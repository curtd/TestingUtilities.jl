function show_value_str(value; kwargs...)
    io = IOBuffer()
    show_value(io, value; kwargs..., newline=false)
    return String(take!(io))
end

function _show_name_str(name)
    if name isa Expr 
        _name = show_value_str(name; use_backticks=true)
    else
        _name = string(name)
    end
    return _name
end

function _show_name(ctx, name)
    _name = _show_name_str(name)
    print(ctx, _name)
    return textwidth(_name)
end

function show_value(ctx::IOContext, value::Ref; kwargs...)
    println(ctx, "Ref(")
    result = show_value(ctx, value[]; kwargs...)
    println(ctx, ")")
    return result
end

function show_value(ctx::IOContext, value; kwargs...)
    println(ctx, repr(value))
    flush(ctx)
    return nothing
end

function show_value(ctx::IOContext, value::Expr; remove_line_nums::Bool=false, use_backticks::Bool=true, newline::Bool=true, kwargs...)
    if Meta.isexpr(value, :macrocall)
        remove_line_nums = true 
    end
    if remove_line_nums
        value = remove_linenums(value)
    end
    if use_backticks
        print(ctx, '`')
    else
        print(ctx, ':', '(')
    end
    if Meta.isexpr(value, :macrocall)
        Base.show_unquoted(ctx, value)
    else
        print(ctx, string(value))
    end
    if use_backticks
        print(ctx, '`')
    else
        print(ctx, ')')
    end
    if newline
        println(ctx)
    end
    return nothing
end

show_value(io::IO, value; compact::Bool=true, kwargs...) = show_value(IOContext(io, :compact => compact), value; kwargs...)
show_value(value; io=stderr, kwargs...) = show_value(io, value; kwargs...)

function show_indented(show_value_func, ctx::IOContext, _displaysz::Tuple{Int,Int}, value; indent::Int, kwargs...)
    io_indented = IOBuffer()
    ioc_indented = IOContext(io_indented, 
        :displaysize => (_displaysz[1], max(1, _displaysz[2] - indent)), 
        :compact => get(ctx, :compact, false)::Bool
    )
    show_value_func(ioc_indented, value; kwargs...)
    indented = String(take!(io_indented))
    indent_str = ' '^indent
    indented_s = split(indented, "\n")
    for (i,line) in enumerate(indented_s)
        if i > 1 
            println(ctx)
            if i < length(indented_s) || !isempty(line)
                print(ctx, indent_str, line)
            end
        else 
            print(ctx, line)
        end
    end
    return length(indented_s) > 1
end
function __show_name(ctx, name)
    name_width = _show_name(ctx, name)
    print(ctx, " = ")
    name_width += 3 
    return name_width
end

function show_name_value(show_value_func, ctx::IOContext, name, value; kwargs...)
    name_width = __show_name(ctx, name)
    return show_indented(show_value_func, ctx, displaysize(ctx), value; indent=name_width, kwargs...)
end
function show_name_value(show_value_func, ctx::IOContext, name, value::Expr; kwargs...)
    name_width = __show_name(ctx, name)
    return show_indented(show_value_func, ctx, displaysize(ctx), value; indent=name_width, kwargs..., use_backticks=false)
end

function show_name_value(show_value_func, ctx::IOContext, name, value::Ref; kwargs...)
    name_width = _show_name(ctx, name)
    print(ctx, "[] = ")
    name_width += 5
    return show_indented(show_value_func, ctx, displaysize(ctx), value[]; indent=name_width, kwargs...)
end


show_name_value(io::IOContext, name, value; kwargs...) = show_name_value(show_value, io, name, value; kwargs...)

show_name_value(io::IO, name, value; compact::Bool=true, kwargs...) = show_name_value(IOContext(io, :compact => compact), name, value; kwargs...)

show_value(name, value; io=stderr, kwargs...) = show_name_value(io, name, value; kwargs...)
