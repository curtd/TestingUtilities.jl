function differing_fields(expected, expected_fields, result, result_fields; use_isequals_equality::Bool=true)
    common_fields = intersect(expected_fields, result_fields)
    fields = Symbol[]
    f = use_isequals_equality ? Base.isequal : Base.:(==)
    for field in common_fields
        if !(f(getfield(expected, field), getfield(result, field))::Bool) 
            push!(fields, field)
        end
    end 
    return fields 
end

function show_diff(::IsStructType, ctx::IOContext, expected, result; expected_name="expected", result_name="result", use_isequals_equality::Bool=true, field_index::Vector{Symbol}=Symbol[], recurse::Bool=true, kwargs...)
    T_expected = typeof(expected)
    T_expected_str = string(T_expected)
    T_result = typeof(result)
    T_result_str = string(T_result)
   
    expected_fields = fieldnames(T_expected)
    result_fields = fieldnames(T_result)
    expected_name_str = string(expected_name)
    result_name_str = string(result_name)
    if ( expected_len = length(expected_name_str); result_len = length(result_name_str); expected_len > result_len)
        result_name_str = lpad(result_name_str, expected_len)
    elseif (expected_len < result_len)
        expected_name_str = lpad(expected_name_str, result_len)
    end
    if expected_fields != result_fields
        show_differing_fieldnames(ctx, expected_fields, result_fields; expected_name=expected_name_str, expected_type_str=T_expected_str,  result_name=result_name_str, result_type_str=T_result_str)
        return nothing
    end
    show_diff_generic(ctx, expected, result; expected_name=expected_name_str, result_name=result_name_str, expected_type_str=T_expected_str, result_type_str=T_result_str)

    if recurse && !isempty(expected_fields) && !should_ignore_struct_type(T_expected) && !should_ignore_struct_type(T_result)
        fields = differing_fields(expected, expected_fields, result, result_fields; use_isequals_equality=use_isequals_equality)
        if isempty(fields)
            println(ctx, "Reason: `$expected_name_str::$T_expected_str and $result_name_str::$T_result_str have no differing fields, but are still not equal according to Base.$(use_isequals_equality ? :isequal : :(==)) -- an explicit method definition for this equality operator may not have been provided for these types`")
        else
            for field in fields
                expected_field = getfield(expected, field)
                results_field = getfield(result, field)
                field_indices = vcat(field_index, field)
                field_indices_str = string.(field_indices)
                expected_field_name = expected_name_str * "." * join(field_indices_str, '.')
                result_field_name = result_name_str * "." * join(field_indices_str, '.')

                println(ctx)    
                
                show_diff(ctx, expected_field, results_field; expected_name=expected_field_name, result_name=result_field_name, use_isequals_equality=use_isequals_equality, fieldindex=field_indices, recurse=recurse, show_type_str=true)
            end
        end
    end
    return nothing
end
