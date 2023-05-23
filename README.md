# TestingUtilities

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://curtd.github.io/TestingUtilities.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://curtd.github.io/TestingUtilities.jl/dev/)
[![Build Status](https://github.com/curtd/TestingUtilities.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/curtd/TestingUtilities.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![][codecov-img]][codecov-url]

`TestingUtilities` provides macros for improving the visibility into your failing tests.

# `@Test` 
An expression invoking `@Test` outputs the value of (automatically-determined) variables of interest when the underlying test errors or fails. E.g., 
```julia
    x = 1
    @Test x^2 == 2
```

Sample output:
```
    Test `x ^ 2 == 2` failed with values:
    `x ^ 2` = 1
    x = 1
    Test Failed at REPL[278]:1
     Expression: x ^ 2 == 2
      Evaluated: false
```

This macro can handle a number of more complicated combinations of Julia expressions, e.g., 
```julia
    test_parity(a; is_odd::Bool) = mod(a,2) == (is_odd ? 1 : 0)
    A = collect(1:10)
    all_is_odd = (false, true)
    @Test all([test_parity(a; is_odd) for a in A for is_odd in all_is_odd])
```

Sample output:
```
    Test `all([test_parity(a; is_odd) for a = A for is_odd = all_is_odd])` failed with values:
    `[test_parity(a; is_odd) for a = A for is_odd = all_is_odd]` = Bool[0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0]
    A = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
```

No values are printed when the test passes. 

# `@test_cases` 
The `@test_cases` macro allows you to compactly evaluate test expressions on test cases with the same underlying data fields, but differing values. The values of the specific test cases that cause each test expression to fail will be printed, similar to `@Test`. 

If run as a standalone macro invocation, the tests will terminate at the first instance of failure, e.g., 
```julia
    @test_cases begin 
        a | b | output 
        1 | 2 | 3
        1 | 2 | 4
        0 | 0 | 1
        0 | 0 | -1
        @test a + b == output
    end
```

Sample output:
```
    Test `a + b == output` failed with values:
    ------
    `a + b` = 3
    output = 4
    a = 1
    b = 2
```

When run inside a `@testset`, all of the failing test values will be printed 

```julia
    @testset "Failing Test" begin
       @test_cases begin 
            a | b | output 
            1 | 2 | 3
            1 | 2 | 4
            0 | 0 | 1
            0 | 0 | -1
            @test a + b == output
        end
    end
```

Sample output:
```
    Test `a + b == output` failed with values:
    ------
    `a + b` = 3
    output = 4
    a = 1
    b = 2
    ------
    `a + b` = 0
    output = 1
    a = 0
    b = 0
    ------
    `a + b` = 0
    output = -1
    a = 0
    b = 0
```