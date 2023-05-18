unwrap_if_quotenode(x) = x 
unwrap_if_quotenode(x::QuoteNode) = x.value

"""
    parse_kwarg_expr(exs...) -> Dict{Symbol, Any}

Parse keyword arguments from a series of expressions, either of the form `key=value` or `key`
"""
function parse_kwarg_expr(exs...)
    @nospecialize 

    kwargs = LittleDict{Symbol,Any}(Symbol[], Any[])
    isempty(exs) && return kwargs
    for (i,ex) in enumerate(exs) 
        @switch ex begin
            @case value::QuoteNode || value::Symbol
                kwargs[unwrap_if_quotenode(value)] = (; position=i, value)
            @case :($key=$value)
                k = @match key begin 
                    k::QuoteNode || k::Symbol => unwrap_if_quotenode(k)
                    k => error("In expression $ex, key $(k) must be a QuoteNode or a Symbol, got typeof(key) = $(typeof(k))")
                end
                kwargs[k] = (; position=i, value)
            @case _ 
                error("Argument $ex must be a Symbol, QuoteNode, or Assignment expression")
        end
    end
    return kwargs
end

"""
    fetch_kwarg_expr(args; expected_types, [key, arg_position, default_value])

    Returns the `value` corresponding to `key` derived from `kwargs` and ensure it is of type `expected_types`.

    At least one of `key` and `arg_position` must be provided and `arg_position` takes precedence.

    See also [@parse_kwarg_expr]

# Arguments
- `args::ArgsKwargs` - Parsed keyword argument expressions

# Keyword Arguments
- `expected_type::Union{Vector{<:Type}, Type}` - Allowable types for value 
- `key::Union{Symbol, Nothing}` - Key to fetch 
- `arg_position::Union{Int,Nothing}` - Position argument to fetch
- `default_value=nothing` - Optional default value for `key`. Will throw an `ErrorException` if `key` is not psent in `kwargs` and this value is `nothing`. 
"""
function fetch_kwarg_expr(kwargs::AbstractDict{Symbol,Any}; key::Union{Symbol,Nothing}=nothing, arg_position::Union{Int,Nothing}=nothing, expected_type::Union{Vector{<:Type}, Type}=Any, default_value=nothing)
    expected_types = expected_type isa Vector ? expected_type : [expected_type]
    !(isnothing(key) && isnothing(arg_position)) || error("At least one of key, arg_position must be provided")
    if !(isnothing(arg_position))
        (arg_position ≥ 1 && arg_position ≤ length(kwargs)) || throw(ArgumentError("arg_position (= $arg_position) must be between 1 and $(length(kwargs))"))
        local value 
        for v in values(kwargs)
            if v.position == arg_position
                value = v.value 
                break
            end
        end
    else
        if isnothing(default_value)    
            if !haskey(kwargs, key) 
                if Nothing ∈ expected_types 
                    value = nothing
                else 
                    throw(ArgumentError("key (= $key) not found in keys(kwargs) (= $(keys(kwargs)))"))
                end
            else
                value = kwargs[key].value
            end
        else
            if haskey(kwargs, key)
                value = kwargs[key].value
            else
                value = default_value
            end
        end
    end

    any( value isa t for t in expected_types) || throw(ArgumentError("key (= $key) = value (= $value) must be one of $(expected_types), got typeof(value) = $(typeof(value))")) 
    return value
end
