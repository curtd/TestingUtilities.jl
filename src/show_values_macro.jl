const _DEFAULT_TEST_EXPR_KEY = gensym(:_initial)

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

function show_value(value; io=stderr, compact::Bool=true)
    ctx = IOContext(io, :compact => compact)
    println(ctx, repr(value))
    flush(ctx)
end

function show_value(name, value; io=stderr, compact::Bool=true)
    ctx = IOContext(io, :compact => compact)
    if name isa Expr
        print(ctx, "`")
        Base.show_unquoted(ctx, name)
        print(ctx, "`")
    else
        Base.show_unquoted(ctx, name)
    end
    print(ctx, " = ")
    println(ctx, repr(value))
    flush(ctx)
end

function generate_test_expr(original_ex, record_data_dict; escape::Bool=true)
    call_func, args, kwargs = parse_args_kwargs(original_ex)
    esc_f = escape ? esc : identity
    test_expr = Expr(:block)
    args_to_use = []
    arg_count = 1
    for arg in args 
        @switch arg begin 
            @case Expr(:generator, body, comprehension)
                push!(args_to_use, Expr(:generator, esc_f(body), esc_f(comprehension)))
            @case ::Expr
                if is_atom_recursive(arg)
                    push!(args_to_use, arg)
                else
                    arg_name = Symbol("arg_$(arg_count)")
                    arg_count += 1
                    push!(test_expr.args, :(local $arg_name = $(esc_f(arg))), :($record_data_dict[$(QuoteNode(arg))] = $arg_name))
                    push!(args_to_use, arg_name)
                end
            @case _ 
                if !is_atom_recursive(arg) && !is_ignored_symbol(arg)
                    push!(test_expr.args, :($record_data_dict[$(QuoteNode(arg))] = $(esc_f(arg))))
                end
                push!(args_to_use, esc_f(arg))
        end
    end
    
    kwargs_to_use = []
    for (k, v) in kwargs
        if !is_atom_recursive(v)
            arg_name = Symbol("arg_$(arg_count)")
            arg_count += 1
            push!(test_expr.args, :(local $arg_name = $(esc_f(v))), :($record_data_dict[:($k = $(QuoteNode(v)))] = $arg_name))
            push!(kwargs_to_use, Expr(:kw, k, arg_name))
        else
            push!(kwargs_to_use, Expr(:kw, k, v))
        end
    end
    eval_test_expr = Expr(:call, esc_f(call_func))
    if !isempty(kwargs_to_use)
        push!(eval_test_expr.args, Expr(:parameters, kwargs_to_use...))
    end
    if !isempty(args_to_use)
        push!(eval_test_expr.args, args_to_use...)
    end
    push!(test_expr.args, :(local _result = $(eval_test_expr)), :($record_data_dict[$(QuoteNode(_DEFAULT_TEST_EXPR_KEY))] = _result))
    return test_expr
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
    initial_values_expr = :(Testing.OrderedDict{Symbol,Any}( $( set_failed_test_data_args... )))

    show_values_expr = Expr(:block)
    push!(show_values_expr.args, quote 
        println(io, "Test `" * $(string(original_ex)) *"` failed with values:")

        for (k,v) in pairs(failed_test_data)
            if !(k === $(QuoteNode(_DEFAULT_TEST_EXPR_KEY)))
                Testing.show_value(k, v; io)
            end
        end
        for (k,v) in pairs(test_input_data)
            if !haskey(failed_test_data, k)
                Testing.show_value(k,v; io)
            end
        end
    end)

    source = QuoteNode(__source__)
    return Base.remove_linenums!(quote 
        local Testing = $(@__MODULE__)

        local io = $(esc(io_expr))
        local has_shown_failed_data = Ref{Bool}(false)
        local test_input_data = $(initial_values_expr)
        local failed_test_data = Testing.OrderedDict{Any,Any}()
        local show_all_test_data = let has_shown_failed_data=has_shown_failed_data, failed_test_data=failed_test_data, test_input_data=test_input_data, io=io, Testing=Testing 
            function()
                if !has_shown_failed_data[]
                    $show_values_expr
                    Testing.set_failed_values_in_main(test_input_data, $(should_set_failed_values))
                    has_shown_failed_data[] = true
                end
            end
        end
        local test_result = try 
            $(test_expr)
            Testing.Test.Returned(_result, _result, $(source))
        catch _e 
            show_all_test_data()
            _e isa InterruptException && rethrow()
            Testing.Test.Threw(_e, Base.current_exceptions(), $(source))
        end
        if Testing.test_did_not_succeed(test_result)
            show_all_test_data()
        end
        Testing.Test.do_test(test_result, $(QuoteNode(original_ex)))
    end)

end