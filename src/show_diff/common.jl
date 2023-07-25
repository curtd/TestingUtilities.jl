function show_maybe_styled(io, val; has_colour::Bool=false, is_matching::Bool)
    if has_colour 
        if is_matching
            style = NamedTuple(show_diff_matching_style)
        else
            style = NamedTuple(show_diff_differing_style)
        end
        printstyled(io, val; style...)
    else
        print(io, val)
    end
    return nothing
end

function print_spaces(io::IO, num_spaces::Int) 
    if num_spaces > 0
        print(io, repeat(' ', num_spaces))
    end
end

function print_aligned(io::IO, str::AbstractString, width, max_width, separator, justify::Symbol)
    if justify == :left
        print(io, str)
        print_spaces(io, max_width-width)
    elseif justify == :right 
        print_spaces(io, max_width-width)
        print(io, str)
    else
        print(io, str)
    end
    print(io, separator)
end

struct PrintAligned 
    header_strs::Vector{String}
    widths::Vector{Int}
    max_width::Int
    separator::String 
    justify::Symbol
    function PrintAligned(header_strs::Vector{String}; separator::String=" = ", justify::Symbol=:left)
        widths = textwidth.(header_strs)
        max_width = maximum(widths)
        return new(header_strs, widths, max_width, separator, justify) 
    end
end
PrintAligned(header_strs::String...; kwargs...) = PrintAligned(collect(header_strs); kwargs...)

function (p::PrintAligned)(io::IO, i::Int)
    (i < 0 || i > length(p.header_strs)) && throw(BoundsError(p.header_strs, i))
    print_aligned(io, p.header_strs[i], p.widths[i], p.max_width, p.separator, p.justify)
    return nothing
end
Base.eachindex(p::PrintAligned) = eachindex(p.header_strs)

should_ignore_struct_type((@nospecialize x)) = false 
should_print_differing_fields_header((@nospecialize x)) = true

for T in (String, AbstractDict, AbstractVector, AbstractSet)
    @eval should_ignore_struct_type(::Type{<:$T}) = true
    @eval should_print_differing_fields_header(::Type{<:$T}) = false
end

function append_type_str(header, type_str::String)
    if !isempty(type_str)
        return string(header)*"::$type_str"
    else
        return string(header)
    end
end

function header_and_type(header, type_str::String) 
    append_type_str(_show_name_str(header), type_str)
end

abstract type AbstractTypeCategory end 
struct TypeTypeCat <: AbstractTypeCategory end 
struct StructTypeCat <: AbstractTypeCategory end 
struct VectorTypeCat <: AbstractTypeCategory end 
struct DictTypeCat <: AbstractTypeCategory end 
struct SetTypeCat <: AbstractTypeCategory end 
struct GenericTypeCat <: AbstractTypeCategory end 

typecat_description(::TypeTypeCat) = "Type"
typecat_description(::StructTypeCat) = "Struct"
typecat_description(::VectorTypeCat) = "Vector"
typecat_description(::DictTypeCat) = "Dict"
typecat_description(::SetTypeCat) = "Set"
typecat_description(::GenericTypeCat) = "generic value"

function type_category(::Type{T}) where {T}
    if T <: Type
        return TypeTypeCat()
    elseif T <: AbstractVector 
        return VectorTypeCat()
    elseif T <: AbstractDict
        return DictTypeCat()
    elseif T <: AbstractSet
        return SetTypeCat()
    elseif isstructtype(T)
        return StructTypeCat()
    else
        return GenericTypeCat()
    end
end

function show_differing_fieldnames(ctx::IOContext, expected_fields, results_fields; expected_name="expected", expected_type_str::String="", result_name="result", result_type_str::String="")
    has_colour = get(ctx, :color, false)::Bool
    expected_header = "fieldnames($(append_type_str(lstrip(string(expected_name)), expected_type_str)))"
    result_header = "fieldnames($(append_type_str(lstrip(string(result_name)), result_type_str)))"
    println(ctx, "Reason: `", expected_header, " != ", result_header ,'`')
    p = PrintAligned(expected_header, result_header; separator=" = ")
    matching = intersect(expected_fields, results_fields)
    for (i, fields) in enumerate((expected_fields, results_fields))
        p(ctx, i)
        print(ctx, '(')
        for field in fields
            show_maybe_styled(ctx, ":$field"; has_colour=has_colour, is_matching=field in matching)
        end
        println(ctx, ')')
    end
    return nothing
end

function show_diff(expected, result; io=stderr, compact::Bool=true, kwargs...)
    return show_diff(IOContext(io, :compact=>compact), expected, result; kwargs...)
end

function show_diff_header(value, value_name, value_type_str::String; show_type_str::Bool=false)
    if show_type_str && isempty(value_type_str)
        value_type_str = string(typeof(value))
    end
    return header_and_type(value_name, value_type_str)
end

function show_diff_mismatched_type_cat(ctx::IOContext, expected_type_category, expected, expected_type, result_type_category, result, result_type; expected_name, result_name)
    has_colour = get(ctx, :color, false)::Bool
    expected_header = show_diff_header(expected, expected_name, string(expected_type); show_type_str=true)
    result_header = show_diff_header(result, result_name, string(result_type); show_type_str=true)
    println(ctx, "Reason: Mismatched type categories")
    show_maybe_styled(ctx, "$expected_header is a $(typecat_description(expected_type_category)), but $result_header is a $(typecat_description(result_type_category))"; has_colour=has_colour, is_matching=false)
    println(ctx)
end

function show_diff(ctx::IOContext, expected, result; expected_name="expected", result_name="result", kwargs...)
    expected_type = typeof(expected)
    result_type = typeof(result)
    expected_typecat = type_category(expected_type)
    result_typecat = type_category(result_type)
    if expected_typecat == result_typecat
        return show_diff(expected_typecat, ctx, expected, result; expected_name=expected_name, result_name=result_name, kwargs...)
    else
        return show_diff_mismatched_type_cat(ctx, expected_typecat, expected, expected_type, result_typecat, result, result_type; expected_name=expected_name, result_name=result_name)
    end
end

function show_diff_generic(ctx::IOContext, expected, result; expected_name="expected", expected_type_str::String="", result_name="result", result_type_str::String="", show_type_str::Bool=false, justify_headers::Symbol=:left, kwargs...)
    expected_header = show_diff_header(expected, expected_name, expected_type_str; show_type_str=show_type_str)
    result_header = show_diff_header(result, result_name, result_type_str; show_type_str=show_type_str)
   
    p = PrintAligned(expected_header, result_header; separator=" = ", justify=justify_headers)
    for (i, value) in enumerate((expected, result))
        p(ctx, i)
        show_value(ctx, value; kwargs...)
    end
    
    return nothing
end

show_diff(::AbstractTypeCategory, ctx::IOContext, expected, result; expected_name="expected", result_name="result", kwargs...) = show_diff_generic(ctx::IOContext, expected, result; expected_name=expected_name, result_name=result_name, justify_headers=:none, kwargs...)