module TestingUtilities

    using Dates, MLStyle, OrderedCollections, Preferences, Test
    
    export @Test, @test_cases, @test_eventually 

    export define_vars_in_failed_tests

    export TaskTimedOutException, TestTimedOutException
    
    include("util.jl")

    include("test_results_printer.jl")

    include("exceptions.jl")
    
    include("settings.jl")

    include("show_values.jl")
    
    include("macro_util.jl")

    include("computational_graph.jl")

    include("macros/_macros.jl")

    function __init__()
        load_show_diff_styles()
    end
end
