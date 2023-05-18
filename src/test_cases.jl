function parse_table(expression; is_header::Bool=false)
    @switch expression begin 
        @case arg::Symbol 
            [arg] 
        @case Expr(:call, :|, args...)
            output = []
            for arg in args 
                append!(output, parse_table(arg; is_header) )
            end
            output
        @case Expr(:tuple, arg1, arg2)
            if is_header
                if arg1 isa Symbol && (Base.isexpr(arg2, :(=), 2) && arg2.args[1] isa Symbol )
                    [(arg1, arg2.args[1] => arg2.args[2])]
                else 
                    error("expression $expression must be a tuple of the form `(name, placeholder = value)`")
                end
            else
                vcat(parse_table(arg1; is_header), parse_table(arg2; is_header))
            end
        @case :($arg1 | $arg2) 
            if arg1 isa Expr
                vcat(parse_table(arg1; is_header), [arg2])
            else
                vcat([arg1], parse_table(arg2; is_header))
            end    
        @case arg 
            if is_header
                error("expression $expression must be of the form `a1 | a2 | ... | an` where each `ai` isa `Symbol` or an expression of the form `(name, (placeholder = value))")
            else
                [arg]
            end
    end
end
function parse_tuple(expression)
    @switch expression begin 
        @case Expr(:tuple, args...)
            output = []
            for arg in args 
                @match arg begin 
                    :($K => $V) => push!(output, V)
                    :($K = $V) => push!(output, V)
                    _ => error("Could not parse tuple $expression")
                end
            end
            return output
        @case _
            error("Could not parse tuple $expression")
    end
end

function test_did_not_succeed(test_result)
    return !(test_result isa Test.Returned && test_result.value isa Bool && test_result.value == true)
end

function rm_macrocall_linenode!(expr::Expr)
    if Base.isexpr(expr, :macrocall)
        expr.args[2] = nothing 
    end
end

