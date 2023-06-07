# Settings 
`TestingUtilities` makes use of the `Preferences` package to store package-side settings for various test failure scenarios.

## String Comparison Tests 
When performing an equality comparison test between two `String` values, say `x` and `y`, if the test fails and the provided `io` object supports printing colours, the matching shared prefix of `x` and `y` will be rendered in green while the differing components of `x` and `y` will be rendered in red.

```@setup settings
using TestingUtilities, Test

mutable struct NoThrowTestSet <: Test.AbstractTestSet
    results::Vector
    NoThrowTestSet(desc) = new([])
end
Test.record(ts::NoThrowTestSet, t::Test.Result) = (push!(ts.results, t); t)
Test.finish(ts::NoThrowTestSet) = ts.results
test_results_match = (results, ref_results)-> all(result isa ref_result for (result, ref_result) in zip(results, ref_results) )

TestingUtilities.set_show_diff_styles(; matching=:color => :green, differing=:color => :red)
```

```@example settings
a = "abcd" 
b = "abef"
c = "abeghik"
@testset NoThrowTestSet "" begin 
    @Test a == b
    @Test isequal(c, "abeg")
end
nothing # hide
```

If you're unable to distinguish between the default colours (or colours more generally), you can set the styles used to render the matching components and differing components of the strings by invoking [`TestingUtilities.set_show_diff_styles`](@ref). You can use any `key => value` pair corresponding to the keyword arguments of [`Base.printstyled`](https://docs.julialang.org/en/v1/base/io-network/#Base.printstyled).

```@example settings 
TestingUtilities.set_show_diff_styles(; matching=:bold => true, differing=:underline => true)
@testset NoThrowTestSet "" begin 
    @Test a == b
    @Test isequal(c, "abeg")
end
nothing # hide
```