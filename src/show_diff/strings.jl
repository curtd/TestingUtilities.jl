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

function show_diff(ctx::IOContext, expected::AbstractString, result::AbstractString; expected_name="expected", result_name="result", show_type_str::Bool=false, expected_type_str::String="", result_type_str::String="", results_printer::Union{TestResultsPrinter, Nothing}=nothing, justify_headers::Symbol=:left, kwargs...)
    if !isnothing(results_printer)
        print_header!(results_printer, TestValues())
    end
    expected_header = show_diff_header(expected, expected_name, expected_type_str; show_type_str=show_type_str)
    result_header = show_diff_header(result, result_name, result_type_str; show_type_str=show_type_str)

    has_colour = get(ctx, :color, false)
    
    prefix, expected_rest, result_rest = common_prefix(expected, result) 
   
    p = PrintAligned(expected_header, result_header; separator=" = ", justify=justify_headers)
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