"""
    @test_cases [io=stderr] begin 
        [test cases] 

        [test expressions]
    end

Create a set of test data and, for each test data point, evaluates one or more test expressions on them. The values in each test case that cause a failing test will be written to `io`. 

`[test cases]` must be a series of expressions of the form

```julia
    variable1 | variable2 | ... | variablen 
    value11   | value12   | ... | value 1n
    value21   | value22   | ... | value 2n
    ...
    valuem1   | valuem2   | ... | value mn
```

Equivalent forms of `value1 | value2 | ... | valuen` are the expressions

`(variable1=value1, variable2=value2, ..., variablen=valuen)`

or 

`variable1 => value1, variable2 => value2, ..., variablen => valuen`

`[test expressions]` must be a series of one or more test evaluation expressions 

```julia
    @test cond1
    @test cond2 
    ...
```

Here, each test condition expression `condi` evalutes to a `Bool` and contains zero or more values from `variable1, variable2, ..., variablen`.

The variable-value matrix is translated into a `for`-loop and each test condition is evaluated at every iteration of the loop. 

If any of the tests fail or throw an exception, the set of all points that caused a test condition not to pass are printed to `io`, along with the corresponding test condition.
"""
macro test_cases(args...)
    kwargs = parse_kwarg_expr(args[1:end-1]...)
    io_expr = fetch_kwarg_expr(kwargs; key=:io, expected_type=[Symbol, Expr], default_value=:(stderr))

    body = args[end]
    Base.isexpr(body, :block) && length(body.args) ≥ 3 || error("Input expression $(body) must be a block expression with at least 3 subexpressions")
    idx = findfirst(t->!(t isa LineNumberNode), body.args)
    isnothing(idx) && error("Input expression $(body) must not be empty")
    headers = parse_table(body.args[idx]; is_header=true)
    !isempty(headers) || error("Provided headers cannot be empty")
    
    test_expr_started = false
    evaluate_test_exprs = []
    all_test_case_values = Any[]
    for expr in body.args[idx+1:end]
        expr isa LineNumberNode && continue 
        if Base.isexpr(expr, :macrocall)
            expr.args[1] === Symbol("@test") || error("Only @test macros allowed in $(expr)")
            test_expr_started = true 
            push!(evaluate_test_exprs, expr.args[end])
        else
            if test_expr_started
                error("Cannot have test expressions interspersed with test data in expression $(body)")
            end
            if Base.isexpr(expr, :tuple)
                test_data_expr = parse_tuple(expr)
            else
                test_data_expr = parse_table(expr; is_header=false)
            end
            length(test_data_expr) == length(headers) || error("Number of test data columns (= $(length(test_data_expr))) in expression (= $(test_data_expr)) must be equal to $(length(headers))")
            push!(all_test_case_values, test_data_expr)
        end
    end
    isempty(evaluate_test_exprs) && error("No test expressions found input expression $(body)")

    normalized_headers = []
    all_header_names = []
    for header in headers 
        if header isa Symbol 
            push!(normalized_headers, (name=header, replace_expr=nothing))
            push!(all_header_names, header)
        else
            name, replace_value = header 
            push!(normalized_headers, (name=name, replace_expr=replace_value))
            push!(all_header_names, name)
        end
    end

    test_data_values_expr = Expr(:vcat)
    for test_case_values in all_test_case_values
        output = []
        for ((;name, replace_expr), test_case) in zip(normalized_headers, test_case_values) 
            if !isnothing(replace_expr)
                replace_key = first(replace_expr)
                replace_value = last(replace_expr)
            else
                replace_key = nothing
                replace_value = nothing
            end
            if isnothing(replace_key) || !(test_case == replace_key)
                push!(output, Expr(:kw, name, test_case))
            else
                push!(output, Expr(:kw, name, replace_value))
            end
        end
        push!(test_data_values_expr.args, Expr(:tuple, Expr(:parameters, output...)))
    end
    
    current_values_expr = Expr(:tuple, Expr(:parameters, all_header_names...))

    show_all_test_data_expr = Expr(:block)

    source = QuoteNode(__source__)

    run_tests_body = Expr(:block)
    for (i, evaluate_test_expr) in enumerate(evaluate_test_exprs)
        
        new_test_expr = generate_test_expr(evaluate_test_expr, :(local_evaluate_test_data[$i]); escape=false)
        push!(run_tests_body.args, Base.remove_linenums!( 
            quote 
                empty!(local_evaluate_test_data[$i])
                local test_result = try 
                    $(new_test_expr) 
                    TestingUtilities.Test.Returned(_result, _result, $(source))
                catch _e
                    _e isa InterruptException && rethrow()
                    TestingUtilities.Test.Threw(_e, Base.current_exceptions(), $(source))
                end
                if TestingUtilities.test_did_not_succeed(test_result)
                    testdata_values = local_evaluate_test_data[$i]
                    current_values = $current_values_expr
                    current_values_dict = copy(testdata_values)
                    for (k,v) in pairs(current_values)
                        if !haskey(current_values_dict,k)
                            current_values_dict[k] = v
                        end
                    end
                    push!(failed_test_data[$i], current_values_dict)
                end
                TestingUtilities.Test.do_test(test_result, $(QuoteNode(evaluate_test_expr)))
            end)
        )

        push!(show_all_test_data_expr.args, quote 
            if !isempty(failed_test_data[$i])
                println(io, "Test `" * $(string(evaluate_test_expr)) *"` failed with values:")
                for (num,t) in enumerate(failed_test_data[$i])
                    println(io, "------")
                    for (k,v) in pairs(t)
                        if !(k === $(QuoteNode(_DEFAULT_TEST_EXPR_KEY)))
                            TestingUtilities.show_value(k,v; io)
                        end
                    end
                end
            end
        end)
        
    end

    run_tests_expr = Expr(:for, Expr(:(=), Expr(:tuple, Expr(:parameters, all_header_names...)), :test_data), run_tests_body)
    out_expr = quote 
        local TestingUtilities = $(@__MODULE__)
        local failed_test_data = [Any[] for i in 1:$(length(evaluate_test_exprs))]
        local local_evaluate_test_data = [TestingUtilities.OrderedDict{Any,Any}() for i in 1:$(length(evaluate_test_exprs))]
        local has_shown_failed_data = Ref{Bool}(false)
        local has_set_failed_data = Ref{Bool}(false)
        local show_all_test_data = let failed_test_data=failed_test_data, has_set_failed_data=has_set_failed_data, io=$(io_expr)
            function()
                if !has_shown_failed_data[]
                    $show_all_test_data_expr
                end
            end
        end
        local test_data = try 
            $(test_data_values_expr)
        catch e 
            @error "Caught error while evaluating test data expression $($(QuoteNode(test_data_values_expr)))"
            rethrow(e)
        end
        try 
            $run_tests_expr
        finally 
            show_all_test_data()
        end
    end 
    Base.remove_linenums!(out_expr)
    return out_expr |> esc 
end