remove_quoting(expr::Expr) = Meta.isexpr(expr, :$) ? remove_quoting(expr.args[1]) : expr
remove_quoting(expr) = expr

@testset "@test_cases" begin 
    @testset "Util" begin 
        @test TestingUtilities.parse_table(:(a | b)) == [:a, :b]
        @test TestingUtilities.parse_table(:(a | b | c)) == [:a, :b, :c]
        @test TestingUtilities.parse_table(:(a | b | c); is_header=true) == [:a, :b, :c]
        @test TestingUtilities.parse_table(:(a | (b, _ = val) | c); is_header=true) == [:a, (:b, :_ => :val), :c]
        @test_throws ErrorException TestingUtilities.parse_table(:(a | (b = d, _ = val) | c); is_header=true)
    end

    results = Test.@testset NoThrowTestSet "Failing Tests" begin 
        io = IOBuffer()
        @test_cases io=io begin 
            a | b | output 
            1 | 2 | 3
            1 | 2 | 4
            0 | 0 | 1
            @test a + b == output
        end
        message = String(take!(io))
        @test message == "Test `a + b == output` failed with values:\n------\n`a + b` = 3\noutput = 4\na = 1\nb = 2\n------\n`a + b` = 0\noutput = 1\na = 0\nb = 0\n"
    end
    @test test_results_match(results, (Test.Pass, Test.Fail, Test.Fail, Test.Pass))

    results = Test.@testset NoThrowTestSet "Failing Tests - alternate syntax" begin 
        io = IOBuffer()
        @test_cases io=io begin 
            a | b | output 
            a => 1 , b => 2, output => 3
            a => 1 , 
            b => 2 ,
            output => 4
            0 | 0 | 1
            @test a + b == output
        end
        message = String(take!(io))
        @test message == "Test `a + b == output` failed with values:\n------\n`a + b` = 3\noutput = 4\na = 1\nb = 2\n------\n`a + b` = 0\noutput = 1\na = 0\nb = 0\n"
    end
    @test test_results_match(results, (Test.Pass, Test.Fail, Test.Fail, Test.Pass))

    results = Test.@testset NoThrowTestSet "Failing Tests - alternate key=value syntax" begin 
        io = IOBuffer()
        @test_cases io=io begin 
            a | b | output 
            (a = 1, b = 2, output = 3)
            (a = 1, b = 2, output = 4)
            (a = 0, b = 0, output = 1)
            @test a + b == output
        end
        message = String(take!(io))
        @test message == "Test `a + b == output` failed with values:\n------\n`a + b` = 3\noutput = 4\na = 1\nb = 2\n------\n`a + b` = 0\noutput = 1\na = 0\nb = 0\n"
    end
    @test test_results_match(results, (Test.Pass, Test.Fail, Test.Fail, Test.Pass))

    results = Test.@testset NoThrowTestSet "Failing Tests - default values" begin 
        io = IOBuffer()
        @test_cases io=io begin 
            a | (b, _ = 2) | output 
            1 | _ | 3
            1 | _ | 4
            0 | 0 | 1
            @test a + b == output
        end
        message = String(take!(io))
        @test message == "Test `a + b == output` failed with values:\n------\n`a + b` = 3\noutput = 4\na = 1\nb = 2\n------\n`a + b` = 0\noutput = 1\na = 0\nb = 0\n"
    end
    @test test_results_match(results, (Test.Pass, Test.Fail, Test.Fail, Test.Pass))

    results = Test.@testset NoThrowTestSet "Failing Tests - In values, refer to previously defined name" begin 
        io = IOBuffer()
        @test_cases io=io begin 
            a | b | output 
            (a = 1, b = 2, output = b^2)
            (a = 1, b = 2, output = b^2)
            (a = 0, b = 0, output = b^2)
            @test a + b == output
        end
        message = String(take!(io))
        @test message == "Test `a + b == output` failed with values:\n------\n`a + b` = 3\noutput = 4\na = 1\nb = 2\n------\n`a + b` = 3\noutput = 4\na = 1\nb = 2\n"
    end
    @test test_results_match(results, (Test.Fail, Test.Fail, Test.Pass, Test.Pass))

    results = Test.@testset NoThrowTestSet "Multiple Simultaneous Tests" begin 
        io = IOBuffer()
        @test_cases io=io begin 
            a | b | y
            1 | 2 | 3
            1 | 2 | 4
            0 | 0 | 1
            @test a + b == y 
            @test b^2 + 1 == y
        end
        message = String(take!(io))
        @test message == "Test `a + b == y` failed with values:\n------\n`a + b` = 3\ny = 4\na = 1\nb = 2\n------\n`a + b` = 0\ny = 1\na = 0\nb = 0\nTest `b ^ 2 + 1 == y` failed with values:\n------\n`b ^ 2 + 1` = 5\ny = 3\na = 1\nb = 2\n------\n`b ^ 2 + 1` = 5\ny = 4\na = 1\nb = 2\n"
    end
    @test test_results_match(results, (Test.Pass, Test.Fail, Test.Fail, Test.Fail, Test.Fail, Test.Pass, Test.Pass))

    results = Test.@testset NoThrowTestSet "Multiple Simultaneous Tests w/ Erroring" begin 
        io = IOBuffer()
        @test_cases io=io begin 
            a | b | y
            1 | 2 | 3
            1 | 2 | 4
            0 | 0 | 1
            @test a + b == y 
            @test error(string(y))
        end
        message = String(take!(io))
        @test message == "Test `a + b == y` failed with values:\n------\n`a + b` = 3\ny = 4\na = 1\nb = 2\n------\n`a + b` = 0\ny = 1\na = 0\nb = 0\nTest `error(string(y))` failed with values:\n------\n`string(y)` = \"3\"\na = 1\nb = 2\ny = 3\n------\n`string(y)` = \"4\"\na = 1\nb = 2\ny = 4\n------\n`string(y)` = \"1\"\na = 0\nb = 0\ny = 1\n"
    end
    @test test_results_match(results, (Test.Pass, Test.Error, Test.Fail, Test.Error, Test.Fail, Test.Error, Test.Pass))

    results = Test.@testset NoThrowTestSet "Error in test data" begin 
        io = IOBuffer()
        @test_cases io=io begin 
            a | b | output 
            1 | 2 | 3
            2 | 2 | error("asdf")
            @test a + b == output
        end
    end
    @test test_results_match(results, (Test.Error,))
    @test results[1].value == "ErrorException(\"asdf\")"
    
end