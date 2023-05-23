@enum TestingSetting DefineVarsInFailedTests DefineVarsInFailedTestsModule 

const _TESTING_SETTINGS = Dict{TestingSetting, Any}()

function testing_setting(t::TestingSetting)
    if t == DefineVarsInFailedTests
        return get!(_TESTING_SETTINGS, t, true)
    elseif t == DefineVarsInFailedTestsModule
        return get!(_TESTING_SETTINGS, t, Main)
    end
    return nothing
end

"""
    define_vars_in_failed_tests(value::Bool)

If `value` is `true`, variables that cause a `@Test` expression to fail will be 
defined in `Main` when Julia is run in interactive mode.

Defaults to `true` if unset. 
"""
function define_vars_in_failed_tests(value::Bool) 
    _TESTING_SETTINGS[DefineVarsInFailedTests] = value
    return nothing 
end

should_define_vars_in_failed_tests(should; force::Bool=false) = force || (((!isnothing(should) && should == true) || (isnothing(should) && testing_setting(DefineVarsInFailedTests))) && Base.isinteractive())
