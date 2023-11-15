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
                if arg1 isa Symbol && (Meta.isexpr(arg2, :(=), 2) && arg2.args[1] isa Symbol )
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
                    _ => push!(output, arg)
                end
            end
            return output
        @case _
            error("Could not parse tuple $expression")
    end
end

function test_ran_result(test_result)
    if test_result isa Test.Returned && test_result.value isa Bool
        return test_result.value
    else
        return nothing 
    end
end
test_did_not_succeed(test_result) = !(test_ran_result(test_result) == true)

function rm_macrocall_linenode!(expr::Expr)
    if Meta.isexpr(expr, :macrocall)
        expr.args[2] = nothing 
    end
end

struct TestDataGeneratorExpr
    per_var_data::Vector{Any}
    generator_exprs::Vector{Any}
end
Base.length(g::TestDataGeneratorExpr) = length(g.per_var_data)
function TestDataGeneratorExpr(expr)
    data_expr = expr.args[1]
    if Meta.isexpr(data_expr, :tuple)
        per_var_data = parse_tuple(data_expr)
    else
        per_var_data = parse_table(data_expr; is_header=false)
    end
    generator_exprs = expr.args[2:end]
    return TestDataGeneratorExpr(per_var_data, generator_exprs)
end

struct TestExpr 
    original_expr::Any
end

Base.@kwdef mutable struct EvaluateTestCasesExpr 
    input_exprs::Vector{Any} = Any[]
    num_test_exprs::Int = 0
end
Base.length(e::EvaluateTestCasesExpr) = length(e.input_exprs)

function add_test_expr!(t::EvaluateTestCasesExpr, expr; in_block_expr::Bool)
    if Meta.isexpr(expr, :macrocall)
        is_test_macro = expr.args[1] in (Symbol("@test"), Symbol("@Test")) 
        
        is_test_macro || in_block_expr || error("Only `@test` or `@Test` macros allowed in $(expr)")
        if is_test_macro
            push!(t.input_exprs, TestExpr(expr.args[end]))
            t.num_test_exprs += 1
        else
            push!(t.input_exprs, expr)
        end
        return true
    elseif in_block_expr
        push!(t.input_exprs, expr)
        return true
    else
        return false 
    end
end

function parse_test_cases(body_args; headers)
    test_expr_started = false
    evaluate_test_exprs = EvaluateTestCasesExpr()
    all_test_case_values = Any[]
    for (i, expr) in enumerate(body_args)
        expr isa LineNumberNode && continue 
        if Meta.isexpr(expr, :macrocall)
            add_test_expr!(evaluate_test_exprs, expr; in_block_expr=false)
            test_expr_started = true
        elseif Meta.isexpr(expr, :block)
            test_expr_started && error("Expression `$expr` must have either `@test` expressions or a single `:block` expression -- cannot mix the two")
            i == length(body_args) || error("`:block` expression must be the last argument")
            for arg in expr.args 
                arg isa LineNumberNode && continue 
                add_test_expr!(evaluate_test_exprs, arg; in_block_expr=true)
            end
        else
            test_expr_started && error("Cannot have test expressions interspersed with test data in expression $(body)")
            
            if Meta.isexpr(expr, :tuple)
                test_data_expr = parse_tuple(expr)
            elseif Meta.isexpr(expr, :generator)
                test_data_expr = TestDataGeneratorExpr(expr)
            else
                test_data_expr = parse_table(expr; is_header=false)
            end
            length(test_data_expr) == length(headers) || error("Number of test data columns (= $(length(test_data_expr))) in expression (= $(test_data_expr)) must be equal to $(length(headers))")
            push!(all_test_case_values, test_data_expr)
        end
    end

    return evaluate_test_exprs, all_test_case_values
end

function test_case_exprs(e::EvaluateTestCasesExpr; source, all_header_names)
    data_var = gensym("test_case_data")

    run_tests_body = Expr(:block, [Expr(:(=), name, :($data_var.$(name))) for name in all_header_names]...)
  
    show_all_test_data_expr = Expr(:block)

    num_test_exprs = 1
    
    for evaluate_test_expr in e.input_exprs
        if evaluate_test_expr isa TestExpr 
            ex = evaluate_test_expr.original_expr
            new_test_expr, use_isequals_equality = generate_test_expr(ex, :(local_evaluate_test_data[$num_test_exprs]); escape=false)

            push!(run_tests_body.args, Base.remove_linenums!( 
                quote 
                    empty!(local_evaluate_test_data[$num_test_exprs])
                    local test_result = try 
                        $(new_test_expr) 
                        $TestingUtilities.Test.Returned(_result, _result, $(source))
                    catch _e
                        _e isa InterruptException && rethrow()
                        $TestingUtilities.Test.Threw(_e, $Base.current_exceptions(), $(source))
                    end
                    if $TestingUtilities.test_did_not_succeed(test_result)
                        testdata_values = local_evaluate_test_data[$num_test_exprs]
                        current_values = $(Expr(:tuple, Expr(:parameters, all_header_names...)))

                        current_values_dict = copy(testdata_values)
                        for (k,v) in pairs(current_values)
                            if !haskey(current_values_dict,k)
                                current_values_dict[k] = v
                            end
                        end
                        push!(failed_test_data[$num_test_exprs], current_values_dict)
                    end
                    $TestingUtilities.Test.do_test(test_result, $(QuoteNode(ex)))
                end)
            )

            push!(show_all_test_data_expr.args, quote 
                if !isempty(failed_test_data[$num_test_exprs])
                    results_printer = $TestingUtilities.TestResultsPrinter(io, $(QuoteNode(ex)); use_isequals_equality=$use_isequals_equality)
                    $TestingUtilities.print_testcases_data!(results_printer, failed_test_data[$num_test_exprs])
                end
            end)
            num_test_exprs += 1
        else 
            push!(run_tests_body.args, evaluate_test_expr)
        end
    end

    run_tests_expr = Expr(:for, Expr(:(=), data_var, :test_data), run_tests_body)

    return run_tests_expr, show_all_test_data_expr
