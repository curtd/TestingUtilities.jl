@enum TestingSetting DefineVarsInFailedTests DefineVarsInFailedTestsModule EmitWarnings

const _TESTING_SETTINGS = Dict{TestingSetting, Any}()

function testing_setting(t::TestingSetting)
    if t == DefineVarsInFailedTests
        return get!(_TESTING_SETTINGS, t, true)::Bool
    elseif t == DefineVarsInFailedTestsModule
        return get!(_TESTING_SETTINGS, t, Main)::Module
    elseif t == EmitWarnings
        return get!(_TESTING_SETTINGS, t, false)::Bool
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

"""
    emit_warnings(value::Bool)

If `value` is `true`, emit warning messages in test macros.

Defaults to `false` if unset. 
"""
function emit_warnings(value::Bool) 
    _TESTING_SETTINGS[EmitWarnings] = value
    return nothing 
end