module TestingUtilities

    using MLStyle, OrderedCollections, Preferences, Test
    
    export @Test, @test_cases   

    export define_vars_in_failed_tests
    
    include("util.jl")
    
    include("settings.jl")

    include("show_values.jl")
    
    include("macro_util.jl")

    include("computational_graph.jl")

    include("macros/_macros.jl")

    function __init__()
        load_show_diff_styles()
    end
end
