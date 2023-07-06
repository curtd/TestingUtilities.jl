const supported_exprs = (:tuple, :vect, :vcat, :hcat, :ref, :., :..., :generator, :filter)

# From https://docs.julialang.org/en/v1/base/base/#Keywords
const reserved_syntax = (:baremodule, :begin, :break, :catch, :const, :continue, :do, :else, :elseif, :end, :export, :false, :finally, :for, :function, :global, :if, :import, :let, :local, :macro, :module, :quote, :return, :struct, :true, :try, :using, :while, :!, :(:), :(::), :(^))

is_reserved_syntax(x) = x isa Symbol && x in reserved_syntax
is_ignored_symbol(x) = x isa Symbol && (hasproperty(Core, x) || hasproperty(Base, x))
is_supported_expr(expr) = expr isa Expr && expr.head in supported_exprs
is_splat_expr(expr) = expr isa Expr && expr.head === :...
iscall(expr) = Meta.isexpr(expr, :call) && !isempty(expr.args)
isref(expr) = Meta.isexpr(expr, :ref) && !isempty(expr.args)

function is_atom(x)
    @switch x begin 
        @case ::Bool || ::Float64 || ::Int || ::String || ::QuoteNode || ::Char
            return true 
        @case Expr(:quote, arg)
            return true
        @case Expr(:$, arg) || Expr(:escape, arg)
            return is_atom(arg)
        @case Expr(:kw, lhs, rhs)
            return is_atom(rhs)
        @case Expr(:tuple)
            return true 
        @case Expr(head, args...) 
            head ∉ (:tuple, :&&, :||, :vect, :vcat, :hcat, :ncat) && return false
            is_lit = @switch args[1] begin 
                @case Expr(:parameters, kwargs...)
                    for kwarg in kwargs
                        !is_atom(kwarg.args[2]) && return false
                    end
                    true
                @case _
                    is_atom(args[1])
            end
            !is_lit && return false
            for arg in args[2:end] 
                !is_atom(arg) && return false
            end
            return true 
        @case _
            return false
    end
end

function should_recurse_children(x)
    @switch x begin 
        @case ::QuoteNode 
            return false
        @case Expr(head, args...) && if head in (:macrocall, ) end 
            return false
        @case _ 
            return !is_atom(x)
    end
end

safe_insert!(d, k, v) = !haskey(d, k) ? d[k] = v : nothing


Base.@kwdef struct MappedArg
    name::Symbol
    kwarg_key::Symbol = Symbol("")
    is_splat::Bool
end

function parse_kwargs!(kwargs, expr)
    @switch expr begin 
        @case Expr(:parameters, args...)
            for arg in args 
                if arg isa Symbol 
                    push!(kwargs, arg => arg)
                else
                    parse_kwargs!(kwargs, arg)
                end
            end
            return true
        @case Expr(:kw, k, v) || Expr(:(=), k, v)
            push!(kwargs, k => v)
            return true
        @case _ 
            return false
    end
end

function parse_args_kwargs!(args, kwargs, expr_args)
    for arg in expr_args 
        if !parse_kwargs!(kwargs, arg)
            push!(args, arg)
        end
    end
    return nothing
end

function parse_args_kwargs(call_expr)
    args = []
    kwargs = []
    (call_func, expr_args) = @switch call_expr begin 
        @case Expr(:call, call_func, expr_args...) 
            call_func, expr_args
        @case Expr(:vect, expr_args...)
            :(Base.vect), expr_args
        @case Expr(head, expr_args...) && if head ∉ (:block, ) end
            head, expr_args
        @case expr 
            error("Unrecognized argument in call_expr (= $call_expr) -- $expr")
    end
    parse_args_kwargs!(args, kwargs, expr_args)
    return call_func, args, kwargs
end

function find_in_current_graph(current_graph, expr)
    matching_key = nothing 
    for (k,v) in pairs(current_graph)
        if isequal(v, expr)
            matching_key = k 
            break
        end
    end
    return matching_key
end

Base.@kwdef mutable struct ArgCounter
    starting_count::Int 
    num_new_args::Int = 0
    num_new_kwargs::Int = 0
end

ArgCounter(current_graph) = ArgCounter(; starting_count=length(current_graph)-1)

function new_arg!(counter::ArgCounter; is_kwarg::Bool=false)
    if is_kwarg
        counter.num_new_kwargs += 1
        new_arg = Symbol("kwarg"*string(counter.starting_count+counter.num_new_args+counter.num_new_kwargs))
    else
        counter.num_new_args += 1
        new_arg = Symbol("arg"*string(counter.starting_count+counter.num_new_args))
    end
    return new_arg
end

function new_arg_if_not_exists!(arg_counter::ArgCounter, current_graph, expr; is_kwarg::Bool=false)
    existing_key = find_in_current_graph(current_graph, expr)
    output_arg = isnothing(existing_key) ? new_arg!(arg_counter; is_kwarg) : existing_key 
    return output_arg, existing_key
end

