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

    TestingUtilities.set_show_diff_styles(; matching=:color => :green, differing=:color => :red)
    @test TestingUtilities.show_diff_matching_style == [:color => :green]
    @test TestingUtilities.show_diff_differing_style == [:color => :red]
    TestingUtilities.set_show_diff_styles(; matching=:bold => true, differing=:underline => true)
    @test TestingUtilities.show_diff_matching_style == [:bold => true]
    @test TestingUtilities.show_diff_differing_style == [:underline => true]
    
    @test_throws ErrorException TestingUtilities.set_show_diff_styles(; matching=:bold => :bad_val, differing=:underline => :bad_val)
    @test TestingUtilities.show_diff_matching_style == [:bold => true]
    @test TestingUtilities.show_diff_differing_style == [:underline => true,]

    TestingUtilities.set_show_diff_styles(; matching=[:color => :green, :underline => true], differing=[:color => :red, :underline => true])
    @test TestingUtilities.show_diff_matching_style == [:color => :green, :underline => true]
    @test TestingUtilities.show_diff_differing_style == [:color => :red, :underline => true]

end