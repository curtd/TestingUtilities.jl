module TestTestingUtilities 
    using TestingUtilities 
    using TestingUtilities.MLStyle, TestingUtilities.OrderedCollections, TestingUtilities.Test

    using DataFrames, DataFrames.PrettyTables, Dates, WidthLimitedIO

    mutable struct NoThrowTestSet <: Test.AbstractTestSet
        results::Vector
        NoThrowTestSet(desc) = new([])
    end
    Test.record(ts::NoThrowTestSet, t::Test.Result) = (push!(ts.results, t); t)
    Test.finish(ts::NoThrowTestSet) = ts.results
    test_results_match = (results, ref_results)-> all(result isa ref_result for (result, ref_result) in zip(results, ref_results) )

    run_df_tests = VERSION ≥ v"1.9"

    struct ShowDiffChild1_1
        x::String 
        y::Int
    end
    
    struct ShowDiffChild1_2
        y::Bool 
        z::Float64
    end
    
    struct ShowDiffChild1_3 
        a::Vector{Int}
    end
    
    struct ShowDiffChild1
        key1::Union{ShowDiffChild1_1, ShowDiffChild1_2}
        key2::Dict{String, Any}
    end
    
    struct ShowDiffChild2 
        key3::Symbol
    end
    
    struct ShowDiffParent 
        child::Union{ShowDiffChild1, ShowDiffChild2}
    end

    include("test_util/_test_util.jl")

    include("test_settings.jl")

    include("test_Test_macro.jl")
    
    include("test_cases_macro.jl")

    include("test_eventually_macro.jl")

end