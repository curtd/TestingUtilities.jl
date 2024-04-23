struct TestFailed end 

struct TestTimedOut
    timeout::Millisecond 
end

struct TestValues end

struct TestResultsPrinter 
    io::IO
    original_ex::String
    printed_headers::Set{Symbol}
    values_already_shown::Set{Any}
    use_isequals_equality::Bool
end    

function TestResultsPrinter(io::IO, original_ex::String; use_isequals_equality::Bool=true)
    return TestResultsPrinter(io, original_ex, Set{Symbol}(), Set{Any}([_DEFAULT_TEST_EXPR_KEY]), use_isequals_equality)
end

function TestResultsPrinter(io::IO, original_ex::Expr; kwargs...)
    if Meta.isexpr(original_ex, :if, 3)
        original_ex_str = "`$(original_ex.args[1]) ? $(original_ex.args[2]) : $(original_ex.args[3])`"
    else
        original_ex_str = show_value_str(original_ex; remove_line_nums=true, use_backticks=true)
    end
    return TestResultsPrinter(io, original_ex_str; kwargs...)
end

TestResultsPrinter(io::IO, original_ex::Symbol; kwargs...) = TestResultsPrinter(io, "`$original_ex`"; kwargs...)
TestResultsPrinter(io::IO, original_ex; kwargs...) = TestResultsPrinter(io, string(original_ex); kwargs...)

function print_header!(p::TestResultsPrinter, ::TestFailed)
    if :toplevel_failed ∉ p.printed_headers
        println(p.io, "Test ", p.original_ex, " failed:")
        push!(p.printed_headers, :toplevel_failed)
    end
    return nothing
end

function print_header!(p::TestResultsPrinter, t::TestTimedOut)
    print_header!(p, TestFailed())
    if :toplevel_timeout ∉ p.printed_headers
        println(p.io, "Reason: Test took longer than $(t.timeout) to pass")
        push!(p.printed_headers, :toplevel_timeout)
    end
    return nothing
end

function print_header!(p::TestResultsPrinter, ::TestValues)
    if :values ∉ p.printed_headers
        println(p.io, "Values:")
        push!(p.printed_headers, :values)
    end
    return nothing
end

function print_show_diff!(p::TestResultsPrinter, failed_test_data)
    if haskey(failed_test_data, _SHOW_DIFF)
        print_header!(p, TestFailed())
        data = failed_test_data[_SHOW_DIFF]
        key1, key2 = data.keys
        value1, value2 = data.values
        if (T_key1 = typeof(value1); T_key2 = typeof(value2); ((type_category(T_key1) == StructTypeCat()) && (type_category(T_key2) == StructTypeCat()) && should_print_differing_fields_header(T_key1) && should_print_differing_fields_header(T_key2)))
            println(p. io, "Differing fields between `$(key1)` and `$(key2)`:\n")
            show_type_str = true
        else 
            show_type_str = false
        end
        show_diff(value1, value2; expected_name=key1, result_name=key2, io=p.io, results_printer=p, show_type_str=show_type_str)
        push!(p.values_already_shown, key1, key2)
        push!(p.values_already_shown, _SHOW_DIFF)
    end
end

has_printed(p::TestResultsPrinter) = :finished in p.printed_headers

function _print_failed_test_data(p::TestResultsPrinter, failed_test_data, test_input_data)
    print_show_diff!(p, failed_test_data)
    for D in (failed_test_data, test_input_data)
        for (k,v) in pairs(D)
            k ∈ p.values_already_shown && continue 
            if k isa Tuple 
                ref_k = :($(k[1]) = $(k[2]))
            else
                ref_k = k 
            end
            if !isnothing(ref_k)
                print_header!(p, TestValues())
                show_value(ref_k, v; io=p.io)
            end
            push!(p.values_already_shown, k)
        end
    end
    push!(p.printed_headers, :finished)
end

function print_Test_data!(p::TestResultsPrinter, failed_test_data, test_input_data)
    print_header!(p, TestFailed())
    _print_failed_test_data(p, failed_test_data, test_input_data)
    return nothing
end

function print_testeventually_data!(p::TestResultsPrinter, max_time, failed_test_data, test_input_data)
    print_header!(p, TestTimedOut(max_time))
    _print_failed_test_data(p, failed_test_data, test_input_data)
end

function print_testcases_data!(p::TestResultsPrinter, failed_test_data)
    print_header!(p, TestFailed())
    print_header!(p, TestValues())
    for t in failed_test_data
        println(p.io, "------")
        print_show_diff!(p, t)
        for (k,v) in pairs(t)
            if k ∉ p.values_already_shown
                show_value(k, v; io=p.io)
            end
        end
    end
    push!(p.printed_headers, :finished)
    return nothing
end