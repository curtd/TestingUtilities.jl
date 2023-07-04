function _show_name(ctx, name)
    if name isa Expr
        io = IOBuffer()
        print(io, "`")
        Base.show_unquoted(io, name)
        print(io, "`")
        _name = String(take!(io))
    else
        _name = string(name)
    end
    print(ctx, _name)
    return textwidth(_name)
end

function show_value(ctx::IOContext, value::Ref; kwargs...)
    println(ctx, "Ref(")
    result = show_value(ctx, value[]; kwargs...)
    println(ctx, ")")
    return result
end

function show_value(ctx::IOContext, value; kwargs...)
    println(ctx, repr(value))
    flush(ctx)
    return nothing
end

show_value(io::IO, value; compact::Bool=true, kwargs...) = show_value(IOContext(io, :compact => compact), value; kwargs...)
show_value(value; io=stderr, kwargs...) = show_value(io, value; kwargs...)

function show_indented(show_value_func, ctx::IOContext, _displaysz::Tuple{Int,Int}, value; indent::Int, kwargs...)
    io_indented = IOBuffer()
    ioc_indented = IOContext(io_indented, 
        :displaysize => (_displaysz[1], max(1, _displaysz[2] - indent)), 
        :compact => get(ctx, :compact, false)::Bool
    )
    show_value_func(ioc_indented, value; kwargs...)
    indented = String(take!(io_indented))
    indent_str = ' '^indent
    indented_s = split(indented, "\n")
    for (i,line) in enumerate(indented_s)
        if i > 1 
            println(ctx)
            if i < length(indented_s) || !isempty(line)
                print(ctx, indent_str, line)
            end
        else 
            print(ctx, line)
        end
    end
    return length(indented_s) > 1
end

function show_name_value(show_value_func, ctx::IOContext, name, value; kwargs...)
    name_width = _show_name(ctx, name)
    print(ctx, " = ")
    name_width += 3 
    return show_indented(show_value_func, ctx, displaysize(ctx), value; indent=name_width, kwargs...)
end

function show_name_value(show_value_func, ctx::IOContext, name, value::Ref; kwargs...)
    name_width = _show_name(ctx, name)
    print(ctx, "[] = ")
    name_width += 5
    return show_indented(show_value_func, ctx, displaysize(ctx), value[]; indent=name_width, kwargs...)
end


show_name_value(io::IOContext, name, value; kwargs...) = show_name_value(show_value, io, name, value; kwargs...)

show_name_value(io::IO, name, value; compact::Bool=true, kwargs...) = show_name_value(IOContext(io, :compact => compact), name, value; kwargs...)

show_value(name, value; io=stderr, kwargs...) = show_name_value(io, name, value; kwargs...)

struct PrintAligned 
    header_strs::Vector{String}
    widths::Vector{Int}
    max_width::Int
    separator::String 
    function PrintAligned(header_strs::Vector{String}; separator::String=" = ")
        widths = textwidth.(header_strs)
        max_width = maximum(widths)
        return new(header_strs, widths, max_width, separator) 
    end
end
PrintAligned(header_strs::String...; kwargs...) = PrintAligned(collect(header_strs); kwargs...)

function (p::PrintAligned)(io::IO, i::Int)
    (i < 0 || i > length(p.header_strs)) && throw(BoundsError(p.header_strs, i))
    print(io, p.header_strs[i], repeat(' ', p.max_width-p.widths[i]), p.separator)
    return nothing
end
Base.eachindex(p::PrintAligned) = eachindex(p.header_strs)

function show_maybe_styled(io, str::AbstractString; has_colour::Bool=false, is_matching::Bool)
    if has_colour 
        if is_matching
            style = NamedTuple(show_diff_matching_style)
        else
            style = NamedTuple(show_diff_differing_style)
        end
        printstyled(io, str; style...)
    else
        print(io, str)
    end
    return nothing
end

function show_escape_newlines(io, str::AbstractString; has_colour::Bool=false, is_matching::Bool)
    replaced_str = replace(str, "\n" => "\\n")
    return show_maybe_styled(io, replaced_str; has_colour, is_matching)
end

function common_prefix(a::AbstractString, b::AbstractString)
    a_itr, b_itr = eachindex(a), eachindex(b)
    i, j = iterate(a_itr), iterate(b_itr)
    common_prefix_length = 0
    while true 
        (i === nothing || j === nothing) && break 
        a[i[1]] == b[j[1]] || break 
        common_prefix_length += 1
        i, j = iterate(a_itr, i[2]), iterate(b_itr, j[2])
    end
    prefix = SubString(a, 1, common_prefix_length)
    a_rest = !isnothing(i) ? (@view a[i[1]:end]) : nothing 
    b_rest = !isnothing(j) ? (@view b[j[1]:end]) : nothing 
    return prefix, a_rest, b_rest
end

function show_diff(expected::AbstractString, result::AbstractString; expected_name="expected", result_name="result", io=stderr, compact::Bool=true, results_printer::Union{Nothing, TestResultsPrinter}=nothing)
    ctx = IOContext(io, :compact => compact)
    has_colour = get(io, :color, false)
    if !isnothing(results_printer)
        print_header!(results_printer, TestValues())
    end
    prefix, expected_rest, result_rest = common_prefix(expected, result) 

    p = PrintAligned(string(expected_name), string(result_name); separator=" = ")
    for (rest, i) in zip((expected_rest, result_rest), eachindex(p))
        p(ctx, i)
        print(ctx, '\"')
        show_escape_newlines(ctx, prefix; has_colour, is_matching=true)
        if !isnothing(rest)
            show_escape_newlines(ctx, rest; has_colour, is_matching=false)
        end
        println(ctx, '\"')
    end
    flush(ctx)
    return true
end

will_show_diff(expected::AbstractString, result::AbstractString) = true

show_diff(expected, result; kwargs...) = nothing

will_show_diff(expected, result) = false

function maybe_show_diff!(already_shown, failed_testdata; io::IO)
    if haskey(failed_testdata, _SHOW_DIFF)
        data = failed_testdata[_SHOW_DIFF]
        key1, key2 = data.keys
        value1, value2 = data.values
        if show_diff(value1, value2; expected_name=key1, result_name=key2, io, print_values_header)
            push!(already_shown, key1, key2)
        end
        push!(already_shown, _SHOW_DIFF)
        return true
    else
        return false
    end
end