function _computational_graph_generator_expr!(arg_counter, current_graph, children, expr)
    @switch expr begin 
        @case Expr(:generator, body, forexprs...)
            new_arg_expr = Expr(:generator, body)
            for forexpr in forexprs 
                push!(new_arg_expr.args, _computational_graph_generator_expr!(arg_counter, current_graph, children, forexpr))
            end
            return new_arg_expr
        @case Expr(:(=), var, collection)
            new_arg, existing_key = new_arg_if_not_exists!(arg_counter, current_graph, collection)
            if isnothing(existing_key) 
                safe_insert!(current_graph, new_arg, collection)
                if collection isa Expr 
                    push!(children, collection)
                end
            end
            return Expr(:(=), var, new_arg)
        @case Expr(:filter, cond, collection)
            return Expr(:filter, cond, _computational_graph_generator_expr!(arg_counter, current_graph, children, collection))
        @case _ 
            error("Could not parse subexpression $(expr) -- not a generator, filter, or assignment expression")
    end
end

function args_kwargs(expr)
    ((expr isa Symbol) || any(Meta.isexpr(expr, k) for k in (:if, :curly, :->, :function, :quote, :macrocall))) && @goto exit_early
        
    call_func, args, kwargs = parse_args_kwargs(expr)

    (isnothing(call_func) || call_func === :... || call_func === :.) && @goto exit_early
    return (call_func, args, kwargs), false

    @label exit_early 
    return nothing, true
end

function _computational_graph!(current_graph, expr)
    children = Any[]
    children_kwargs = Any[]

    parsed_values, exit_early = args_kwargs(expr)
    exit_early && @goto exit 
    call_func, args, kwargs = parsed_values 
    matching_key = find_in_current_graph(current_graph, expr)
    
    arg_counter = ArgCounter(current_graph)
    new_args = []
    new_kwargs = []
    for arg in args
        should_ignore_arg = is_atom(arg) || is_reserved_syntax(arg) || is_ignored_symbol(arg)
        if !should_ignore_arg && (arg isa Symbol || arg isa Expr)
            if Meta.isexpr(arg, :generator)
                new_arg_expr = _computational_graph_generator_expr!(arg_counter, current_graph, children, arg)
                push!(new_args, new_arg_expr)
            else
                is_splat = is_splat_expr(arg)
                new_arg, existing_key = new_arg_if_not_exists!(arg_counter, current_graph, arg)
                arg_data = MappedArg(; name=new_arg, is_splat)
                push!(new_args, arg_data)

                if isnothing(existing_key)
                    to_insert = is_splat_expr(arg) ? arg.args[1] : arg 
                    push!(children, to_insert)
                    safe_insert!(current_graph, new_arg, to_insert)
                end
            end
        else 
            if !should_ignore_arg 
                push!(children, arg)
            end
            push!(new_args, arg)
        end
    end
    
    for kwarg in kwargs
        if isa(kwarg, Pair) 
            k, v = kwarg
            no_children = is_atom(v) || is_ignored_symbol(v) || v isa QuoteNode
            should_skip = is_reserved_syntax(v) || no_children
            if !should_skip || v isa Expr 
                new_kwarg, existing_key = new_arg_if_not_exists!(arg_counter, current_graph, v; is_kwarg=true)
                arg_data = MappedArg(; kwarg_key=k, name=new_kwarg, is_splat=false)
                if isnothing(existing_key)
                    safe_insert!(current_graph, new_kwarg, v)
                    push!(children_kwargs, v)
                end
            elseif no_children
                arg_data = k => v
            else
                arg_data = MappedArg(; kwarg_key=k, name=k, is_splat=false)
                push!(children_kwargs, k)
            end
            push!(new_kwargs, arg_data)
        end
    end
    if call_func in (:ref, :., :generator) 
        new_call_expr = Expr(call_func)
    else
        new_call_expr = Expr(:call, call_func)
    end
   
    if !isempty(new_kwargs)
        new_kwarg_expr = Expr(:parameters, [kv isa MappedArg ? Expr(:kw, kv.kwarg_key, kv.name) : Expr(:kw, first(kv), last(kv)) for kv in new_kwargs]...)
        push!(new_call_expr.args, new_kwarg_expr)
    end

    append!(children, children_kwargs)

    for new_arg in new_args
        if new_arg isa MappedArg 
            if new_arg.is_splat 
                push!(new_call_expr.args, Expr(:..., new_arg.name))
            else
                push!(new_call_expr.args, new_arg.name)
            end
        else
            push!(new_call_expr.args, new_arg)
        end
    end

    current_graph[matching_key] = new_call_expr
    @label exit
    return children
end

function walk_expr!(graph, ex)
    children = _computational_graph!(graph, ex)
    for arg in children
        if Meta.isexpr(arg, :parameters) 
            for _arg in arg.args 
                if Meta.isexpr(_arg, :kw)
                    walk_expr!(graph, _arg.args[2])
                else
                    walk_expr!(graph, _arg)
                end
            end
        elseif Meta.isexpr(arg, :kw) 
            if arg.args[2] isa Expr 
                walk_expr!(graph, arg.args[2])
            end
        elseif arg isa Expr
            walk_expr!(graph, arg)
        end
    end
    return nothing
end

walk_expr!(graph, ex::Symbol) = nothing

function computational_graph(expr)
    graph = OrderedDict{Any, Any}()
    graph[_DEFAULT_TEST_EXPR_KEY] = expr
    walk_expr!(graph, expr)
    return graph
end

computational_graph(sym::Symbol) = return OrderedDict{Any,Any}(_DEFAULT_TEST_EXPR_KEY => sym)