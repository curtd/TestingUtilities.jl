macro test_throws_compat(ExceptionType, message, expr)
    output = Expr(:block)

    push!(output.args, :(@test_throws $ExceptionType $expr))
    if VERSION ≥ v"1.7"
        push!(output.args, :(@test_throws $message $expr))
    end
    return output |> esc
end

# Ensure consistent type printing for DateTime type, in interactive mode or in package tests 
PrettyTables.compact_type_str(::Type{DateTime}) = "DateTime"

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
        @testset "Generic value" begin 
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
        if run_df_tests
            @testset "DataFrame" begin 
                io = IOBuffer()
                df = DataFrame( (Symbol("a$i") => (i:i+10) for i in 1:10)... )
                TestingUtilities.show_value(df; io, max_num_rows_cols=(1,1), keyword_to_ignore=:abcd)
                s = String(take!(io))
                ref_str = """
                ┌───────┬───┐
                │    a1 │ … │
                │ Int64 │   │
                ├───────┼───┤
                │     1 │ ⋯ │
                │     ⋮ │   │
                └───────┴───┘
                """
                @test isequal(s, ref_str)
                TestingUtilities.show_value(df; io, max_num_rows_cols=(1,1), keyword_to_ignore=:abcd, alignment=:l)
                s = String(take!(io))
                ref_str = """
                ┌───────┬───┐
                │ a1    │ … │
                │ Int64 │   │
                ├───────┼───┤
                │ 1     │ ⋯ │
                │ ⋮     │   │
                └───────┴───┘
                """
                @test isequal(s, ref_str)
                TestingUtilities.show_value(df; io, max_num_rows_cols=(3,1))
                s = String(take!(io))
                ref_str = """
                ┌───────┬───┐
                │    a1 │ … │
                │ Int64 │   │
                ├───────┼───┤
                │     1 │ ⋯ │
                │     2 │   │
                │     3 │   │
                │     ⋮ │   │
                └───────┴───┘
                """
                @test isequal(s, ref_str)
                TestingUtilities.show_value(df; io, max_num_rows_cols=(1, 3))
                s = String(take!(io))
                ref_str = """
                ┌───────┬───────┬───────┬───┐
                │    a1 │    a2 │    a3 │ … │
                │ Int64 │ Int64 │ Int64 │   │
                ├───────┼───────┼───────┼───┤
                │     1 │     2 │     3 │ ⋯ │
                │     ⋮ │     ⋮ │     ⋮ │   │
                └───────┴───────┴───────┴───┘
                """
                @test isequal(s, ref_str)
                TestingUtilities.show_value(df; io, max_num_rows_cols=(4, 3))
                s = String(take!(io))
                ref_str = """
                ┌───────┬───────┬───────┬───┐
                │    a1 │    a2 │    a3 │ … │
                │ Int64 │ Int64 │ Int64 │   │
                ├───────┼───────┼───────┼───┤
                │     1 │     2 │     3 │ ⋯ │
                │     2 │     3 │     4 │   │
                │     3 │     4 │     5 │   │
                │     4 │     5 │     6 │   │
                │     ⋮ │     ⋮ │     ⋮ │   │
                └───────┴───────┴───────┴───┘
                """
                @test isequal(s, ref_str)

                TestingUtilities.show_value(Ref(df); io, max_num_rows_cols=(1,1))
                s = String(take!(io))
                ref_str = """
                Ref(
                ┌───────┬───┐
                │    a1 │ … │
                │ Int64 │   │
                ├───────┼───┤
                │     1 │ ⋯ │
                │     ⋮ │   │
                └───────┴───┘
                )
                """
                @test isequal(s, ref_str)
                TestingUtilities.show_value(Ref(df); io, max_num_rows_cols=(2,3))
                s = String(take!(io))
                ref_str = """
                Ref(
                ┌───────┬───────┬───────┬───┐
                │    a1 │    a2 │    a3 │ … │
                │ Int64 │ Int64 │ Int64 │   │
                ├───────┼───────┼───────┼───┤
                │     1 │     2 │     3 │ ⋯ │
                │     2 │     3 │     4 │   │
                │     ⋮ │     ⋮ │     ⋮ │   │
                └───────┴───────┴───────┴───┘
                )
                """
                @test isequal(s, ref_str)
            end
        end
    end
    @testset "common_prefix" begin 
        test_data = [
            (; a = "", b = "", result = ""),
            (; a = "", b = "ab", result = ""),
            (; a = "a", b = "ab", result = "a"),
            (; a = "abc", b = "ab", result = "ab"),
            (; a = "abαβγdefc", b = "ab", result = "ab"),
        ]
        for data in test_data
            a, b, result = data.a, data.b, data.result
            @test TestingUtilities.common_prefix(a,b)[1] == result
        end
    end
    @testset "show_diff" begin 
        @testset "Strings" begin 
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
                expected, result, output = data.expected, data.result, data.output
                TestingUtilities.show_diff(expected, result; io)
                @test String(take!(buf)) == output
            end
            if VERSION ≥ v"1.7"
                TestingUtilities.set_show_diff_styles(; matching=:bold => true, differing=:underline => true)
                TestingUtilities.show_diff("abcd", "abef"; io)
                @test String(take!(buf)) == "expected = \"\e[0m\e[1mab\e[22m\e[0m\e[4mcd\e[24m\"\nresult   = \"\e[0m\e[1mab\e[22m\e[0m\e[4mef\e[24m\"\n"
            end
        end
        if run_df_tests
            @testset "DataFrames" begin 
                @testset "show_diff" begin 
                    max_num_rows_cols=(100,100)
                    # Differing propertynames 
                    io = IOBuffer()
                    reason_header = "Reason: `propertynames(expected) != propertynames(result)`"
                    test_data = [
                        (; expected = DataFrame(:a => [1]), result = DataFrame(:b => [1]), output_nocolour = "$reason_header\n`propertynames(expected)` = {:a}\n`propertynames(result)`   = {:b}\n", output_colour = "$reason_header\n`propertynames(expected)` = {\e[31m:a\e[39m}\n`propertynames(result)`   = {\e[31m:b\e[39m}\n"), 
                        (; expected = DataFrame(:a => [1], :c => [1]), result = DataFrame(:b => [1], :c => [2]), output_nocolour = "$reason_header\n`propertynames(expected)` = {:c, :a}\n`propertynames(result)`   = {:c, :b}\n", output_colour = "$reason_header\n`propertynames(expected)` = {\e[32m:c\e[39m, \e[31m:a\e[39m}\n`propertynames(result)`   = {\e[32m:c\e[39m, \e[31m:b\e[39m}\n"), 
                        (; expected = DataFrame(:a => [1], :c => [1]), result = DataFrame(:b => [1], :c => [2], :d => [1]), output_nocolour = "$reason_header\n`propertynames(expected)` = {:c, :a}\n`propertynames(result)`   = {:c, :b, :d}\n", output_colour = "$reason_header\n`propertynames(expected)` = {\e[32m:c\e[39m, \e[31m:a\e[39m}\n`propertynames(result)`   = {\e[32m:c\e[39m, \e[31m:b, :d\e[39m}\n")
                    ]
                    for data in test_data    
                        expected, result, output_nocolour = data.expected, data.result, data.output_nocolour
                        @test TestingUtilities.show_diff(expected, result; io, max_num_rows_cols)
                        @test String(take!(io)) == output_nocolour
                    end
                
                    TestingUtilities.set_show_diff_styles(; matching=:color => :green, differing=:color => :red)
                    buf = IOBuffer()
                    io = IOContext(buf, :color => true)

                    for data in test_data    
                        expected, result, output_colour = data.expected, data.result, data.output_colour
                        @test TestingUtilities.show_diff(expected, result; io, max_num_rows_cols)
                        @test String(take!(buf)) == output_colour
                    end
                    
                    # Same propertynames, differing rows 
                    io_noc = IOBuffer()
                    buf = IOBuffer()
                    io_c = IOContext(buf, :color => true)

                    expected = DataFrame(:a => [1,2])
                    result = DataFrame(:a => [1])
                    reason_header = "Reason: `nrow(expected) != nrow(result)`"
                    output_nocolour = "$reason_header\n`nrow(expected)` = 2\n`nrow(result)`   = 1\n"
                    output_colour = "$reason_header\n`nrow(expected)` = 2\n`nrow(result)`   = 1\n"
                    @test TestingUtilities.show_diff(expected, result; io=io_noc, max_num_rows_cols)
                    @test String(take!(io_noc)) == output_nocolour
                    @test TestingUtilities.show_diff(expected, result; io=io_c, max_num_rows_cols)
                    @test String(take!(buf)) == output_colour

                    expected = DataFrame(:a => [1, 2], :c => [DateTime(2023, 1, 1), DateTime(2023, 1, 2)])
                    result = DataFrame(:a => [1, 2], :c => [DateTime(2023, 1, 1), DateTime(2023, 1, 1)])
                    reason_header = "Reason: Mismatched values"
                    datetime_type_str = string(DateTime)

                    output_nocolour = "$reason_header\n┌───────────────────┬──────────┬───────┬─────────────────────┐\n│           row_num │       df │     a │                   c │\n│ U{Nothing, Int64} │   String │ Int64 │            DateTime │\n├───────────────────┼──────────┼───────┼─────────────────────┤\n│                 2 │ expected │     2 │ 2023-01-02T00:00:00 │\n│                   │   result │     2 │ 2023-01-01T00:00:00 │\n└───────────────────┴──────────┴───────┴─────────────────────┘\n"
                    output_colour = "$reason_header\n┌───────────────────┬──────────┬───────┬─────────────────────┐\n│\e[1m           row_num \e[0m│\e[1m       df \e[0m│\e[1m     a \e[0m│\e[1m                   c \e[0m│\n│\e[90m U{Nothing, Int64} \e[0m│\e[90m   String \e[0m│\e[90m Int64 \e[0m│\e[90m            DateTime \e[0m│\n├───────────────────┼──────────┼───────┼─────────────────────┤\n│                 2 │ expected │\e[32m     2 \e[0m│\e[31m 2023-01-02T00:00:00 \e[0m│\n│                   │   result │\e[32m     2 \e[0m│\e[31m 2023-01-01T00:00:00 \e[0m│\n└───────────────────┴──────────┴───────┴─────────────────────┘\n"

                    @test TestingUtilities.show_diff(expected, result; io=io_noc, max_num_rows_cols)
                    @Test String(take!(io_noc)) == output_nocolour
                    @test TestingUtilities.show_diff(expected, result; io=io_c, max_num_rows_cols)
                    @Test String(take!(buf)) == output_colour
                end
            end
        end
        @testset "Generic structs" begin 
            expected_1_1 = ShowDiffChild1_1("abc", 1)
            result_1_1 = ShowDiffChild1_1("ab", 1)
            io = IOBuffer()
            TestingUtilities.show_diff(expected_1_1, result_1_1; io=io)
            message = String(take!(io))
            ref_message = """
            expected::$ShowDiffChild1_1 = $(expected_1_1)
              result::$ShowDiffChild1_1 = $(result_1_1)

            expected.x::String = "abc"
              result.x::String = "ab"
            """
            @test message == ref_message
            
            expected_1_1 = ShowDiffChild1_1("abc", 2)
            result_1_1 = ShowDiffChild1_1("ab", 1)
            TestingUtilities.show_diff(expected_1_1, result_1_1; io=io)
            message = String(take!(io))
            ref_message = """
            expected::$ShowDiffChild1_1 = $(expected_1_1)
              result::$ShowDiffChild1_1 = $(result_1_1)

            expected.x::String = "abc"
              result.x::String = "ab"

            expected.y::Int64 = 2
              result.y::Int64 = 1
            """
            @test message == ref_message

            expected_1 = ShowDiffChild1(expected_1_1, Dict{String, Any}())
            result_1 = ShowDiffChild1(result_1_1, Dict{String, Any}())
            TestingUtilities.show_diff(expected_1, result_1; io=io)
            message = String(take!(io))
            ref_message = """
            expected::$ShowDiffChild1 = $(expected_1)
              result::$ShowDiffChild1 = $(result_1)

            expected.key1::$ShowDiffChild1_1 = $(expected_1.key1)
              result.key1::$ShowDiffChild1_1 = $(result_1.key1)

            expected.key1.x::String = "abc"
              result.key1.x::String = "ab"

            expected.key1.y::Int64 = 2
              result.key1.y::Int64 = 1
            """
            @test message == ref_message

            expected_1 = ShowDiffChild1(expected_1_1, Dict{String, Any}("b" => 1))
            result_1 = ShowDiffChild1(result_1_1, Dict{String, Any}("z" => 0))
            TestingUtilities.show_diff(expected_1, result_1; io=io)
            message = String(take!(io))
            ref_message = """
            expected::$ShowDiffChild1 = $(expected_1)
              result::$ShowDiffChild1 = $(result_1)

            expected.key1::$ShowDiffChild1_1 = $(expected_1.key1)
              result.key1::$ShowDiffChild1_1 = $(result_1.key1)

            expected.key1.x::String = "abc"
              result.key1.x::String = "ab"

            expected.key1.y::Int64 = 2
              result.key1.y::Int64 = 1
            
            expected.key2::Dict{String, Any} = $(expected_1.key2)
              result.key2::Dict{String, Any} = $(result_1.key2)
            """
            @test message == ref_message

        end
        @testset "Generic values" begin 
            expected_1_1 = ShowDiffChild1_1("abc", 1)
            io = IOBuffer()
            TestingUtilities.show_diff(expected_1_1, 10; io=io)
            message = String(take!(io))
            @test message == "Reason: Mismatched type categories\nexpected::$ShowDiffChild1_1 is a Struct, but result::$Int is a generic value\n"
        
            TestingUtilities.show_diff(Int, String; io=io)
            message = String(take!(io))
            @test message == "expected = $Int\nresult = $String\n"
        end
    end
