const _DEFAULT_TEST_EXPR_KEY = gensym(:_initial)
const _SHOW_DIFF = gensym(:_show_diff)

function set_failed_values_in_main(failed_values::AbstractDict{<:Any,<:Any}, should_set_failed_values; force::Bool=false, _module::Module=Main)
    if should_define_vars_in_failed_tests(should_set_failed_values; force) && !isempty(failed_values)
        if isempty(imported_names_in_main[])
            update_imported_names_in_main()
        end
        _imported_names_in_main = imported_names_in_main[]
        set_failed_values_sub_expr = Expr(:block)
        for (key, value) in pairs(failed_values)
            !(key isa Symbol) && continue
            if key ∉ _imported_names_in_main
                push!(set_failed_values_sub_expr.args, Expr(:(=), key, value isa Symbol || value isa Expr ? QuoteNode(value) : value))
            elseif testing_setting(EmitWarnings)
                @warn "Variable $key (= $value) not set in $_module -- name already exists and is imported in module"
            end
        end
        Core.eval(_module, set_failed_values_sub_expr)
    end
    return nothing
end

is_input_value(x) = x isa Symbol || Meta.isexpr(x, :., 2) || Meta.isexpr(x, :macrocall)

function generate_test_expr(original_ex, record_data_dict; escape::Bool=true)
    call_func, args, kwargs = parse_args_kwargs(original_ex)
    esc_f = escape ? esc : identity
    test_expr = Expr(:block)
    show_diff_exprs = []
    use_isequals_equality = true
    if should_recurse_children(original_ex)
        args_to_use = []
        arg_count = 1
        mapped_args = Dict()
        for arg in args 
            @switch arg begin 
                @case Expr(:generator, body, comprehension)
                    push!(args_to_use, Expr(:generator, esc_f(body), esc_f(comprehension)))
                @case ::Expr
                    if is_atom(arg)
                        push!(args_to_use, arg)
                    else
                        arg_name = Symbol("arg_$(arg_count)")
                        arg_count += 1
                        push!(test_expr.args, :(local $arg_name = $(esc_f(arg))), :($record_data_dict[$(QuoteNode(arg))] = $arg_name))
                        push!(args_to_use, arg_name)
                        mapped_args[arg_name] = arg
                    end
                @case _ 
                    arg_is_atom = is_atom(arg)
                    if !arg_is_atom && !is_ignored_symbol(arg)
                        push!(test_expr.args, :($record_data_dict[$(QuoteNode(arg))] = $(esc_f(arg))))
                    end
                    if arg_is_atom
                        push!(args_to_use, arg)
                    else
                        push!(args_to_use, esc_f(arg))
                    end
            end
        end
        
        kwargs_to_use = []
        for (k, v) in kwargs
            if !is_atom(v)
                arg_name = Symbol("arg_$(arg_count)")
                arg_count += 1
                push!(test_expr.args, :(local $arg_name = $(esc_f(v))), :($record_data_dict[($(QuoteNode(k)),$(QuoteNode(v)))] = $arg_name))
                push!(kwargs_to_use, Expr(:kw, k, arg_name))
                mapped_args[arg_name] = v
            else
                push!(kwargs_to_use, Expr(:kw, k, esc_f(v)))
            end
        end
       
        if call_func in (:isequal, :(==), :(Base.(==)), :(Base.isequals)) && length(args_to_use) == 2
            first_arg, second_arg = args_to_use
            first_arg_unesc = unescape(first_arg)
            second_arg_unesc = unescape(second_arg)
            show_diff_expr = Expr(:(=), Expr(:ref, record_data_dict, QuoteNode(_SHOW_DIFF)))
            keys = []
            if (!is_atom(first_arg_unesc) && !is_atom(second_arg_unesc)) 
                push!(keys, QuoteNode(get(mapped_args, first_arg_unesc, first_arg_unesc)) )
                push!(keys, QuoteNode(get(mapped_args, second_arg_unesc, second_arg_unesc)) )
                push!(show_diff_expr.args, :((keys=Any[$(keys...)], values=Any[$first_arg, $second_arg])))
            elseif first_arg_unesc isa String 
                if second_arg_unesc isa String 
                    push!(show_diff_expr.args, :((keys=[:expected, :result], values=Any[$first_arg, $second_arg])))
                else
                    push!(keys, QuoteNode(:expected), QuoteNode(get(mapped_args, second_arg_unesc, second_arg_unesc)))
                    push!(show_diff_expr.args, :((keys=Any[$(keys...)], values=Any[$first_arg, $second_arg])))
                end
            elseif second_arg_unesc isa String 
                push!(keys, QuoteNode(:expected), QuoteNode(get(mapped_args, first_arg_unesc, first_arg_unesc)))
                push!(show_diff_expr.args, :((keys=Any[$(keys...)], values=Any[$second_arg, $first_arg])) )
            end
            if length(show_diff_expr.args) == 2
                push!(show_diff_exprs, show_diff_expr)
            end
            use_isequals_equality = call_func in (:isequal, :(Base.isequals))
        end
    
        if call_func in (:&&, :||, :comparison, :if, :ref, :.)
            eval_test_expr = Expr(call_func)
        else
            eval_test_expr = Expr(:call, esc_f(call_func))
        end
        if !isempty(kwargs_to_use)
            push!(eval_test_expr.args, Expr(:parameters, kwargs_to_use...))
        end
        if !isempty(args_to_use)
            push!(eval_test_expr.args, args_to_use...)
        end
    else
        eval_test_expr = esc_f(original_ex)
    end
    push!(test_expr.args, :(local _result = $(eval_test_expr)), :($record_data_dict[$(QuoteNode(_DEFAULT_TEST_EXPR_KEY))] = _result))
    append!(test_expr.args, show_diff_exprs)
    return test_expr, use_isequals_equality
