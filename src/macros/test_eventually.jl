function time_unit_expr(num::Int, unit::Symbol)
    if unit === :ms 
        return :($Dates.Millisecond($num))
    elseif unit === :s
        return :($Dates.Second($num))
    elseif unit === :m
        return :($Dates.Minute($num))
    elseif unit === :h
        return :($Dates.Hour($num))
    elseif unit === :d
        return :($Dates.Day($num))
    elseif unit === :w
        return :($Dates.Week($num))
    elseif unit === :month 
        return :($Dates.Month($num))
    elseif unit === :y
        return :($Dates.Year($num))
    else
        return nothing 
    end
end

function parse_shorthand_duration(ex::Expr)
    @switch ex begin 
        @case Expr(:call, :*, num, unit) && if num isa Int end && if unit isa Symbol end
            return time_unit_expr(num, unit)
        @case _
            return nothing
    end
end
parse_shorthand_duration(ex::Int) = :($Dates.Millisecond($ex))
parse_shorthand_duration(ex) = nothing

"""
    @test_eventually [io=stderr] [timeout=duration] [sleep=duration] [repeat=false] test_expr

Evalutes `test_expr` in the context of the `Test` module (i.e., runs the equivalent to `@test \$test_expr`), and ensures that it passes within a given time frame.

If `test_expr` does not return a value within the specified `timeout`, the test fails with a `TestTimedOutException`. This macro checks `sleep` amount of time for the test expression to return a value, until `timeout` is reached. 

If `repeat == true` and the first invocation of `test_expr` returns `false`, repeats the call to `test_expr` until it returns `true` or it times out.

## Duration Types 
If `key = value` is given for `key` = `sleep` or `key` = `timeout`, then
- if `value::Int` - the corrresponding duration is converted to a `Millisecond(value)`
- if `value` is an expression of the form `num*unit` for `num::Int` and `unit` is one of the shorthand durations (`ms`, `s`, `m`, `h`, `d`, `w`, `month`, `y`), the resulting duration will be converted to its equivalent unit from the `Dates` module
    e.g., `value = 1m` => `Dates.Minute(1)`
          `value = 2s` => `Dates.Second(2)`
- otherwise, `value` must be a valid `Dates.Period` expression
"""
macro test_eventually(args...)
    kwargs = parse_kwarg_expr(args[1:end-1]...)
    io_expr = fetch_kwarg_expr(kwargs; key=:io, expected_type=[Symbol, Expr], default_value=:(stderr))
    timeout_expr = fetch_kwarg_expr(kwargs; key=:timeout, expected_type=[Symbol, Expr, Int])
    sleep_period_expr = fetch_kwarg_expr(kwargs; key=:sleep, expected_type=[Symbol, Expr, Int])
    repeat = fetch_kwarg_expr(kwargs; key=:repeat, expected_type=[Bool], default_value=false)

    original_ex = args[end]

    if (timeout_short_expr = parse_shorthand_duration(timeout_expr); !isnothing(timeout_short_expr))
        timeout_expr = timeout_short_expr
    else 
        timeout_expr = esc(timeout_expr)
    end

    if (sleep_period_short_expr = parse_shorthand_duration(sleep_period_expr); !isnothing(sleep_period_short_expr))
        sleep_period_expr = sleep_period_short_expr
    else 
        sleep_period_expr = esc(sleep_period_expr)
    end

    initial_values_expr, test_expr, use_isequals_equality = test_expr_and_init_values(original_ex, :failed_test_data, :_result)
    
    source = QuoteNode(__source__)

    original_ex_str = show_value_str(original_ex)

    return Base.remove_linenums!(quote 
        local io = $(esc(io_expr))
        local results_printer = $TestResultsPrinter(io, $(QuoteNode(original_ex)); use_isequals_equality=$use_isequals_equality)
        local test_input_data = $(initial_values_expr)
        local failed_test_data = $OrderedDict{Any,Any}()

        local test_cb = function()
            try 
                $(test_expr)
                $Test.Returned(_result, _result, $(source))
            catch _e 
                $Test.Threw(_e, $(current_exceptions_expr()), $(source))
            end
        end
        local max_time = $timeout_expr
        local sleep_time = $sleep_period_expr
        local timer = $TaskFinishedTimer(test_cb; max_time=max_time, sleep_time=sleep_time, timer_name=$(original_ex_str))

        local test_result

        while true 
            test_result = $fetch(timer; throw_error=false)
            if isnothing(test_result)
                # Timed out 
                $print_testeventually_data!(results_printer, max_time, failed_test_data, test_input_data)
                test_result = $Test.Threw($TestTimedOutException(max_time, $(original_ex_str)), [], $(source))
            else
                result = $test_ran_result(test_result)
                if result == false
                    $(repeat ? :(continue) : nothing)
                    $print_Test_data!(results_printer, failed_test_data, test_input_data)
                end
            end
            break
        end

        $Test.do_test(test_result, $(QuoteNode(original_ex)))
    end)
end