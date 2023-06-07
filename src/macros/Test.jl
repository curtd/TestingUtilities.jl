const _DEFAULT_TEST_EXPR_KEY = gensym(:_initial)
const _SHOW_DIFF = gensym(:_show_diff)

function set_failed_values_in_main(failed_values::AbstractDict{Symbol,Any}, should_set_failed_values; force::Bool=false, _module::Module=Main)
    if should_define_vars_in_failed_tests(should_set_failed_values; force) && !isempty(failed_values)
        if isempty(imported_names_in_main[])
            update_imported_names_in_main()
        end
        _imported_names_in_main = imported_names_in_main[]
        set_failed_values_sub_expr = Expr(:block)
        for (key, value) in pairs(failed_values)
            if key ∉ _imported_names_in_main
                push!(set_failed_values_sub_expr.args, Expr(:(=), key, value))
            elseif testing_setting(EmitWarnings)
                @warn "Variable $key (= $value) not set in $_module -- name already exists and is imported in module"
            end
        end
        Core.eval(_module, set_failed_values_sub_expr)
    end
    return nothing
end


function generate_test_expr(original_ex, record_data_dict; escape::Bool=true)
    call_func, args, kwargs = parse_args_kwargs(original_ex)
    esc_f = escape ? esc : identity
    test_expr = Expr(:block)
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
            push!(test_expr.args, :(local $arg_name = $(esc_f(v))), :($record_data_dict[:($k = $(QuoteNode(v)))] = $arg_name))
            push!(kwargs_to_use, Expr(:kw, k, arg_name))
            mapped_args[arg_name] = v
        else
            push!(kwargs_to_use, Expr(:kw, k, esc_f(v)))
        end
    end
    show_diff_exprs = []
    if call_func in (:isequal, :(==), :(Base.(==))) && length(args_to_use) == 2
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
    end
   
    if call_func in (:&&, :||, :comparison, :if)
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
    push!(test_expr.args, :(local _result = $(eval_test_expr)), :($record_data_dict[$(QuoteNode(_DEFAULT_TEST_EXPR_KEY))] = _result))
    append!(test_expr.args, show_diff_exprs)
    return test_expr
end

function generate_show_diff_expr(already_shown_name, failed_testdata_name)
    return quote 
        if haskey($(failed_testdata_name), $(QuoteNode(_SHOW_DIFF)))
            data = $(failed_testdata_name)[$(QuoteNode(_SHOW_DIFF))]
            key1, key2 = data.keys
            value1, value2 = data.values
            if value1 isa AbstractString && value2 isa AbstractString 
                if TestingUtilities.show_diff(value1, value2; expected_name=key1, result_name=key2, io)
                    push!($(already_shown_name), key1, key2)
                end
            end
            push!($(already_shown_name), $(QuoteNode(_SHOW_DIFF)))
            true
        else 
            false
        end
    end
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
    kwargs = parse_kwarg_expr(args[1:end-1]...)
    io_expr = fetch_kwarg_expr(kwargs; key=:io, expected_type=[Symbol, Expr], default_value=:(stderr))
    should_set_failed_values = fetch_kwarg_expr(kwargs; key=:set_failed_values, expected_type=[Bool, Nothing], default_value=nothing)
    
    original_ex = args[end]
    
    comp_graph = computational_graph(original_ex)
    all_input_values = [v for v in values(comp_graph) if v isa Symbol]
   
    if original_ex isa Symbol 
        test_expr = Expr(:block, :(local _result = $(esc(original_ex))), :(failed_test_data[$(QuoteNode(_DEFAULT_TEST_EXPR_KEY))] = _result))
    else
        test_expr = generate_test_expr(original_ex, :failed_test_data)
    end

    set_failed_test_data_args = []
    if !(original_ex isa Symbol)
        for k in all_input_values
            push!(set_failed_test_data_args, :($(QuoteNode(k)) => $(esc(k))))
        end
    end
    initial_values_expr = :(TestingUtilities.OrderedDict{Symbol,Any}( $( set_failed_test_data_args... )))

    show_values_expr = Expr(:block)
    if Meta.isexpr(original_ex, :if, 3)
        original_ex_str = "$(original_ex.args[1]) ? $(original_ex.args[2]) : $(original_ex.args[3])"
    else
        original_ex_str = string(original_ex)
    end

    push!(show_values_expr.args, quote 
        println(io, "Test `" * $(original_ex_str) *"` failed with values:")
        already_shown = Set(Any[$(QuoteNode(_DEFAULT_TEST_EXPR_KEY))])
        $(generate_show_diff_expr(:already_shown, :failed_test_data))
        for (k,v) in pairs(failed_test_data)
            if k ∉ already_shown && !(k === $(QuoteNode(_DEFAULT_TEST_EXPR_KEY)))
                TestingUtilities.show_value(k, v; io)
                push!(already_shown, k)
            end
        end
        for (k,v) in pairs(test_input_data)
            if k ∉ already_shown
                TestingUtilities.show_value(k,v; io)
                push!(already_shown, k)
            end
        end
    end)

    source = QuoteNode(__source__)
    return Base.remove_linenums!(quote 
        local TestingUtilities = $(@__MODULE__)

        local io = $(esc(io_expr))
        local has_shown_failed_data = Ref{Bool}(false)
        local test_input_data = $(initial_values_expr)
        local failed_test_data = TestingUtilities.OrderedDict{Any,Any}()
        local show_all_test_data = let has_shown_failed_data=has_shown_failed_data, failed_test_data=failed_test_data, test_input_data=test_input_data, io=io, TestingUtilities=TestingUtilities 
            function()
                if !has_shown_failed_data[]
                    $show_values_expr
                    TestingUtilities.set_failed_values_in_main(test_input_data, $(should_set_failed_values))
                    has_shown_failed_data[] = true
                end
            end
        end
        local test_result = try 
            $(test_expr)
            TestingUtilities.Test.Returned(_result, _result, $(source))
        catch _e 
            show_all_test_data()
            _e isa InterruptException && rethrow()
            TestingUtilities.Test.Threw(_e, Base.current_exceptions(), $(source))
        end
        if TestingUtilities.test_did_not_succeed(test_result)
            show_all_test_data()
        end
        TestingUtilities.Test.do_test(test_result, $(QuoteNode(original_ex)))
    end)

end