end

@testset "Misc utilities" begin 
    @testset "TaskFinishedTimer" begin 
        done = Ref(false)
        cb = ()->(while !done[] sleep(0.1) end; 1)
        max_time = Millisecond(100)
        sleep_time = Millisecond(1)
        timer = TestingUtilities.TaskFinishedTimer(cb; max_time, sleep_time)
        f = @async fetch(timer)
        sleep(0.5)
        @test_throws TaskFailedException fetch(f)
        if VERSION ≥ v"1.7"
            @test current_exceptions(f)[1].exception isa TaskTimedOutException
        else 
            @test Base.catch_stack(f)[1][1] isa TaskTimedOutException
        end
        max_time = Millisecond(1000)
        sleep_time = Millisecond(1)
        timer = TestingUtilities.TaskFinishedTimer(cb; max_time, sleep_time)
        f = @async fetch(timer)
        sleep(0.05)
        done[] = true
        sleep(0.25)
        @test istaskdone(f) && !istaskfailed(f)
        @test fetch(f) == 1

        # Task will fail before timer fails
        done = Ref(false)
        cb = ()->(local a = 0; while !done[] sleep(0.1); a += 1; a ≥ 3 && error("Failed"); end)
        timer = TestingUtilities.TaskFinishedTimer(cb; max_time, sleep_time)
        f = @async fetch(timer)
        @test !istaskdone(f) && !istaskfailed(f)
        sleep(0.5)
        @test_throws TaskFailedException fetch(f)
    end
end