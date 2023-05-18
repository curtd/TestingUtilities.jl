module TestingUtilities

    using MLStyle, OrderedCollections, Test
    
    export @Test, @test_cases   

    export define_vars_in_failed_tests
    
    include("settings.jl")

    include("macro_util.jl")

    include("computational_graph.jl")

    include("show_values_macro.jl")

    include("test_cases.jl")
end
