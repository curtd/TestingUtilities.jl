@testset "Settings" begin 

    TestingUtilities.define_vars_in_failed_tests(true)
    @test TestingUtilities.should_define_vars_in_failed_tests(false) == false
    @test TestingUtilities.should_define_vars_in_failed_tests(true) == Base.isinteractive()
    @test TestingUtilities.should_define_vars_in_failed_tests(nothing) == Base.isinteractive() 

    TestingUtilities.define_vars_in_failed_tests(false)
    @test TestingUtilities.should_define_vars_in_failed_tests(false) == false
    @test TestingUtilities.should_define_vars_in_failed_tests(true) == Base.isinteractive()
    @test TestingUtilities.should_define_vars_in_failed_tests(nothing) == false

    for b in (false, true)
        TestingUtilities.emit_warnings(b) 
        @test TestingUtilities.testing_setting(TestingUtilities.EmitWarnings) == b 
    end
    for b in (false, true)
        TestingUtilities.emit_warnings(b) 
        @test TestingUtilities.testing_setting(TestingUtilities.EmitWarnings) == b 
    end
end