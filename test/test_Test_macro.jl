function sometimes_throws(x)
    if isequal(x, 0)
        return nothing 
    else
        throw(ArgumentError("Didn't get my favourite value"))
    end
end

function sometimes_fails(a, b)
    if isnothing(a) || a == 2*b 
        return true 
    else
        return false 
    end
end

multi_valued(x) = x[1], x[2]^2

multi_input(x, y) = x+y

multi_input_kwargs(x; y) = x*y

const TEST_EXPR_KEY = TestingUtilities._DEFAULT_TEST_EXPR_KEY

append_char(x, c; n::Int) = x * repeat(c, n)

macro sample_macro(f, x)
    return quote 
        $f($x)
    end |> esc
end

@testset "@Test" begin 
    @testset "Util" begin 
        @testset "set_failed_values_in_main" begin 
            @eval Main $(:(var1 = gensym(:var1); var2 = gensym(:var2); var3 = gensym(:var3)))
            var1_name = Main.var1 
            var2_name = Main.var2
            var3_name = Main.var3
            for v in (var1_name, var2_name, var3_name)
                @test !hasproperty(Main, v)
            end
            vals = TestingUtilities.OrderedDict{Symbol,Any}(var1_name => 1, var2_name => 2, var3_name => 3)
            TestingUtilities.set_failed_values_in_main(vals, false, force=false)
            for v in (var1_name, var2_name, var3_name)
                @test !hasproperty(Main, v)
            end
            TestingUtilities.set_failed_values_in_main(vals, true, force=true)
            for v in (var1_name, var2_name, var3_name)
                @test getproperty(Main, v) == vals[v]
            end
            # Don't overwrite explicitly imported variables 
            @eval Main import Base.vcat
            vals = TestingUtilities.OrderedDict{Symbol,Any}(:vcat => 1)
            TestingUtilities.update_imported_names_in_main()

            TestingUtilities.emit_warnings(true)
            try 
                @test_logs (:warn, "Variable vcat (= 1) not set in Main -- name already exists and is imported in module") TestingUtilities.set_failed_values_in_main(vals, true, force=true)
            finally 
                TestingUtilities.emit_warnings(false)
            end
            @test Main.vcat === Base.vcat

            @eval Main using WidthLimitedIO 
            TestingUtilities.update_imported_names_in_main()
            vals = TestingUtilities.OrderedDict{Symbol,Any}(:ansi_esc_status => 1)
            TestingUtilities.emit_warnings(true)
            try 
                @test_logs (:warn, "Variable ansi_esc_status (= 1) not set in Main -- name already exists and is imported in module") TestingUtilities.set_failed_values_in_main(vals, true, force=true)
            finally 
                TestingUtilities.emit_warnings(false)
            end
            @test Main.ansi_esc_status === Main.WidthLimitedIO.ansi_esc_status
        end
        @testset "parse_args_kwargs" begin 
            test_data = [
                (expr = :(f()), result = (call_func = :f, args=[], kwargs=[])),
                (expr = :(f(a)), result = (call_func = :f, args=[:a], kwargs=[])),
                (expr = :(f(a, g(h))), result = (call_func = :f, args=[:a, :(g(h))], kwargs=[])),
                (expr = :(f(a, g(h), k=8)), result = (call_func = :f, args=[:a, :(g(h))], kwargs=[:k => :8])),
                (expr = :(f(a, g(h), k=8; kv1)), result = (call_func = :f, args=[:a, :(g(h))], kwargs=[:kv1 => :kv1, :k => :8])),
                (expr = :(f(a, g(h), k=8; kv1, kv2=rhs())), result = (call_func = :f, args=[:a, :(g(h))], kwargs=[:kv1 => :kv1, :kv2 => :(rhs()), :k => :8])),
                (expr = :((a,)), result = (call_func = :tuple, args=[:a], kwargs=[])),
                (expr = :((a,b)), result = (call_func = :tuple, args=[:a,:b], kwargs=[])),
                (expr = :((a,b,c=1)), result = (call_func = :tuple, args=[:a,:b], kwargs=[:c => 1])),
                (expr = :((a,b,c=1; d, e=f(h))), result = (call_func = :tuple, args=[:a,:b], kwargs=[:d => :d, :e => :(f(h)), :c => 1])),
                (expr = :([a]), result = (call_func = :(Base.vect), args=[:a], kwargs=[])),
                (expr = :([a,b]), result = (call_func = :(Base.vect), args=[:a,:b], kwargs=[])),
                (expr = :([a;b]), result = (call_func = :vcat, args=[:a,:b], kwargs=[])),
                (expr = :(f(a...)), result = (call_func = :f, args=[:(a...)], kwargs=[])),
                (expr = :(a...), result = (call_func = :..., args=[:a], kwargs=[])),
                (expr = :(a[]), result = (call_func = :ref, args=[:a], kwargs=[])),
                (expr = :(a[b]), result = (call_func = :ref, args=[:a,:b], kwargs=[])),
                (expr = :(a.b), result = (call_func = :., args=[:a,QuoteNode(:b)], kwargs=[])),
                (expr = :(a for a in T if a > 0), result = (call_func = :generator, args=[:a, Expr(:filter, :(a > 0), :(a = T))], kwargs=[]))
            ]
            for data in test_data 
                @test isequal(TestingUtilities.parse_args_kwargs(data.expr), tuple(values(data.result)...))
            end 
        end
        @testset "_computational_graph!" begin 
            graph = OrderedDict{Any,Any}()
            expr = :(f(a, g(b)))
            graph[TEST_EXPR_KEY] = expr
            @test TestingUtilities._computational_graph!(graph, expr) == [:a, :(g(b))]
            @test graph == OrderedDict(TEST_EXPR_KEY => :(f(arg1, arg2)), :arg1 => :a, :arg2 => :(g(b)))

            expr = :(g(b))
            @test TestingUtilities._computational_graph!(graph, expr) == [:b]
            @test graph == OrderedDict(TEST_EXPR_KEY => :(f(arg1, arg2)), :arg1 => :a, :arg2 => :(g(arg3)), :arg3 => :b)
            
            # args + kwargs
            graph = OrderedDict{Any,Any}()
            expr = :(f(a, g(b^2), k=z(q)))
            graph[TEST_EXPR_KEY] = expr
            @test TestingUtilities._computational_graph!(graph, expr) == [:a, :(g(b^2)), :(z(q))]
            @test graph == OrderedDict(TEST_EXPR_KEY => :(f(arg1, arg2; k=kwarg3)), :arg1 => :a, :arg2 => :(g(b^2)), :kwarg3 => :(z(q)))

            expr = :(g(b^2))
            @test TestingUtilities._computational_graph!(graph, expr) == [:(b^2)]
            @test graph == OrderedDict(TEST_EXPR_KEY => :(f(arg1, arg2; k=kwarg3)), :arg1 => :a, :arg2 => :(g(arg4)), :kwarg3 => :(z(q)), :arg4 => :(b^2))

            expr = :(b^2)
            @test TestingUtilities._computational_graph!(graph, expr) == [:b]
            @test graph == OrderedDict(TEST_EXPR_KEY => :(f(arg1, arg2; k=kwarg3)), :arg1 => :a, :arg2 => :(g(arg4)), :kwarg3 => :(z(q)), :arg4 => :(arg5^2), :arg5 => :b)

            expr = :(z(q))
            @test TestingUtilities._computational_graph!(graph, expr) == [:q]
            @test graph == OrderedDict(TEST_EXPR_KEY => :(f(arg1, arg2; k=kwarg3)), :arg1 => :a, :arg2 => :(g(arg4)), :kwarg3 => :(z(arg6)), :arg4 => :(arg5^2), :arg5 => :b, :arg6 => :q)

            graph = OrderedDict{Any,Any}()
            expr = :(f(a; k, l=A.m(123, false, z)))
            graph[TEST_EXPR_KEY] = expr
            @test TestingUtilities._computational_graph!(graph, expr) == [:a, :k, :(A.m(123, false, z))]
            @test graph == OrderedDict(TEST_EXPR_KEY => :(f(arg1; k=kwarg2, l=kwarg3)), :arg1 => :a, :kwarg2 => :k, :kwarg3 => :(A.m(123, false, z)))

            expr = :(A.m(123, false, z))
            @test TestingUtilities._computational_graph!(graph, expr) == [:z]
            @test graph == OrderedDict(TEST_EXPR_KEY => :(f(arg1; k=kwarg2, l=kwarg3)), :arg1 => :a, :kwarg2 => :k, :kwarg3 => :(A.m(123, false, arg4)), :arg4 => :z)
            
            # vect expression
            graph = OrderedDict{Any,Any}()
            expr = :([a, g(b)])
            graph[TEST_EXPR_KEY] = expr
            @test TestingUtilities._computational_graph!(graph, expr) == [:a, :(g(b))]
            @test graph == OrderedDict(TEST_EXPR_KEY => :(Base.vect(arg1, arg2)), :arg1 => :a, :arg2 => :(g(b)))

            expr = :(g(b))
            @test TestingUtilities._computational_graph!(graph, expr) == [:b]
            @test graph == OrderedDict(TEST_EXPR_KEY => :(Base.vect(arg1, arg2)), :arg1 => :a, :arg2 => :(g(arg3)), :arg3 => :b)
            
            # Splatted arg
            graph = OrderedDict{Any,Any}()
            expr = :([h(a)...])
            graph[TEST_EXPR_KEY] = expr
            @test TestingUtilities._computational_graph!(graph, expr) == [:(h(a))]
            @test graph == OrderedDict(TEST_EXPR_KEY => :(Base.vect(arg1...)), :arg1 => :(h(a)))
            
            @test TestingUtilities._computational_graph!(graph, :(h(a))) == [:a]
            @test graph == OrderedDict(TEST_EXPR_KEY => :(Base.vect(arg1...)), :arg1 => :(h(arg2)), :arg2 => :a)
            
            # args + keyword arguments with literal value 
            graph = OrderedDict{Any,Any}()
            expr = :(f(a, g(b^2), k=7))
            graph[TEST_EXPR_KEY] = expr
            @test TestingUtilities._computational_graph!(graph, expr) == [:a, :(g(b^2))]
            @test graph == OrderedDict(TEST_EXPR_KEY => :(f(arg1, arg2; k=7)), :arg1 => :a, :arg2 => :(g(b^2)))
            
            @test TestingUtilities._computational_graph!(graph, :(g(b^2))) == [:(b^2)]
            @test graph == OrderedDict(TEST_EXPR_KEY => :(f(arg1, arg2; k=7)), :arg1 => :a, :arg2 => :(g(arg3)), :arg3 => :(b^2))

            @test TestingUtilities._computational_graph!(graph, :(b^2)) == [:b]
            
            @test graph == OrderedDict(TEST_EXPR_KEY => :(f(arg1, arg2; k=7)), :arg1 => :a, :arg2 => :(g(arg3)), :arg3 => :(arg4^2), :arg4 => :b)

            # Ref expressions 
            graph = OrderedDict{Any,Any}()
            expr = :(a[b,g(h)])
            graph[TEST_EXPR_KEY] = expr
            @test TestingUtilities._computational_graph!(graph, expr) == [:a, :b, :(g(h))]
            @test graph == OrderedDict(TEST_EXPR_KEY => :(arg1[arg2, arg3]), :arg1 => :a, :arg2 => :b, :arg3 => :(g(h)))
            @test TestingUtilities._computational_graph!(graph, :(g(h))) == [:h]
            @test graph == OrderedDict(TEST_EXPR_KEY => :(arg1[arg2, arg3]), :arg1 => :a, :arg2 => :b, :arg3 => :(g(arg4)), :arg4 => :h)
            
            # Ref expression with reserved keywords 
            graph = OrderedDict{Any,Any}()
            expr = :(a[b, end])
            graph[TEST_EXPR_KEY] = expr
            @test TestingUtilities._computational_graph!(graph, expr) == [:a, :b]
            @test graph == OrderedDict(TEST_EXPR_KEY => :(arg1[arg2, end]), :arg1 => :a, :arg2 => :b)

            # Generators
            graph = OrderedDict{Any,Any}()
            graph[TEST_EXPR_KEY] = :(all(isequal(df[x], y) for x in setdiff(A, [:dates])))
            @test TestingUtilities._computational_graph!(graph, graph[TEST_EXPR_KEY]) == [:(setdiff(A, [:dates]))]
            @test graph == OrderedDict(TEST_EXPR_KEY => :(all(isequal(df[x],y) for x in arg1)), :arg1 => :(setdiff(A, [:dates])))

            # There are no children for expressions which are composed of literals/quote nodes 
            @test TestingUtilities._computational_graph!(graph, :(setdiff(A, [:dates]))) == [:A]
            @test graph == OrderedDict(TEST_EXPR_KEY => :(all(isequal(df[x],y) for x in arg1)), :arg1 => :(setdiff(arg2, [:dates])), :arg2 => :A)


            # Generators over multiple collections
            graph = OrderedDict{Any,Any}()
            graph[TEST_EXPR_KEY] = :(all(isequal(df[x], y) for x in setdiff(A, [:dates]), y in H(z)))
            @test TestingUtilities._computational_graph!(graph, graph[TEST_EXPR_KEY]) == [:(setdiff(A, [:dates])), :(H(z))]
            @test graph == OrderedDict(TEST_EXPR_KEY => Expr(:call, :all, Expr(:generator, :(isequal(df[x], y)), Expr(:(=), :x, :arg1), Expr(:(=), :y, :arg2))), :arg1 => :(setdiff(A, [:dates])), :arg2 => :(H(z)))
        end
        @testset "computational_graph" begin 
            expr = :(f())
            result = TestingUtilities.computational_graph(expr)
            @test result == OrderedDict(TEST_EXPR_KEY => :(f()),)
            expr = :(a == 5)
            result = TestingUtilities.computational_graph(expr)
            @test result == OrderedDict(TEST_EXPR_KEY => :(arg1 == 5), :arg1 => :a)

            expr = :(f(A.b, x, y))
            result = TestingUtilities.computational_graph(expr)
            @test result == OrderedDict(TEST_EXPR_KEY => :(f(arg1, arg2, arg3)), :arg1 => :(A.b), :arg2 => :x, :arg3 => :y)

            expr = :(f(A.b(z), x, y))
            result = TestingUtilities.computational_graph(expr)
            @test result == OrderedDict(TEST_EXPR_KEY => :(f(arg1, arg2, arg3)), :arg1 => :(A.b(arg4)), :arg2 => :x, :arg3 => :y, :arg4 => :z)

            expr = :(f(a, b; c, d=g(x,y)))
            result = TestingUtilities.computational_graph(expr)
            @test result == OrderedDict(TEST_EXPR_KEY => :(f(arg1, arg2; c=kwarg3, d=kwarg4)), :arg1 => :a, :arg2 => :b, :kwarg3 => :c, :kwarg4 => :(g(arg5, arg6)), :arg5 => :x, :arg6 => :y)

            expr = :(f(a, g(b^2), k=z(q)))
            result = TestingUtilities.computational_graph(expr)
            @test result == OrderedDict(TEST_EXPR_KEY => :(f(arg1, arg2; k = kwarg3)), :arg1 => :a, :arg2 => :(g(arg4)), :kwarg3 => :(z(arg6)), :arg4 => :(arg5^2), :arg5 => :b, :arg6 => :q )

            expr = :(f(a, g(b^2), k=10))
            result = TestingUtilities.computational_graph(expr)
            @test result == OrderedDict(TEST_EXPR_KEY => :(f(arg1, arg2; k = 10)), :arg1 => :a, :arg2 => :(g(arg3)), :arg3 => :(arg4^2), :arg4 => :b)

            expr = :(f(a, g(b^2), k=b^2))
            result = TestingUtilities.computational_graph(expr)
            @test result == OrderedDict(TEST_EXPR_KEY => :(f(arg1, arg2; k = kwarg3)), :arg1 => :a, :arg2 => :(g(kwarg3)), :kwarg3 => :(arg4^2), :arg4 => :b)

            expr = :([a, g(b)])
            result = TestingUtilities.computational_graph(expr)
            @test result == OrderedDict(TEST_EXPR_KEY => :(Base.vect(arg1, arg2)), :arg1 => :a, :arg2 => :(g(arg3)), :arg3 => :b )

            expr = :([a; g(b)])
            result = TestingUtilities.computational_graph(expr)
            @test result == OrderedDict(TEST_EXPR_KEY => :(vcat(arg1, arg2)), :arg1 => :a, :arg2 => :(g(arg3)), :arg3 => :b )

            expr = :(abc[f(i)])
            result = TestingUtilities.computational_graph(expr)
            @test result == OrderedDict(TEST_EXPR_KEY => :(arg1[arg2]), :arg1 => :abc, :arg2 => :(f(arg3)), :arg3 => :i )

            expr = :(f[begin, end, 1])
            result = TestingUtilities.computational_graph(expr)
            @test result == OrderedDict(TEST_EXPR_KEY => :(arg1[begin,end,1]), :arg1 => :f )

            expr = :(f[a.b])
            result = TestingUtilities.computational_graph(expr)
            @test result == OrderedDict(TEST_EXPR_KEY => :(arg1[arg2]), :arg1 => :f, :arg2 => :(a.b) )

            # Don't recurse into generators, only grab their body expression
            # No filtering condition
            expr = :(all(a for a in T if a > 0))
            result = TestingUtilities.computational_graph(expr)
            @test result == OrderedDict(TEST_EXPR_KEY => :(all(a for a in arg1 if a > 0)), :arg1 => :T)

            # Don't recurse into anonymous function definitions 
            expr = Base.remove_linenums!(:(sprint((io,x)->show(io, x), abc)))
            result = TestingUtilities.computational_graph(expr)
            @test result == OrderedDict(TEST_EXPR_KEY => :(sprint(arg1, arg2)), :arg1 => Base.remove_linenums!(:((io, x)->show(io, x))), :arg2 => :abc)

            # Filtering condition
            expr = :(all(ai > 2 for ai in a if mod(ai,2) == 0))
            result = TestingUtilities.computational_graph(expr)
            @test result == OrderedDict(TEST_EXPR_KEY => :(all(ai > 2 for ai in arg1 if mod(ai,2)== 0)), :arg1 => :a)

            expr = :(all(ai > 2 for ai in [a,h(b),c] if mod(ai,2) == 0))
            result = TestingUtilities.computational_graph(expr)
            @test result == OrderedDict(TEST_EXPR_KEY => :(all(ai > 2 for ai in arg1 if mod(ai,2)== 0)), :arg1 => :(Base.vect(arg2, arg3, arg4)), :arg2 => :a, :arg3 => :(h(arg5)), :arg4 => :c, :arg5 => :b)

            expr = :(f(Dict{Int,String}))
            result = TestingUtilities.computational_graph(expr)
            @test result == OrderedDict(TEST_EXPR_KEY => :(f(arg1)), :arg1 => :(Dict{Int,String}))

            expr = :(b isa Vector)
            result = TestingUtilities.computational_graph(expr)
            @test result == OrderedDict(TEST_EXPR_KEY => :(arg1 isa Vector), :arg1 => :(b))

            expr = :(f('c', x))
            result = TestingUtilities.computational_graph(expr)
            @test result == OrderedDict(TEST_EXPR_KEY => :(f('c', arg1)), :arg1 => :(x))

            expr = :(g(x) == :(f(a,b)))
            result = TestingUtilities.computational_graph(expr)
            @test result == OrderedDict(TEST_EXPR_KEY => :(arg1 == :(f(a,b))), :arg1 => :(g(arg2)), :arg2 => :x)

            expr = Expr(:call, :isequal, Expr(:macrocall, QuoteNode(Symbol("@a")), nothing, :a, :(f(x))), :(b))
            result = TestingUtilities.computational_graph(expr)
            @test result == OrderedDict(TEST_EXPR_KEY => Expr(:call, :isequal, :arg1, :arg2), :arg1 => Expr(:macrocall, QuoteNode(Symbol("@a")), nothing, :a, :(f(x))), :arg2 => :(b))
        end
    end
    @testset "@testset behaviour" begin 
        results = Test.@testset NoThrowTestSet "Comparison" begin 
            io = IOBuffer()
            a = 1
            @Test io=io a == 2 
            message = String(take!(io))
            @test message == "Test `a == 2` failed:\nValues:\na = $a\n"
            b = Ref(false)
            @Test io=io b[]
            message = String(take!(io))
            @test message == "Test `b[]` failed:\nValues:\nb[] = $(b[])\n"
        end
        @test test_results_match(results, (Test.Fail, Test.Pass, Test.Fail, Test.Pass))

        results = Test.@testset NoThrowTestSet "Comparison to string" begin 
            io = IOBuffer()
            a = "abc"
            b = "abcd"
            @Test io=io a == "def" 
            message = String(take!(io))
            @test message == "Test `a == \"def\"` failed:\nValues:\nexpected = \"def\"\na        = \"abc\"\n"
            @Test io=io a == b
            message = String(take!(io))
            @test message == "Test `a == b` failed:\nValues:\na = \"abc\"\nb = \"abcd\"\n"
            @Test io=io append_char(a,'d'; n=5) == b 
            message = String(take!(io))
            @test message == "Test `append_char(a, 'd'; n = 5) == b` failed:\nValues:\nappend_char(a, 'd'; n = 5) = \"abcddddd\"\nb                          = \"abcd\"\na = \"abc\"\n"
            @Test io=io isequal("abcde", append_char(a,'d'; n=3))
            message = String(take!(io))
            @test message == "Test `isequal(\"abcde\", append_char(a, 'd'; n = 3))` failed:\nValues:\nexpected                   = \"abcde\"\nappend_char(a, 'd'; n = 3) = \"abcddd\"\na = \"abc\"\n"
        end
        @test test_results_match(results, (Test.Fail, Test.Pass, Test.Fail, Test.Pass, Test.Fail, Test.Pass, Test.Fail, Test.Pass))

        if run_df_tests
            TestingUtilities.set_show_df_opts(; max_num_rows=3, max_num_cols=3)
            TestingUtilities.set_show_diff_df_opts(; max_num_rows=10, max_num_cols=10)
            results = Test.@testset NoThrowTestSet "Comparison to DataFrame" begin 
                io = IOBuffer()
                a = DataFrame(:b => [1,2,3], :c => [1.0, 2.0, 3.0])
                b = DataFrame(:d => [1,2,3], :c => [1.0, 2.0, 3.0])
                c = DataFrame(:b => [1,-2,3], :c => [-1.0, 2.0, 3.0])
                d = DataFrame( (Symbol("a$i") => (i:i+10) for i in 1:10)... )
                d_ref = Ref(d)
                a2 = a[1:2,:]
                
                @Test io=io a == b 
                message = String(take!(io))
                @test message == "Test `a == b` failed:\nReason: `propertynames(a) != propertynames(b)`\n`propertynames(a)` = {:c, :b}\n`propertynames(b)` = {:c, :d}\n"

                @Test io=io a == a2
                message = String(take!(io))
                @test message == "Test `a == a2` failed:\nReason: `nrow(a) != nrow(a2)`\n`nrow(a)`  = 3\n`nrow(a2)` = 2\n"

                @Test io=io a == c 
                message = String(take!(io))
                @test message == "Test `a == c` failed:\nReason: Mismatched values\n┌───────────────────┬────────┬───────┬─────────┐\n│           row_num │     df │     b │       c │\n│ U{Nothing, Int64} │ Symbol │ Int64 │ Float64 │\n├───────────────────┼────────┼───────┼─────────┤\n│                 1 │      a │     1 │     1.0 │\n│                   │      c │     1 │    -1.0 │\n│                 2 │      a │     2 │     2.0 │\n│                   │      c │    -2 │     2.0 │\n└───────────────────┴────────┴───────┴─────────┘\n"

                @Test io=io nrow(d) == 1
                message = String(take!(io))
                @test message == "Test `nrow(d) == 1` failed:\nValues:\n`nrow(d)` = 11\nd = ┌───────┬───────┬───────┬───┐\n    │    a1 │    a2 │    a3 │ … │\n    │ Int64 │ Int64 │ Int64 │   │\n    ├───────┼───────┼───────┼───┤\n    │     1 │     2 │     3 │ ⋯ │\n    │     2 │     3 │     4 │   │\n    │     3 │     4 │     5 │   │\n    │     ⋮ │     ⋮ │     ⋮ │   │\n    └───────┴───────┴───────┴───┘\n"

                @Test io=io nrow(d_ref[]) == 1
                message = String(take!(io))
                @test message == "Test `nrow(d_ref[]) == 1` failed:\nValues:\n`nrow(d_ref[])` = 11\nd_ref[] = ┌───────┬───────┬───────┬───┐\n          │    a1 │    a2 │    a3 │ … │\n          │ Int64 │ Int64 │ Int64 │   │\n          ├───────┼───────┼───────┼───┤\n          │     1 │     2 │     3 │ ⋯ │\n          │     2 │     3 │     4 │   │\n          │     3 │     4 │     5 │   │\n          │     ⋮ │     ⋮ │     ⋮ │   │\n          └───────┴───────┴───────┴───┘\n"

            end
            @test test_results_match(results, (Test.Fail, Test.Pass, Test.Fail, Test.Pass, Test.Fail, Test.Pass, Test.Fail, Test.Pass))
        end

        results = Test.@testset NoThrowTestSet "Invalid Test" begin 
            io = IOBuffer()
            a = 1
            @Test io=io a 
            message = String(take!(io))
            @test message == "Test `a` failed:\n"

            @Test io=io a^2
            message = String(take!(io))
            @test message == "Test `a ^ 2` failed:\nValues:\na = $a\n"
        end
        @test test_results_match(results, (Test.Error, Test.Pass, Test.Error, Test.Pass))

        results = Test.@testset NoThrowTestSet "Failing test with curly expressions" begin 
            io = IOBuffer()
            b = Dict{String,Int}
            @Test io=io typeof(b) <: Vector 
            message = String(take!(io))
            @test message == "Test `typeof(b) <: Vector` failed:\nValues:\n`typeof(b)` = DataType\nb = Dict{String, Int64}\n"
            @Test io=io b() isa Vector
            message = String(take!(io))
            @test message == "Test `b() isa Vector` failed:\nValues:\n`b()` = Dict{String, Int64}()\n"
        end
        @test test_results_match(results, (Test.Fail, Test.Pass, Test.Fail, Test.Pass))

        results = Test.@testset NoThrowTestSet "Failing test with quoted expressions" begin 
            io = IOBuffer()
            g = t->:($t)
            @Test io=io g(:x) == :(f(a,b))
            message = String(take!(io))
            @test message == "Test `g(:x) == :(f(a, b))` failed:\nValues:\n`g(:x)` = :x\n"
        end
        @test test_results_match(results, (Test.Fail, Test.Pass))

        results = Test.@testset NoThrowTestSet "Failing test with macro expression" begin 
            io = IOBuffer()
            f = t->t^2 
            a = 2
            @Test io=io @sample_macro(f, a) > 5
            message = String(take!(io))
            @test message == "Test `@sample_macro(f, a) > 5` failed:\nValues:\n`@sample_macro(f, a)` = 4\n"
        end
        @test test_results_match(results, (Test.Fail, Test.Pass))

        results = Test.@testset NoThrowTestSet "Nested expression - single variable - success" begin 
            io = IOBuffer()
            a = 0
            @Test io=io isnothing(sometimes_throws(a)) 
            message = String(take!(io))
            @test isempty(message)
        end
        @test test_results_match(results, (Test.Pass, Test.Pass))

        results = Test.@testset NoThrowTestSet "Nested expression - single variable - throws" begin
            io = IOBuffer()
            a = 1
            @Test io=io isnothing(sometimes_throws(a)) 
            message = String(take!(io))
            @test message == "Test `isnothing(sometimes_throws(a))` failed:\nValues:\na = $a\n"
        end
        @test test_results_match(results, (Test.Error, Test.Pass))

        results = Test.@testset NoThrowTestSet "Nested expression - single variable - throws" begin
            io = IOBuffer()
            a = 2
            @Test io=io isnothing(sometimes_throws(a^2)) 
            message = String(take!(io))
            @test message == "Test `isnothing(sometimes_throws(a ^ 2))` failed:\nValues:\na = $a\n"
        end
        @test test_results_match(results, (Test.Error, Test.Pass))

        results = Test.@testset NoThrowTestSet "Nested expression - single variable w/ dot - throws" begin
            io = IOBuffer()
            a = (; b=2)
            @Test io=io isnothing(sometimes_throws(a.b)) 
            message = String(take!(io))
            @test message == "Test `isnothing(sometimes_throws(a.b))` failed:\nValues:\n`a.b` = $(a.b)\n"
        end
        @test test_results_match(results, (Test.Error, Test.Pass))

        results = Test.@testset NoThrowTestSet "Nested expression - generator - fails" begin
            io = IOBuffer()
            a = 1:10
            b = -5:-1
            @Test io=io all( ai < 5 for ai in a )
            message = String(take!(io))
            @test message == "Test `all((ai < 5 for ai = a))` failed:\nValues:\na = $a\n"
            @Test io=io all( ai < 5 for ai in vcat(a, b) if mod(ai, 2) == 0)
            message = String(take!(io))
            @test message == "Test `all((ai < 5 for ai = vcat(a, b) if mod(ai, 2) == 0))` failed:\nValues:\na = $a\nb = $b\n"
        end
        @test test_results_match(results, (Test.Fail, Test.Pass, Test.Fail, Test.Pass))

        results = Test.@testset NoThrowTestSet "Nested expression - single variable too long to print fully - throws" begin
            io = TextWidthLimiter(IOBuffer(), 100)
            a = repeat([1], 1000)
            @Test io=io isnothing(sometimes_throws(a[1]^2)) 
            message = String(take!(io))
            @test message == "Test `isnothing(sometimes_throws(a[1] ^ 2))` failed:\nValues:\na = [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,…\n"
        end
        @test test_results_match(results, (Test.Error, Test.Pass))

        results = Test.@testset NoThrowTestSet "Nested expression - single variable - throws" begin
            g = x->2x
            a = nothing
            b = 1 
            io = IOBuffer()
            @Test sometimes_fails(a, g(b))
            message = String(take!(io))
            @test isempty(message)

            a = 2
            @Test io=io set_failed_values=true sometimes_fails(a, g(b))
            message = String(take!(io))
            @test message == "Test `sometimes_fails(a, g(b))` failed:\nValues:\na = $a\n`g(b)` = $(g(b))\nb = $b\n"
        end
        @test test_results_match(results, (Test.Pass, Test.Pass, Test.Fail, Test.Pass))

        if Base.isinteractive()
            @test hasproperty(Main, :a) && Main.a == 2 && hasproperty(Main, :b) && Main.b == 1
        else 
            @test !hasproperty(Main, :a)
            @test !hasproperty(Main, :b)
        end

        results = Test.@testset NoThrowTestSet "Reference expression" begin
            io = IOBuffer()
            a = [1, 2, 3]
            @Test io=io a[2] == 3
            message = String(take!(io))
            @test message == "Test `a[2] == 3` failed:\nValues:\n`a[2]` = 2\na = $a\n"
        end
        @test test_results_match(results, (Test.Fail, Test.Pass))

        results = Test.@testset NoThrowTestSet "Reference expression - reserved keyword" begin
            io = IOBuffer()
            a = [1, 2, 3]
            @Test io=io a[begin] == 3
            message = String(take!(io))
            @test message == "Test `a[begin] == 3` failed:\nValues:\n`a[begin]` = 1\na = $a\n"
        end
        @test test_results_match(results, (Test.Fail, Test.Pass))

        results = Test.@testset NoThrowTestSet "Nested expression - keyword arguments - fails" begin
            io = IOBuffer()
            x = 1
            y = 2
            @Test io=io multi_input_kwargs(x; y) == 4
            message = String(take!(io))
            @test message == "Test `multi_input_kwargs(x; y) == 4` failed:\nValues:\n`multi_input_kwargs(x; y)` = 2\nx = $x\ny = $y\n"

            z = 2
            @Test io=io multi_input_kwargs(x; y=z) == 4
            message = String(take!(io))
            @test message == "Test `multi_input_kwargs(x; y = z) == 4` failed:\nValues:\n`multi_input_kwargs(x; y = z)` = 2\nx = $x\nz = $y\n"
        end
        @test test_results_match(results, (Test.Fail, Test.Pass))

        results = Test.@testset NoThrowTestSet "Short-circuiting operators" begin 
            io = IOBuffer()
            f = t->!t
            x = true 
            y = false 
            @Test io=io f(x) && y
            message = String(take!(io))
            @test message == "Test `f(x) && y` failed:\nValues:\n`f(x)` = false\ny = false\nx = true\n"
            @Test io=io f(x) ? y : !x
            message = String(take!(io))
            @test message == "Test `f(x) ? y : !x` failed:\nValues:\n`f(x)` = false\ny = false\n`!x` = false\n"
        end
        @test test_results_match(results, (Test.Fail, Test.Pass, Test.Fail, Test.Pass))

        results = Test.@testset NoThrowTestSet "Splatting" begin
            a = (1, 2)
            io = IOBuffer()
            @Test io=io multi_valued(a) == (1, 4)
            message = String(take!(io))
            @test isempty(message)

            a = (2, 2)
            @Test io=io multi_valued(a) == (1, 4)
            message = String(take!(io))
            @test message == "Test `multi_valued(a) == (1, 4)` failed:\nValues:\n`multi_valued(a)` = (2, 4)\na = $a\n"

            @Test io=io multi_valued((a,)...) == (1, 4)
            message = String(take!(io))
            @test message == "Test `multi_valued((a,)...) == (1, 4)` failed:\nValues:\n`multi_valued((a,)...)` = (2, 4)\na = $a\n"

            @Test io=io multi_input((a.^2)...) == 5
            message = String(take!(io))
            @test message == "Test `multi_input(a .^ 2...) == 5` failed:\nValues:\n`multi_input(a .^ 2...)` = 8\na = (2, 2)\n"
        end
        @test test_results_match(results, (Test.Pass, Test.Pass, Test.Fail, Test.Pass, Test.Fail, Test.Pass, Test.Fail, Test.Pass))
        
        results = Test.@testset NoThrowTestSet "Generators" begin
            a = 1:10
            io = IOBuffer()
            @Test io=io all(ai > 2 for ai in a if mod(ai,2) == 0)
            message = String(take!(io))
            @test message == "Test `all((ai > 2 for ai = a if mod(ai, 2) == 0))` failed:\nValues:\na = $a\n"
        end
        @test test_results_match(results, (Test.Fail, Test.Pass))

        test_data = [
            (; a=4, b=1),
            (; a=1, b=3),
        ]
        results = Test.@testset NoThrowTestSet "Tests inside for-loop - second one throws" begin 
            io = IOBuffer()
            g = x->2x
            for data in test_data 
                a = data.a 
                b = data.b
                if a == 4
                    @Test set_failed_values=true io=io sometimes_fails(a, g(b))
                else
                    @Test set_failed_values=true io=io sometimes_fails(a, g(b)) 
                end
            end
            message = String(take!(io))
            @test message == "Test `sometimes_fails(a, g(b))` failed:\nValues:\na = 1\n`g(b)` = 6\nb = 3\n"
        end
        @test test_results_match(results, (Test.Pass, Test.Fail, Test.Pass))

        if Base.isinteractive()
            @test hasproperty(Main, :a) && Main.a == 1 && hasproperty(Main, :b) && Main.b == 3
        else 
            @test !hasproperty(Main, :a)
            @test !hasproperty(Main, :b)
        end
    end
end