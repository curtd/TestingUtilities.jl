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
    if istaskdone(t.cb_task) || is_timed_out(t)
        close(t.timer)
    end
    return nothing
end

"""

"""
function TaskFinishedTimer(max_time::Millisecond, sleep_time::Millisecond,  return_type::Type{T}, cb::Function, args...; timer_name::String="") where {T}
    ch = Channel{T}(1)
    error_ch = Channel(1)
    run_cb = let ch=ch, error_ch=error_ch, cb=cb, args=args
        function ()
            try 
                put!(ch, cb(args...))
            catch e 
                put!(error_ch, (e, catch_backtrace()))
                rethrow(e)
            end
        end
    end
    cb_task = Task(run_cb)
    t = TaskFinishedTimer(nothing, cb_task, ch, error_ch, DateTime(0,1,1), Millisecond(0), sleep_time, max_time, timer_name)
    return t
end

TaskFinishedTimer(::Type{T}, cb::Function, args...; max_time::Millisecond, sleep_time::Millisecond, timer_name::String="") where {T} = TaskFinishedTimer(max_time, sleep_time, T, cb, args...; timer_name)

TaskFinishedTimer(cb::Function, args...; kwargs...) = TaskFinishedTimer(Any, cb, args...; kwargs...)

function Base.wait(t::TaskFinishedTimer)
    if !isnothing(t.cb_task) && !istaskstarted(t.cb_task)
        schedule(t.cb_task)
    end
    if isnothing(t.timer)
        interval = Dates.value(t.sleep_time) / Dates.value(Millisecond(Second(1)))
        t.cumul_time = Millisecond(0)
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
    isready(t.channel) && take!(t.channel)::T
    istaskfailed(t.cb_task) && fetch(t.cb_task)
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