end

function generate_show_diff_expr(already_shown_name, failed_testdata_name)
    return quote 
        if haskey($(failed_testdata_name), $(QuoteNode(_SHOW_DIFF)))
            data = $(failed_testdata_name)[$(QuoteNode(_SHOW_DIFF))]
            key1, key2 = data.keys
            value1, value2 = data.values

            $show_diff(value1, value2; expected_name=key1, result_name=key2, io, print_values_header)
            push!($(already_shown_name), key1, key2)
            
          
            push!($(already_shown_name), $(QuoteNode(_SHOW_DIFF)))
            true
        else 
            false
        end
    end
end

function test_expr_and_init_values(original_ex, failed_test_data_name::Symbol, result_name::Symbol)
    comp_graph = computational_graph(original_ex)
    all_input_values = [v for v in values(comp_graph) if is_input_value(v)]
    if original_ex isa Symbol 
        test_expr = Expr(:block, :(local $result_name = $(esc(original_ex))), :($failed_test_data_name[$(QuoteNode(_DEFAULT_TEST_EXPR_KEY))] = $result_name))
        use_isequals_equality = true
    else
        test_expr, use_isequals_equality = generate_test_expr(original_ex, failed_test_data_name)
    end
    set_failed_test_data_args = []
    if !(original_ex isa Symbol)
        for k in all_input_values
            push!(set_failed_test_data_args, :($(QuoteNode(k)) => $(esc(k))))
        end
    end
    initial_values_expr = :($OrderedDict{Any,Any}( $( set_failed_test_data_args... )))
    return initial_values_expr, test_expr, use_isequals_equality
end

function test_show_values_expr(results_printer_name::Symbol, failed_test_data_sym::Symbol, test_input_data_sym::Symbol; should_set_failed_values)

    show_values_func_expr = Base.remove_linenums!(quote 
        let results_printer=$results_printer_name, failed_test_data=$failed_test_data_sym, test_input_data=$test_input_data_sym
            function()
                if !$has_printed(results_printer)
                    $print_Test_data!(results_printer, failed_test_data, test_input_data)
                
                    $set_failed_values_in_main($test_input_data_sym, $(should_set_failed_values))
                end
            end
        end
    end)
    return show_values_func_expr
end

function Test_expr(original_ex; io_expr, should_set_failed_values, _sourceinfo)
    source = QuoteNode(_sourceinfo)
    initial_values_expr, test_expr, use_isequals_equality = test_expr_and_init_values(original_ex, :failed_test_data, :_result)

    show_test_data_expr = Base.remove_linenums!(quote 
        let results_printer=results_printer, failed_test_data=failed_test_data, test_input_data=test_input_data
            function()
                if !$has_printed(results_printer)
                    $print_Test_data!(results_printer, failed_test_data, test_input_data)
                
                    $set_failed_values_in_main(test_input_data, $(should_set_failed_values))
                end
            end
        end
    end)

    output = Base.remove_linenums!(quote 
        local io = $(esc(io_expr))
        local results_printer = $TestResultsPrinter(io, $(QuoteNode(original_ex)); use_isequals_equality=$use_isequals_equality)
        local test_input_data = $(initial_values_expr)
        local failed_test_data = $OrderedDict{Any,Any}()

        local show_all_test_data = $(show_test_data_expr)

        local test_result = try 
            $(test_expr)
            $Test.Returned(_result, _result, $(source))
        catch _e 
            show_all_test_data()
            _e isa InterruptException && rethrow()
            $Test.Threw(_e, $(current_exceptions_expr()), $(source))
        end
        if $test_did_not_succeed(test_result)
            show_all_test_data()
        end
        $Test.do_test(test_result, $(QuoteNode(original_ex)))
    end)
    return output
end


"""
    @Test [io=stderr] [set_failed_values=nothing] test_expr 

Evaluates `test_expr` in the context of the `Test` module (i.e., runs the equivalent to `@test \$test_expr`).

If `test_expr` does not pass, either due to an exception or the test itself runs but does not return the expected value, an error message is printed to `io` with the values of the top-level expressions and any bare symbols extracted from `test_expr`

When executed from an interactive Julia session and 
- `_GLOBAL_DEFINE_VARS_IN_FAILED_TESTS[] == true` and `set_failed_values != false`
or
- `set_failed_values == true` 

the names + values of the bare symbols in `test_expr` are set in the `Main` module to simplify debugging the failing test case. 

"""
macro Test(args...)
    isempty(args) && error("`@Test` must have at least one argument")
    kwargs = parse_kwarg_expr(args[1:end-1]...)
    io_expr = fetch_kwarg_expr(kwargs; key=:io, expected_type=[Symbol, Expr], default_value=:(stderr))
    should_set_failed_values = fetch_kwarg_expr(kwargs; key=:set_failed_values, expected_type=[Bool, Nothing], default_value=nothing)
    
    original_ex = args[end]
    
    return Test_expr(original_ex; io_expr, should_set_failed_values, _sourceinfo=__source__)
end