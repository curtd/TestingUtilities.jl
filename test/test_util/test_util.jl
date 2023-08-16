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

        c = Ref(0)
        l = ReentrantLock()
        f = ()-> (sleep(0.05); return lock(()->c[] ≥ 2, l))
        g = @async (while c[] ≤ 2; sleep(0.1); lock(()->c[] += 1, l) end)

        timer = TestingUtilities.TaskFinishedTimer(f; max_time=Second(1), sleep_time)
        t = @async fetch(timer)
        @test !istaskdone(t) && !istaskfailed(t)
        sleep(0.1)
        @test istaskdone(t) && !istaskfailed(t)
        @test fetch(t) == false
        sleep(0.8)
        t = @async fetch(timer)
        sleep(0.1)
        @test istaskdone(t) && !istaskfailed(t)
        @test fetch(t) == true

        # Keep running until timed out
        c = Ref(0)
        f = ()-> (sleep(0.01); return lock(()->c[] ≥ 2, l))

        timer = TestingUtilities.TaskFinishedTimer(f; max_time=Millisecond(100), sleep_time=Millisecond(20))
        for i in 1:100
            t = fetch(timer; throw_error=false)
            if isnothing(t)
                @test TestingUtilities.is_timed_out(timer)
                break
            else
                @test t == false
            end
            i == 100 && error("Ran for 100 iterations without timing out")
        end
    end
end