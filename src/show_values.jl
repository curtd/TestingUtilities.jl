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

function show_escape_newlines(io, str::AbstractString; has_colour::Bool=false, is_matching::Bool)
    replaced_str = replace(str, "\n" => "\\n")
    if has_colour 
        if is_matching
            style = NamedTuple(show_diff_matching_style)
        else
            style = NamedTuple(show_diff_differing_style)
        end
        printstyled(io, replaced_str; style...)
    else
        print(io, replaced_str)
    end
end

function show_diff(expected::AbstractString, result::AbstractString; expected_name="expected", result_name="result", io=stderr, compact::Bool=true)
    ctx = IOContext(io, :compact => compact)
    has_colour = get(io, :color, false)
    if startswith(expected, result)
        common_prefix_length = length(result)
        common_prefix = result
    elseif startswith(result, expected)
        common_prefix_length = length(expected)
        common_prefix = expected
    else
        common_prefix_length = something(findfirst(i->expected[i] != result[i], 1:min(length(expected), length(result))), 1)-1
        common_prefix = expected[1:common_prefix_length]
    end
    expected_name_str = string(expected_name)
    expected_width = textwidth(expected_name_str)
    result_name_str = string(result_name)
    result_width = textwidth(result_name_str)
    longest_width = max(expected_width, result_width)
    for (text, text_name, width) in ((expected, expected_name_str, expected_width), (result, result_name_str, result_width))
        print(ctx, text_name, repeat(' ', longest_width-width), " = ")
        print(ctx, '\"')
        show_escape_newlines(ctx, common_prefix; has_colour, is_matching=true)
        show_escape_newlines(ctx, text[common_prefix_length+1:end]; has_colour, is_matching=false)
        println(ctx, '\"')
    end
    flush(ctx)
    return true
end

show_diff(expected, result; kwargs...) = false