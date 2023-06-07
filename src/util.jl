function module_using_names(m::Module=Main)
    _modules = ccall(:jl_module_usings, Any, (Any,), m)
    output = Set{Symbol}(names(m, imported=true))
    for _mod in _modules 
        union!(output, Set{Symbol}(names(_mod)))
    end
    return output
end

const imported_names_in_main = Ref(Set{Symbol}())

update_imported_names_in_main() = imported_names_in_main[] = module_using_names(Main) 

function unescape(x)
    @switch x begin 
        @case Expr(:$, arg) || Expr(:escape, arg)
            return unescape(arg)
        @case _ 
            return x
    end
end