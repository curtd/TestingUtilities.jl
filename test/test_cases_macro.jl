append_char(x, c; n::Int) = x * repeat(c, n)

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
        @test message == "Test `a + b == output` failed:\nValues:\n------\n`a + b` = 3\noutput = 4\na = 1\nb = 2\n------\n`a + b` = 0\noutput = 1\na = 0\nb = 0\n"
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
        @test message == "Test `a + b == output` failed:\nValues:\n------\n`a + b` = 3\noutput = 4\na = 1\nb = 2\n------\n`a + b` = 0\noutput = 1\na = 0\nb = 0\n"
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
        @test message == "Test `a + b == output` failed:\nValues:\n------\n`a + b` = 3\noutput = 4\na = 1\nb = 2\n------\n`a + b` = 0\noutput = 1\na = 0\nb = 0\n"
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
        @test message == "Test `a + b == output` failed:\nValues:\n------\n`a + b` = 3\noutput = 4\na = 1\nb = 2\n------\n`a + b` = 0\noutput = 1\na = 0\nb = 0\n"
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
        @test message == "Test `a + b == output` failed:\nValues:\n------\n`a + b` = 3\noutput = 4\na = 1\nb = 2\n------\n`a + b` = 3\noutput = 4\na = 1\nb = 2\n"
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
        @test message == "Test `a + b == y` failed:\nValues:\n------\n`a + b` = 3\ny = 4\na = 1\nb = 2\n------\n`a + b` = 0\ny = 1\na = 0\nb = 0\nTest `b ^ 2 + 1 == y` failed:\nValues:\n------\n`b ^ 2 + 1` = 5\ny = 3\na = 1\nb = 2\n------\n`b ^ 2 + 1` = 5\ny = 4\na = 1\nb = 2\n"
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
        @test message == "Test `a + b == y` failed:\nValues:\n------\n`a + b` = 3\ny = 4\na = 1\nb = 2\n------\n`a + b` = 0\ny = 1\na = 0\nb = 0\nTest `error(string(y))` failed:\nValues:\n------\n`string(y)` = \"3\"\na = 1\nb = 2\ny = 3\n------\n`string(y)` = \"4\"\na = 1\nb = 2\ny = 4\n------\n`string(y)` = \"1\"\na = 0\nb = 0\ny = 1\n"
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
    
    results = Test.@testset NoThrowTestSet "String comparison" begin 
        io = IOBuffer()
        @test_cases io=io begin 
            a     | b   | output 
            "abc" | 'd' | "abcd"
            "abc" | 'e' | "abce"
            @test append_char(a, b; n=3) == output
        end
        message = String(take!(io))
        ref_message = """Test `append_char(a, b; n = 3) == output` failed:
        Values:
        ------
        `append_char(a, b; n = 3)` = "abcddd"
        output                     = "abcd"
        a = "abc"
        b = 'd'
        ------
        `append_char(a, b; n = 3)` = "abceee"
        output                     = "abce"
        a = "abc"
        b = 'e'
        """
        @test message == ref_message
    end
    @test test_results_match(results, (Test.Fail, Test.Fail, Test.Pass))

    results = Test.@testset NoThrowTestSet "BlockExpr tests" begin 
        io = IOBuffer()
        @test_cases io=io begin 
            a | b | output 
            0 | 1 | 2
            1 | 1 | 3
            begin 
                c = a^2 
                @test b + c == output
                d = c
                @test b^2 == d
            end
        end
        message = String(take!(io))
        ref_message = """Test `b + c == output` failed:\nValues:\n------\n`b + c` = 1\noutput = 2\na = 0\nb = 1\n------\n`b + c` = 2\noutput = 3\na = 1\nb = 1\nTest `b ^ 2 == d` failed:\nValues:\n------\n`b ^ 2` = 1\nd = 0\na = 0\nb = 1\noutput = 2\n"""
        @test message == ref_message
    end

    @test test_results_match(results, (Test.Fail, Test.Fail, Test.Fail, Test.Pass, Test.Pass))

    results = Test.@testset NoThrowTestSet "Test data - generator expression" begin 
        io = IOBuffer()
        @test_cases io=io begin 
            a | b | output 
            0 | 1 | 2
            (a | b | b^2 for a in 1:1, b in 0:1)
            ((a, b, b^2) for a in 1:1, b in 0:1)
            begin 
                d = a
                @test b^2 == d
            end
        end
        message = String(take!(io))
        ref_message = """Test `b ^ 2 == d` failed:\nValues:\n------\n`b ^ 2` = 1\nd = 0\na = 0\nb = 1\noutput = 2\n------\n`b ^ 2` = 0\nd = 1\na = 1\nb = 0\noutput = 0\n------\n`b ^ 2` = 0\nd = 1\na = 1\nb = 0\noutput = 0\n"""
        @test message == ref_message
    end

    @test test_results_match(results, (Test.Fail, Test.Fail, Test.Pass, Test.Fail, Test.Pass, Test.Pass))

end