end


"""
    @test_cases [io=stderr] begin 
        [test cases] 

        [test expressions]
    end

Create a set of test data and, for each test data point, evaluates one or more test expressions on them. The values in each test case that cause the test to fail or for an exception to be thrown will be written to `io`. 

## Test Case Expressions
`[test cases]` must be a series of expressions of the form

```julia
    variable₁ | variable₂ | ... | variableₙ 
    value₁₁   | value₁₂   | ... | value₁ₙ
    value₂₁   | value₂₂   | ... | value₂ₙ
    ...
    valueₘ₁   | valueₘ₂   | ... | valueₘₙ
```

Equivalent forms of `value₁ | value₂ | ... | valueₙ` are

`(variable₁ = value₁, variable₂ = value₂, ..., variableₙ = valueₙ)`

or 

`variable₁ => value₁, variable₂ => value₂, ..., variableₙ  => valueₙ`

Note: The `variableᵢ` can involve expressions that refer to `variableⱼ` for any `j < i`. E.g., the following is a valid `[test_case]` expression: 
```julia
    x  | y   | z
    1  | x^2 | y-x
```

`[test cases]` may also be a generator expression of the form 
```julia
(value₁ | value₂ | ... | valueₙ for [valueᵢ₁ in Vᵢ₁, ..., valueᵢⱼ in Vᵢⱼ])
```

## Test Expressions
`[test expressions]` must be a series of one or more test evaluation expressions 

e.g., 
```julia
    @test cond₁
    @test cond₂ 
    ...
    @test condₖ
```

or a single `begin ... end` expression containing one or more test evaluation expressions, as well as other expressions that will be evaluated for each input data value

e.g., 
```julia
begin 
    expr₁ 
    @test cond₁ 
    expr₂
    @test cond₂
    ...
end
```

Note, each test condition expression `condᵢ` must evaluate to a `Bool` and contains zero or more values from `variable₁, variable₂, ..., variableₙ `.
"""
macro test_cases(args...)
    isempty(args) && error("`@test_cases` must have at least one argument")
    kwargs = parse_kwarg_expr(args[1:end-1]...)
    io_expr = fetch_kwarg_expr(kwargs; key=:io, expected_type=[Symbol, Expr], default_value=:(stderr))

    body = args[end]
    Meta.isexpr(body, :block) && length(body.args) ≥ 3 || error("Input expression $(body) must be a block expression with at least 3 subexpressions")
    idx = findfirst(t->!(t isa LineNumberNode), body.args)
    isnothing(idx) && error("Input expression $(body) must not be empty")
    headers = parse_table(body.args[idx]; is_header=true)
    !isempty(headers) || error("Provided headers cannot be empty")

    evaluate_test_exprs, all_test_case_values = parse_test_cases(body.args[idx+1:end]; headers)
    num_test_exprs = evaluate_test_exprs.num_test_exprs
    num_test_exprs == 0 && error("No test expressions found input expression $(body)")

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

    test_data_tuple_expr = Expr(:tuple)
    for test_case_values in all_test_case_values
        vals = test_case_values isa TestDataGeneratorExpr ? test_case_values.per_var_data : test_case_values

        output_expr = Expr(:block)
        for (header, test_case) in zip(normalized_headers, vals) 
            name = header.name 
            replace_expr = header.replace_expr
            if !isnothing(replace_expr)
                replace_key = first(replace_expr)
                replace_value = last(replace_expr)
            else
                replace_key = nothing
                replace_value = nothing
            end
            if isnothing(replace_key) || !(test_case == replace_key)
                push!(output_expr.args, :(local $name = $(test_case)))
            else
                push!(output_expr.args, :(local $name = $(replace_value)))
            end
        end
        push!(output_expr.args, Expr(:tuple, Expr(:parameters, all_header_names...)))

        if test_case_values isa TestDataGeneratorExpr
            push!(test_data_tuple_expr.args, Expr(:generator, output_expr, test_case_values.generator_exprs...))
        else
            push!(test_data_tuple_expr.args, Expr(:tuple, output_expr))
        end
    end
    test_data_values_expr = :($Base.Iterators.flatten($test_data_tuple_expr))
    run_tests_expr, show_all_test_data_expr = test_case_exprs(evaluate_test_exprs; source=QuoteNode(__source__), all_header_names)
    
    out_expr = quote 
        local failed_test_data = [Any[] for i in 1:$(num_test_exprs)]
        local local_evaluate_test_data = [$TestingUtilities.OrderedDict{Any,Any}() for i in 1:$(num_test_exprs)]
        local has_set_failed_data = Ref{Bool}(false)

        local show_all_test_data = let failed_test_data=failed_test_data, has_set_failed_data=has_set_failed_data, io=$(io_expr)
            function()
                $show_all_test_data_expr
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