@testset "@test_eventually" begin 
    @testset "Util" begin 
        test_data = [
            (; input=:(1s), output=:(Dates.Second(1))),
            (; input=:(1ms), output=:(Dates.Millisecond(1))),
            (; input=:(2s), output=:(Dates.Second(2))),
            (; input=:(1m), output=:(Dates.Minute(1))),
            (; input=:(1h), output=:(Dates.Hour(1))),
            (; input=:(3h), output=:(Dates.Hour(3))),
            (; input=:(1d), output=:(Dates.Day(1))),
            (; input=:(1w), output=:(Dates.Week(1))),
            (; input=:(1month), output=:(Dates.Month(1))),
            (; input=:(1y), output=:(Dates.Year(1))),
        ]
        for data in test_data 
            input = data.input 
            output = data.output
            @test TestingUtilities.parse_shorthand_duration(input) == output
        end
    end
    # Returns the same results as @Test for immediately returning test values
    results = Test.@testset NoThrowTestSet "Comparison" begin 
        io = IOBuffer()
        a = 1
        @test_eventually io=io sleep=10ms timeout=Millisecond(100) a == 2 
        message = String(take!(io))
        @test message == "Test `a == 2` failed:\nValues:\na = $a\n"

        b = Ref(false)
        @Test io=io b[]
        message = String(take!(io))
        @test message == "Test `b[]` failed:\nValues:\nb[] = $(b[])\n"
    end
    @test test_results_match(results, (Test.Fail, Test.Pass, Test.Fail, Test.Pass))

    results = Test.@testset NoThrowTestSet "Timed out tests" begin 
        io = IOBuffer()
        done = Ref(false)
        f = (done)->(while !done[]; sleep(0.1) end; true)
        
        # Function never returns
        @test_eventually io=io sleep=Millisecond(10) timeout=100ms f(done)

        message = String(take!(io))
        @test message == "Test `f(done)` failed:\nReason: Test took longer than 100 milliseconds to pass\nValues:\ndone[] = $(done[])\n"

        @test_eventually io=io sleep=1s timeout=1s f(done)
        message = String(take!(io))
        @test message == "Test `f(done)` failed:\nReason: Test took longer than 1000 milliseconds to pass\nValues:\ndone[] = $(done[])\n"

        # Function returns within time limit and test passes
        done = Ref(false)
        f = (done)->(while !done[]; sleep(0.1) end; true)
        g = @async (sleep(0.3); done[] = true)
        @test_eventually io=io sleep=10ms timeout=1s f(done)

        # Function returns within time limit + test fails
        done = Ref(false)
        f = (done)->(while !done[]; sleep(0.1) end; false)
        g = @async (sleep(0.3); done[] = true)
        @test_eventually io=io sleep=Millisecond(10) timeout=Millisecond(1000) f(done)

        message = String(take!(io))

        @test message == "Test `f(done)` failed:\nValues:\ndone[] = $(done[])\n"

        # Default behaviour: try to see if test passes the first time -- if function returns within time limit, returned value is test result value
        c = Ref(0)
        l = ReentrantLock()
        f = (count)-> (sleep(0.1); return lock(()->count[] ≥ 2, l))
        g = @async (while c[] ≤ 2; sleep(0.2); lock(()->c[] += 1, l) end)
        @test_eventually io=io sleep=10ms timeout=500ms f(c)
        message = String(take!(io))
        @test message == "Test `f(c)` failed:\nValues:\nc[] = 0\n"
        
        # Test eventually succeeds 
        c = Ref(0)
        g = @async (while c[] ≤ 2; sleep(0.2); lock(()->c[] += 1, l) end)
        @test_eventually io=io sleep=10ms timeout=500ms repeat=true f(c)

        # Test runs but never succeeds
        d = Ref(0)
        @test_eventually io=io sleep=10ms timeout=100ms repeat=true f(d)
        message = String(take!(io))
        @test message == "Test `f(d)` failed:\nReason: Test took longer than 100 milliseconds to pass\nValues:\nd[] = $(d[])\n"
    end
    @test test_results_match(results, (Test.Error, Test.Pass, Test.Error, Test.Pass, Test.Pass, Test.Fail, Test.Pass, Test.Fail, Test.Pass, Test.Pass, Test.Error, Test.Pass))
end