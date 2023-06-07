macro test_throws_compat(ExceptionType, message, expr)
    output = Expr(:block)

    push!(output.args, :(@test_throws $ExceptionType $expr))
    if VERSION ≥ v"1.7"
        push!(output.args, :(@test_throws $message $expr))
    end
    return output |> esc
end
@testset "Macro utilities" begin 
    @test TestingUtilities.unwrap_if_quotenode(:x) == :x 
    @test TestingUtilities.unwrap_if_quotenode(QuoteNode(:x)) == :x 

    @testset "Keyword argument parsing" begin 
        ex = [:(a=1), :(d=A.b), :(c=def), :(b), :(e=:e)]
        kwargs = TestingUtilities.parse_kwarg_expr(ex...)
        @test kwargs == Dict{Symbol, Any}(:a => (; position=1, value=1), :b => (; position=4, value=:b), :c => (; position=3, value=:def), :d => (; position=2, value=:(A.b)), :e => (; position=5, value=QuoteNode(:e)))
        @test_throws_compat ErrorException "Argument f(a) must be a Symbol, QuoteNode, or Assignment expression" TestingUtilities.parse_kwarg_expr(:(f(a)))
       
        @test_throws_compat ErrorException "In expression f(a) = b, key f(a) must be a QuoteNode or a Symbol, got typeof(key) = Expr" TestingUtilities.parse_kwarg_expr(Expr(:(=), :(f(a)), :b))
    
        @test TestingUtilities.fetch_kwarg_expr(kwargs; key=:a, expected_type=[Int,QuoteNode]) == 1
        @test TestingUtilities.fetch_kwarg_expr(kwargs; arg_position=1, expected_type=[Int,QuoteNode]) == 1
        @test TestingUtilities.fetch_kwarg_expr(kwargs; key=:b, expected_type=[Symbol]) == :b
        @test TestingUtilities.fetch_kwarg_expr(kwargs; arg_position=4, expected_type=[Symbol]) == :b
        @test TestingUtilities.fetch_kwarg_expr(kwargs; arg_position=3, key=:c, expected_type=[Symbol]) == :def
        @test TestingUtilities.fetch_kwarg_expr(kwargs; key=:c, expected_type=[Symbol]) == :def
        
    
        @test TestingUtilities.fetch_kwarg_expr(kwargs; arg_position=1, expected_type=[Int,QuoteNode]) == 1
        @test_throws ErrorException TestingUtilities.fetch_kwarg_expr(kwargs; expected_type=[Int,Symbol,QuoteNode])
        @test_throws ArgumentError TestingUtilities.fetch_kwarg_expr(kwargs; arg_position=10, expected_type=[Int,Symbol,QuoteNode])
        @test_throws ArgumentError TestingUtilities.fetch_kwarg_expr(kwargs; key=:f, expected_type=[Int,QuoteNode]) 
        @test TestingUtilities.fetch_kwarg_expr(kwargs; key=:f, default_value=10, expected_type=[Int,QuoteNode]) == 10
        @test_throws_compat ArgumentError "key (= f) = value (= abc) must be one of DataType[Int64, QuoteNode], got typeof(value) = String" TestingUtilities.fetch_kwarg_expr(kwargs; key=:f, default_value="abc", expected_type=[Int,QuoteNode])
        @test_throws_compat ArgumentError "key (= f) not found in keys(kwargs)" TestingUtilities.fetch_kwarg_expr(kwargs; key=:f, default_value=nothing, expected_type=[Int,QuoteNode])
        @test TestingUtilities.fetch_kwarg_expr(kwargs; key=:f, default_value=nothing, expected_type=[Int,QuoteNode, Nothing]) |> isnothing
    end
    @testset "show_value" begin 
        io = IOBuffer()
        k = :var
        v = 1
        TestingUtilities.show_value(v; io)
        @test String(take!(io)) == "1\n"
        TestingUtilities.show_value(k, v; io)
        @test String(take!(io)) == "var = 1\n"

        k = Expr(:call, :f, :x)
        TestingUtilities.show_value(k, v; io)
        @test String(take!(io)) == "`f(x)` = 1\n"
    end
    @testset "show_diff" begin 
        io = IOBuffer()
        test_data = [
            (; expected = "", result = "", output = "expected = \"\"\nresult   = \"\"\n"),
            (; expected = "abc", result = "", output = "expected = \"abc\"\nresult   = \"\"\n"),
            (; expected = "abc", result = "ab", output = "expected = \"abc\"\nresult   = \"ab\"\n"),
            (; expected = "ab\nc", result = "ab", output = "expected = \"ab\\nc\"\nresult   = \"ab\"\n"),
            (; expected = "ab\nc", result = "ab\n", output = "expected = \"ab\\nc\"\nresult   = \"ab\\n\"\n"),
        ]
        for data in test_data 
            expected = data.expected 
            result = data.result
            output = data.output
            TestingUtilities.show_diff(expected, result; io)
            @test String(take!(io)) == output
        end
        TestingUtilities.set_show_diff_styles(; matching=:color => :green, differing=:color => :red)
        buf = IOBuffer()
        io = IOContext(buf, :color => true)
        test_data = [
            (; expected = "", result = "", output = "expected = \"\"\nresult   = \"\"\n"),
            (; expected = "abc", result = "", output = "expected = \"\e[31mabc\e[39m\"\nresult   = \"\"\n"),
            (; expected = "abc", result = "ab", output = "expected = \"\e[32mab\e[39m\e[31mc\e[39m\"\nresult   = \"\e[32mab\e[39m\"\n"),
            (; expected = "ab\nc", result = "ab", output = "expected = \"\e[32mab\e[39m\e[31m\\nc\e[39m\"\nresult   = \"\e[32mab\e[39m\"\n"),
            (; expected = "ab\nc", result = "ab\n", output = "expected = \"\e[32mab\\n\e[39m\e[31mc\e[39m\"\nresult   = \"\e[32mab\\n\e[39m\"\n"),
        ]
        for data in test_data 
            expected = data.expected 
            result = data.result
            output = data.output
            TestingUtilities.show_diff(expected, result; io)
            @test String(take!(buf)) == output
        end
        TestingUtilities.set_show_diff_styles(; matching=:bold => true, differing=:underline => true)
        TestingUtilities.show_diff("abcd", "abef"; io)
        @test String(take!(buf)) == "expected = \"\e[0m\e[1mab\e[22m\e[0m\e[4mcd\e[24m\"\nresult   = \"\e[0m\e[1mab\e[22m\e[0m\e[4mef\e[24m\"\n"
    end
end