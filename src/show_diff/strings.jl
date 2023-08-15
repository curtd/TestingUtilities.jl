function show_escape_newlines(io, str::AbstractString; has_colour::Bool=false, is_matching::Bool)
    replaced_str = replace(str, "\n" => "\\n")
    return show_maybe_styled(io, replaced_str; has_colour, is_matching)
end

const no_prefix = SubString("")

function common_prefix(a::AbstractString, b::AbstractString)
    (isempty(a) || isempty(b)) && return no_prefix, a, b
    a_itr, b_itr = eachindex(a), eachindex(b)
    i, j = iterate(a_itr), iterate(b_itr)
    a_prefix_end = nothing
    b_prefix_end = nothing
    while true 
        (i === nothing || j === nothing) && break 
        a_index, a_state = i
        b_index, b_state = j
        a[a_index] == b[b_index] || break 
        a_prefix_end = a_index
        b_prefix_end = b_index
        i, j = iterate(a_itr, a_state), iterate(b_itr, b_state)
    end
    prefix = !isnothing(a_prefix_end) ? SubString(a, firstindex(a), a_prefix_end) : no_prefix
    if isnothing(a_prefix_end) 
        a_rest = SubString(a)
    elseif a_prefix_end != lastindex(a)
        a_rest = @view a[nextind(a, a_prefix_end):end]
    else
        a_rest = nothing
    end
    if isnothing(b_prefix_end) 
        b_rest = SubString(b)
    elseif b_prefix_end != lastindex(b)
        b_rest = @view b[nextind(b, b_prefix_end):end]
    else
        b_rest = nothing
    end
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