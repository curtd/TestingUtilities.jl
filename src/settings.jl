@enum TestingSetting DefineVarsInFailedTests DefineVarsInFailedTestsModule EmitWarnings

const _TESTING_SETTINGS = Dict{TestingSetting, Any}()

function testing_setting(t::TestingSetting)
    if t == DefineVarsInFailedTests
        return get!(_TESTING_SETTINGS, t, true)::Bool
    elseif t == DefineVarsInFailedTestsModule
        return get!(_TESTING_SETTINGS, t, Main)::Module
    elseif t == EmitWarnings
        return get!(_TESTING_SETTINGS, t, false)::Bool
    end
    return nothing
end

"""
    define_vars_in_failed_tests(value::Bool)

If `value` is `true`, variables that cause a `@Test` expression to fail will be defined in `Main` when Julia is run in interactive mode.

Defaults to `true` if unset. 
"""
function define_vars_in_failed_tests(value::Bool) 
    _TESTING_SETTINGS[DefineVarsInFailedTests] = value
    return nothing 
end

should_define_vars_in_failed_tests(should; force::Bool=false) = force || (((!isnothing(should) && should == true) || (isnothing(should) && testing_setting(DefineVarsInFailedTests))) && Base.isinteractive())

"""
    emit_warnings(value::Bool)

If `value` is `true`, emit warning messages in test macros.

Defaults to `false` if unset. 
"""
function emit_warnings(value::Bool) 
    _TESTING_SETTINGS[EmitWarnings] = value
    return nothing 
end

const printstyled_bool_kwargs = (:bold, :underline, :blink, :reverse, :hidden)

const show_diff_matching_style = Pair{Symbol, Any}[:color => :green]

const show_diff_differing_style = Pair{Symbol, Any}[:color => :red]

pref_to_string(p::Pair) = string(first(p)) * "=" * string(last(p))

pref_to_string(p::Vector{<:Pair}) = join([pref_to_string(pi) for pi in p], ",")

function parse_load_styles(str::AbstractString)
    kwargs = Pair{Symbol,Any}[]
    str_split = split(str, ",")
    for s in str_split
        isempty(s) && continue
        s_split = split(s, "=")
        length(s_split) == 2 || error("Cannot parse pair from string $s")
        key = Symbol(s_split[1])
        if key in printstyled_bool_kwargs
            value = tryparse(Bool, s_split[2])
            isnothing(value) && error("Cannot parse Bool for key $key from input $(s_split[1])")
            push!(kwargs, key => value)
        else
            push!(kwargs, key => Symbol(s_split[2]))
        end
    end
    return kwargs
end

function load_show_diff_styles(; 
    matching_style::String = "", 
    differing_style::String = "")
    if isempty(matching_style)
        matching_style = @load_preference("show_diff_matching_style", "")
    end
    matching_style_opts = parse_load_styles(matching_style)
    if !isempty(matching_style_opts)
        copy!(show_diff_matching_style, matching_style_opts)
    end
    if isempty(differing_style)
        differing_style = @load_preference("show_diff_differing_style", "")
    end
    differing_style_opts = parse_load_styles(differing_style)
    if !isempty(differing_style_opts)
        copy!(show_diff_differing_style, differing_style_opts)
    end
    return nothing
end

"""
    set_show_diff_styles(; matching=show_diff_matching_style, differing=show_diff_differing_style)

Sets the local style information for the `show_diff` method, which is invoked when displaying two differing `String` values. 

Both `matching` and `differing` must each be a `Pair` whose keys and values correspond to the keyword arguments of the [`Base.printstyled`](https://docs.julialang.org/en/v1/base/io-network/#Base.printstyled) function, or a `Vector` of such `Pair`s.
"""
function set_show_diff_styles(; matching::Union{Pair, Vector{<:Pair}}=show_diff_matching_style, differing::Union{Pair, Vector{<:Pair}}=show_diff_differing_style)
    if matching isa Pair 
        matching = [matching]
    end
    if differing isa Pair 
        differing = [differing]
    end
    @set_preferences!("show_diff_matching_style" => pref_to_string(matching))
    @set_preferences!("show_diff_differing_style" => pref_to_string(differing))

    load_show_diff_styles()
    return nothing
end