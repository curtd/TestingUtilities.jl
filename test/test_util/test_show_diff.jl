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

                output_nocolour = """$reason_header
                ┌───────────────────┬──────────┬───────┬─────────────────────┐
                │           row_num │       df │     a │                   c │
                │ U{Nothing, Int64} │   String │ Int64 │            DateTime │
                ├───────────────────┼──────────┼───────┼─────────────────────┤
                │                 2 │ expected │     2 │ 2023-01-02T00:00:00 │
                │                   │   result │     2 │ 2023-01-01T00:00:00 │
                └───────────────────┴──────────┴───────┴─────────────────────┘\n"""
                
                output_colour = "$reason_header\n┌───────────────────┬──────────┬───────┬─────────────────────┐\n│\e[1m           row_num \e[0m│\e[1m       df \e[0m│\e[1m     a \e[0m│\e[1m                   c \e[0m│\n│\e[90m U{Nothing, Int64} \e[0m│\e[90m   String \e[0m│\e[90m Int64 \e[0m│\e[90m            DateTime \e[0m│\n├───────────────────┼──────────┼───────┼─────────────────────┤\n│                 2 │ expected │\e[32m     2 \e[0m│\e[31m 2023-01-02T00:00:00 \e[0m│\n│                   │   result │\e[32m     2 \e[0m│\e[31m 2023-01-01T00:00:00 \e[0m│\n└───────────────────┴──────────┴───────┴─────────────────────┘\n"

                @test TestingUtilities.show_diff(expected, result; io=io_noc, max_num_rows_cols)
                @Test String(take!(io_noc)) == output_nocolour
                @test TestingUtilities.show_diff(expected, result; io=io_c, max_num_rows_cols)
                @Test String(take!(buf)) == output_colour

                output_nocolour = """$reason_header
                ┌───────────────────┬──────────┬─────────────────────┐
                │           row_num │       df │                   c │
                │ U{Nothing, Int64} │   String │            DateTime │
                ├───────────────────┼──────────┼─────────────────────┤
                │                 2 │ expected │ 2023-01-02T00:00:00 │
                │                   │   result │ 2023-01-01T00:00:00 │
                └───────────────────┴──────────┴─────────────────────┘\n"""

                @test TestingUtilities.show_diff(expected, result; io=io_noc, max_num_rows_cols, differing_cols_only=true)
                @Test String(take!(io_noc)) == output_nocolour

                expected = DataFrame(:a => [1, 2, 4], :c => [DateTime(2023, 1, 1), DateTime(2023, 1, 2), DateTime(2023, 1, 3)])
                result = DataFrame(:a => [1, 2, 3], :c => [DateTime(2023, 1, 1), DateTime(2023, 1, 1), DateTime(2023, 1, 3)])

                output_nocolour = """$reason_header
                ┌───────────────────┬──────────┬─────────────────────┐
                │           row_num │       df │                   c │
                │ U{Nothing, Int64} │   String │            DateTime │
                ├───────────────────┼──────────┼─────────────────────┤
                │                 2 │ expected │ 2023-01-02T00:00:00 │
                │                   │   result │ 2023-01-01T00:00:00 │
                └───────────────────┴──────────┴─────────────────────┘
                ┌───────────────────┬──────────┬───────┐
                │           row_num │       df │     a │
                │ U{Nothing, Int64} │   String │ Int64 │
                ├───────────────────┼──────────┼───────┤
                │                 3 │ expected │     4 │
                │                   │   result │     3 │
                └───────────────────┴──────────┴───────┘\n"""
                @test TestingUtilities.show_diff(expected, result; io=io_noc, max_num_rows_cols, differing_cols_only=true)
                @Test String(take!(io_noc)) == output_nocolour
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

        # Don't recurse into Date/Time/Period types
        for (expected, result) in [(Date(2023, 1, 1), Date(2023, 1, 2)), (DateTime(2023, 1, 1), DateTime(2023, 1, 2)), (Time(9, 30), Time(9, 31)), (Second(1), Second(2))]
            io = IOBuffer()
            TestingUtilities.show_diff(expected, result; io=io)
            message = String(take!(io))
            T = typeof(expected)
            ref_message = """
            expected::$(T) = $(repr(expected))
              result::$(T) = $(repr(result))
            """
            @test message == ref_message
        end
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