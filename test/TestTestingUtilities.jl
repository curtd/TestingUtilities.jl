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

    include("test_util.jl")

    include("test_settings.jl")

    include("test_Test_macro.jl")
    
    include("test_cases_macro.jl")

end