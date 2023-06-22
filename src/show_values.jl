function show_value(value; io=stderr, compact::Bool=true)
    ctx = IOContext(io, :compact => compact)
    println(ctx, repr(value))
    flush(ctx)
end

function show_value(name, value; io=stderr, compact::Bool=true)
    ctx = IOContext(io, :compact => compact)
    if name isa Expr
        print(ctx, "`")
        Base.show_unquoted(ctx, name)
        print(ctx, "`")
    else
        Base.show_unquoted(ctx, name)
    end
    print(ctx, " = ")
    println(ctx, repr(value))
    flush(ctx)
end

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

function show_diff(expected::AbstractString, result::AbstractString; expected_name="expected", result_name="result", io=stderr, compact::Bool=true, print_values_header::Union{PrintHeader,Nothing}=nothing)
    ctx = IOContext(io, :compact => compact)
    if !isnothing(print_values_header) && !has_printed(print_values_header)
        print_values_header(ctx)
    end
    has_colour = get(io, :color, false)
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

show_diff(expected, result; kwargs...) = false