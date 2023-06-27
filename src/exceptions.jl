"""
    TaskTimedOutException(timer)

Exception thrown when the callback function attached to `timer` took longer than `timer.max_time` to return a value
"""
struct TaskTimedOutException <: Exception
    timer::TaskFinishedTimer
end

Base.showerror(io::IO, e::TaskTimedOutException) = print(io, "TaskFinishedTimer " * (!isempty(e.timer.name) ? "(name = $(e.timer.name)) " : "" ), "took longer than $(e.timer.max_time) to return")

"""
    TestTimedOutException(max_time, original_ex)

Exception thrown when the test given by `original_ex` took longer than `max_time` to return a value
"""
struct TestTimedOutException <: Exception
    max_time::Millisecond
    original_ex::String
end

Base.showerror(io::IO, e::TestTimedOutException) = print(io, "Test `$(e.original_ex)` took longer than $(e.max_time) to pass")