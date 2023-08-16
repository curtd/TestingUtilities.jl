function module_using_names(m::Module=Main)
    _modules = ccall(:jl_module_usings, Any, (Any,), m)
    output = Set{Symbol}(names(m, imported=true))
    for _mod in _modules 
        union!(output, Set{Symbol}(names(_mod)))
    end
    return output
end

const imported_names_in_main = Ref(Set{Symbol}())

update_imported_names_in_main() = imported_names_in_main[] = module_using_names(Main) 

function unescape(x)
    @switch x begin 
        @case Expr(:$, arg) || Expr(:escape, arg)
            return unescape(arg)
        @case _ 
            return x
    end
end

struct PrintHeader
    header::String
    printed::Ref{Bool}
end
PrintHeader(str::String) = PrintHeader(str, Ref(false))

has_printed(p::PrintHeader) = p.printed[]
function (p::PrintHeader)(io::IO)
    if !has_printed(p)
        println(io, p.header)
        p.printed[] = true
    end
    return p.printed[]
end

mutable struct TaskFinishedTimer{T}
    timer::Union{Nothing, Timer}
    cb_func::Any
    cb_task::Union{Nothing, Task}
    channel::Channel{T}
    error_channel::Channel
    last_awoken::DateTime
    cumul_time::Millisecond
    sleep_time::Millisecond
    max_time::Millisecond
    name::String
end

function Base.show(io::IO, t::TaskFinishedTimer{T}) where {T}
    print(io, "TaskFinishedTimer($T)")
    if !isnothing(t.cb_task)
        print(io, ", task running = $(istaskstarted(t.cb_task) && !istaskdone(t.cb_task))")
        print(io, ", time elapsed = ($(t.cumul_time) / $(t.max_time))")
    end
end

is_timed_out(t::TaskFinishedTimer) = t.cumul_time ≥ t.max_time

function check_task_done!(t::TaskFinishedTimer)
    last_awoken = t.last_awoken
    currently = Dates.now()
    t.cumul_time += (currently - last_awoken)
    t.last_awoken = currently
    if isready(t.channel) || istaskdone(t.cb_task) || is_timed_out(t)
        close(t.timer)
    end
    return nothing
end


function TaskFinishedTimer(max_time::Millisecond, sleep_time::Millisecond,  return_type::Type{T}, cb::Function, args...; timer_name::String="") where {T}
    ch = Channel{T}(1)
    error_ch = Channel(1)
    cb_func = let ch=ch, error_ch=error_ch, cb=cb, args=args
        function ()
            try 
                put!(ch, cb(args...))
            catch e 
                put!(error_ch, (e, catch_backtrace()))
                rethrow(e)
            end
        end
    end
    t = TaskFinishedTimer(nothing, cb_func, nothing, ch, error_ch, DateTime(0,1,1), Millisecond(0), sleep_time, max_time, timer_name)
    return t
end

TaskFinishedTimer(max_time::Dates.Period, sleep_time::Dates.Period, args...; kwargs...) = TaskFinishedTimer(Millisecond(max_time), Millisecond(sleep_time), args...; kwargs...)

TaskFinishedTimer(::Type{T}, cb::Function, args...; max_time::Dates.Period, sleep_time::Dates.Period, timer_name::String="") where {T} = TaskFinishedTimer(max_time, sleep_time, T, cb, args...; timer_name)

TaskFinishedTimer(cb::Function, args...; kwargs...) = TaskFinishedTimer(Any, cb, args...; kwargs...)

# At the end of this function, either the callback task has completed or the timer has expired
function Base.wait(t::TaskFinishedTimer)
    if isnothing(t.cb_task) || (istaskdone(t.cb_task))
        t.cb_task = Task(t.cb_func)
    end
    if !istaskstarted(t.cb_task)
        schedule(t.cb_task)
    end
    if isnothing(t.timer) || (!isopen(t) && !is_timed_out(t))
        interval = Dates.value(t.sleep_time) / Dates.value(Millisecond(Second(1)))
        if isnothing(t.timer)
            t.cumul_time = Millisecond(0)
        end
        t.last_awoken = now()
        t.timer = Timer(0.0; interval=interval)
    end
    while isopen(t) && !is_timed_out(t) 
        wait(t.timer)
        check_task_done!(t)
    end
    return nothing
end

Base.isopen(t::TaskFinishedTimer) = isopen(t.timer)

function Base.fetch(t::TaskFinishedTimer{T}; throw_error::Bool=true) where {T}
    isready(t.channel) && return take!(t.channel)::T
    !isnothing(t.cb_task) && istaskfailed(t.cb_task) && fetch(t.cb_task)
    wait(t)
    if isready(t.channel)
        return take!(t.channel)::T
    elseif istaskfailed(t.cb_task)
        return fetch(t.cb_task)
    elseif is_timed_out(t)
        throw_error && throw(TaskTimedOutException(t))
        return nothing
    end
end

function remove_linenums!(ex)
    @switch ex begin 
        @case Expr(:macrocall, name, lnn, args...)
            ex.args[2] = nothing
            return nothing
        @case Expr(:block, args...)
            to_remove = Int[]
            for (i,arg) in enumerate(args )
                if arg isa LineNumberNode
                    push!(to_remove, i)
                else
                    remove_linenums!(arg)
                end
            end
            deleteat!(ex.args, to_remove)
            return nothing
        @case Expr(head, args...)
            for arg in args 
                remove_linenums!(arg)
            end
        @case _
            return nothing
    end
end

function remove_linenums(ex::Expr)
    new_ex = deepcopy(ex)
    remove_linenums!(new_ex)
    return new_ex
end