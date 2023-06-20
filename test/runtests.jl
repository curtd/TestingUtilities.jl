using TestingUtilities

if VERSION ≥ v"1.9"
    using Aqua
    Aqua.test_all(TestingUtilities)
end

include("TestTestingUtilities.jl")