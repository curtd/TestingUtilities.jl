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

_show_diff_matching_style_default() = [:color => :green]
_show_diff_differing_style_default() = [:color => :red]

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
    return matching_style_opts, differing_style_opts
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

    return load_show_diff_styles()
end

reset_show_diff_styles() = set_show_diff_styles(; matching=_show_diff_matching_style_default(), differing=_show_diff_differing_style_default())

_show_df_max_nrows_default() = 5 
_show_df_max_ncols_default() = 10 

const show_df_max_nrows_ncols = Ref((_show_df_max_nrows_default(), _show_df_max_ncols_default()))

function load_show_df_max_rows_cols(; max_num_rows::Int=0, max_num_cols::Int=0)
    if max_num_rows ≤ 0
        max_num_rows = @load_preference("show_df.max_num_rows", _show_df_max_nrows_default())::Int
        if max_num_rows ≤ 0
            max_num_rows = _show_df_max_nrows_default()
        end
    end
    if max_num_cols ≤ 0
        max_num_cols = @load_preference("show_df.max_num_cols", _show_df_max_ncols_default())::Int
        if max_num_cols ≤ 0
            max_num_cols = _show_df_max_ncols_default()
        end
    end
    show_df_max_nrows_ncols[] = (max_num_rows, max_num_cols)
    return show_df_max_nrows_ncols[]
end

"""
    set_show_df_opts(; [max_num_rows::Int=0], [max_num_cols::Int=0], [save_preference::Bool=true])

Sets the local maximum # of rows + columns to show when printing `DataFrame` values. 

If non-positive values for `max_num_rows` or `max_num_cols` are provided, these will be set to `max_num_of_rows = 5` and `max_num_cols = 10`, respectively.

If `save_preference == true`, will save this local preference with keys `show_df.max_num_rows`, `show_df.max_num_cols`.
"""
function set_show_df_opts(; max_num_rows::Int=0, max_num_cols::Int=0, save_preference::Bool=true)
    if save_preference && max_num_rows > 0
        @set_preferences!("show_df.max_num_rows" => max_num_rows)
        max_num_rows = 0
    end
    if save_preference && max_num_cols > 0
        @set_preferences!("show_df.max_num_cols" => max_num_cols)
        max_num_cols = 0
    end

    return load_show_df_max_rows_cols(; max_num_rows, max_num_cols)
end

reset_show_df_opts() = set_show_df_opts(; max_num_rows=_show_df_max_nrows_default(), max_num_cols=_show_df_max_ncols_default())

_show_diff_df_max_nrows_default() = 10 
_show_diff_df_max_ncols_default() = 10 

const show_diff_df_max_nrows_ncols = Ref((_show_diff_df_max_nrows_default(), _show_diff_df_max_ncols_default()))

function load_show_diff_df_max_rows_cols(; max_num_rows::Int=0, max_num_cols::Int=0)
    if max_num_rows ≤ 0
        max_num_rows = @load_preference("show_diff_df.max_num_rows", 10)::Int
        if max_num_rows ≤ 0
            max_num_rows = _show_diff_df_max_nrows_default()
        end
    end
    if max_num_cols ≤ 0
        max_num_cols = @load_preference("show_diff_df.max_num_cols", 10)::Int
        if max_num_cols ≤ 0
            max_num_cols = _show_diff_df_max_ncols_default()
        end
    end
    show_diff_df_max_nrows_ncols[] = (max_num_rows, max_num_cols)
    return show_diff_df_max_nrows_ncols[]
end

"""
    set_show_diff_df_opts(; [max_num_rows::Int = 0], [max_num_cols::Int = 0], [save_preference::Bool = true])

Sets the local maximum # of rows + columns to show when printing differences of `DataFrame` values. 

If either `max_num_rows` or `max_num_cols` are non-positive, they will be set to `max_num_rows = 10` and `max_num_cols = 10`, respectively.

If `save_preference == true`, will save this local preference with keys `show_diff_df.max_num_rows`, `show_diff_df.max_num_cols`.
"""
function set_show_diff_df_opts(; max_num_rows::Int=0, max_num_cols::Int=0, save_preference::Bool=true)
    if save_preference && max_num_rows > 0
        @set_preferences!("show_diff_df.max_num_rows" => max_num_rows)
        max_num_rows = 0 
    end
    if save_preference && max_num_cols > 0
        @set_preferences!("show_diff_df.max_num_cols" => max_num_cols)
        max_num_cols = 0
    end

    return load_show_diff_df_max_rows_cols(; max_num_rows, max_num_cols)
end

reset_show_diff_df_opts() = set_show_df_opts(; max_num_rows=_show_diff_df_max_nrows_default(), max_num_cols=_show_diff_df_max_ncols_default())

_default_max_print_length() = 300

const max_length_to_print = Ref(_default_max_print_length())

function load_max_print_length(; max_print_length::Int=0)
    if max_print_length ≤ 0
        max_print_length = @load_preference("max_print_length", _default_max_print_length())::Int
        if max_print_length ≤ 0
            max_print_length = _default_max_print_length()
        end
    end
    max_length_to_print[] = max_print_length
    return max_length_to_print[]
end

"""
    set_max_print_length(; [max_print_length::Int=0], [save_preference::Bool=true])

Sets the local maximum # characters to print for each displayed value in, e.g., a failing test

If `max_print_length` is not provided or if non-positive values are provided, will be set to `max_print_length = 300`

If `save_preference == true`, will save this local preference with key `max_print_length`
"""
function set_max_print_length(; max_print_length::Int=0, save_preference::Bool=true)
    if save_preference && max_print_length > 0
        @set_preferences!("max_print_length" => max_print_length)
        max_print_length = 0
    end
    return load_max_print_length(; max_print_length)
end