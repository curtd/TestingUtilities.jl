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
            @test_logs (:warn, "Variable vcat (= 1) not set in Main -- name already exists and is imported in module") TestingUtilities.set_failed_values_in_main(vals, true, force=true)
            @test Main.vcat === Base.vcat
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

            @test TestingUtilities._computational_graph!(graph, :(setdiff(A, [:dates]))) == [:A, :([:dates])]
            @test graph == OrderedDict(TEST_EXPR_KEY => :(all(isequal(df[x],y) for x in arg1)), :arg1 => :(setdiff(arg2, arg3)), :arg2 => :A, :arg3 => :([:dates]))

            # There are no children for expressions which are composed of literals/quote nodes 
            @test TestingUtilities._computational_graph!(graph, :([:dates])) |> isempty
            @test graph == OrderedDict(TEST_EXPR_KEY => :(all(isequal(df[x],y) for x in arg1)), :arg1 => :(setdiff(arg2, arg3)), :arg2 => :A, :arg3 => :(Base.vect(:dates)))

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

            expr = :(f(a, b; c, d=g(x,y)))
            result = TestingUtilities.computational_graph(expr)
            @test result == OrderedDict(TEST_EXPR_KEY => :(f(arg1, arg2; c=kwarg3, d=kwarg4)), :arg1 => :a, :arg2 => :b, :kwarg3 => :c, :kwarg4 => :(g(arg5, arg6)), :arg5 => :x, :arg6 => :y)

            expr = :(f(a, g(b^2), k=z(q)))
            result = TestingUtilities.computational_graph(expr)
            @test result == OrderedDict(TEST_EXPR_KEY => :(f(arg1, arg2; k = kwarg3)), :arg1 => :a, :arg2 => :(g(arg4)), :kwarg3 => :(z(arg6)), :arg4 => :(arg5^2), :arg5 => :b, :arg6 => :q )

            expr = :(f(a, g(b^2), k=10))
            result = TestingUtilities.computational_graph(expr)
            @test result == OrderedDict(TEST_EXPR_KEY => :(f(arg1, arg2; k = 10)), :arg1 => :a, :arg2 => :(g(arg3)), :arg3 => :(arg4^2), :arg4 => :b)

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
            @test result == OrderedDict(TEST_EXPR_KEY => :(arg1[arg2]), :arg1 => :f, :arg2 => :(arg3.b), :arg3 => :a )

            # Don't recurse into generators, only grab their body expression
            # No filtering condition
            expr = :(all(a for a in T if a > 0))
            result = TestingUtilities.computational_graph(expr)
            @test result == OrderedDict(TEST_EXPR_KEY => :(all(a for a in arg1 if a > 0)), :arg1 => :T)

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
        end
        @testset "Misc" begin 
            @test TestingUtilities.should_define_vars_in_failed_tests(false) == false
            @test TestingUtilities.should_define_vars_in_failed_tests(true) == Base.isinteractive()
        end
    end
    @testset "@testset behaviour" begin 
        results = Test.@testset NoThrowTestSet "Comparison" begin 
            io = IOBuffer()
            a = 1
            @Test io=io a == 2 
            message = String(take!(io))
            @test message == "Test `a == 2` failed with values:\na = $a\n"
        end
        @test test_results_match(results, (Test.Fail, Test.Pass))

        results = Test.@testset NoThrowTestSet "Invalid Test" begin 
            io = IOBuffer()
            a = 1
            @Test io=io a 
            message = String(take!(io))
            @test message == "Test `a` failed with values:\n"

            @Test io=io a^2
            message = String(take!(io))
            @test message == "Test `a ^ 2` failed with values:\na = $a\n"
        end
        @test test_results_match(results, (Test.Error, Test.Pass, Test.Error, Test.Pass))

        results = Test.@testset NoThrowTestSet "Failing test with curly expressions" begin 
            io = IOBuffer()
            b = Dict{String,Int}
            @Test io=io typeof(b) <: Vector 
            message = String(take!(io))
            @test message == "Test `typeof(b) <: Vector` failed with values:\n`typeof(b)` = DataType\nb = Dict{String, Int64}\n"
            @Test io=io b() isa Vector
            message = String(take!(io))
            @test message == "Test `b() isa Vector` failed with values:\n`b()` = Dict{String, Int64}()\n"
        end
        @test test_results_match(results, (Test.Fail, Test.Pass, Test.Fail, Test.Pass))

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
            @test message == "Test `isnothing(sometimes_throws(a))` failed with values:\na = $a\n"
        end
        @test test_results_match(results, (Test.Error, Test.Pass))

        results = Test.@testset NoThrowTestSet "Nested expression - single variable - throws" begin
            io = IOBuffer()
            a = 2
            @Test io=io isnothing(sometimes_throws(a^2)) 
            message = String(take!(io))
            @test message == "Test `isnothing(sometimes_throws(a ^ 2))` failed with values:\na = $a\n"
        end
        @test test_results_match(results, (Test.Error, Test.Pass))

        results = Test.@testset NoThrowTestSet "Nested expression - single variable w/ dot - throws" begin
            io = IOBuffer()
            a = (; b=2)
            @Test io=io isnothing(sometimes_throws(a.b)) 
            message = String(take!(io))
            @test message == "Test `isnothing(sometimes_throws(a.b))` failed with values:\na = $a\n"
        end
        @test test_results_match(results, (Test.Error, Test.Pass))

        results = Test.@testset NoThrowTestSet "Nested expression - generator - fails" begin
            io = IOBuffer()
            a = 1:10
            b = -5:-1
            @Test io=io all( ai < 5 for ai in a )
            message = String(take!(io))
            @test message == "Test `all((ai < 5 for ai = a))` failed with values:\na = $a\n"
            @Test io=io all( ai < 5 for ai in vcat(a, b) if mod(ai, 2) == 0)
            message = String(take!(io))
            @test message == "Test `all((ai < 5 for ai = vcat(a, b) if mod(ai, 2) == 0))` failed with values:\na = $a\nb = $b\n"
        end
        @test test_results_match(results, (Test.Fail, Test.Pass, Test.Fail, Test.Pass))

        results = Test.@testset NoThrowTestSet "Nested expression - single variable too long to print fully - throws" begin
            io = TextWidthLimiter(IOBuffer(), 100)
            a = repeat([1], 1000)
            @Test io=io isnothing(sometimes_throws(a[1]^2)) 
            message = String(take!(io))
            @test message == "Test `isnothing(sometimes_throws(a[1] ^ 2))` failed with values:\na = [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, …\n"
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
            @test message == "Test `sometimes_fails(a, g(b))` failed with values:\na = $a\n`g(b)` = $(g(b))\nb = $b\n"
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
            @test message == "Test `a[2] == 3` failed with values:\n`a[2]` = 2\na = $a\n"
        end
        @test test_results_match(results, (Test.Fail, Test.Pass))

        results = Test.@testset NoThrowTestSet "Reference expression - reserved keyword" begin
            io = IOBuffer()
            a = [1, 2, 3]
            @Test io=io a[begin] == 3
            message = String(take!(io))
            @test message == "Test `a[begin] == 3` failed with values:\n`a[begin]` = 1\na = $a\n"
        end
        @test test_results_match(results, (Test.Fail, Test.Pass))

        results = Test.@testset NoThrowTestSet "Nested expression - keyword arguments - fails" begin
            io = IOBuffer()
            x = 1
            y = 2
            @Test io=io multi_input_kwargs(x; y) == 4
            message = String(take!(io))
            @test message == "Test `multi_input_kwargs(x; y) == 4` failed with values:\n`multi_input_kwargs(x; y)` = 2\nx = $x\ny = $y\n"
        end
        @test test_results_match(results, (Test.Fail, Test.Pass))

        results = Test.@testset NoThrowTestSet "Splatting" begin
            a = (1, 2)
            io = IOBuffer()
            @Test io=io multi_valued(a) == (1, 4)
            message = String(take!(io))
            @test isempty(message)

            a = (2, 2)
            @Test io=io multi_valued(a) == (1, 4)
            message = String(take!(io))
            @test message == "Test `multi_valued(a) == (1, 4)` failed with values:\n`multi_valued(a)` = (2, 4)\na = $a\n"

            @Test io=io multi_valued((a,)...) == (1, 4)
            message = String(take!(io))
            @test message == "Test `multi_valued((a,)...) == (1, 4)` failed with values:\n`multi_valued((a,)...)` = (2, 4)\na = $a\n"

            @Test io=io multi_input((a.^2)...) == 5
            message = String(take!(io))
            @test message == "Test `multi_input(a .^ 2...) == 5` failed with values:\n`multi_input(a .^ 2...)` = 8\na = (2, 2)\n"
        end
        @test test_results_match(results, (Test.Pass, Test.Pass, Test.Fail, Test.Pass, Test.Fail, Test.Pass, Test.Fail, Test.Pass))
        
        results = Test.@testset NoThrowTestSet "Generators" begin
            a = 1:10
            io = IOBuffer()
            @Test io=io all(ai > 2 for ai in a if mod(ai,2) == 0)
            message = String(take!(io))
            @test message == "Test `all((ai > 2 for ai = a if mod(ai, 2) == 0))` failed with values:\na = $a\n"
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
            @test message == "Test `sometimes_fails(a, g(b))` failed with values:\na = 1\n`g(b)` = 6\nb = 3\n"
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