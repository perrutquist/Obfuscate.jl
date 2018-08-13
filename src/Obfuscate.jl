module Obfuscate

using InteractiveUtils, Libdl

export MethodInfo, MethodSet, llvmstring, remove_comments, invokedfuns,
    makename, getlocalname, build_methodset, build_methodset!, nametable,
    jlprint, llprint, obfuscate

llvmstring(f, types) = sprint(code_llvm, f, types)

mutable struct MethodInfo
    f::Function
    types::Tuple
    localname::Symbol
    local_ir::String
    return_type::DataType
end

function MethodInfo(f, types; nocomment=true)
    ir = llvmstring(f, types)
    ir = nocomment ? remove_comments(ir) : ir
    ln = getlocalname(ir)
    rts = Base.return_types(f, types)
    length(rts) == 1 || error("No unique return type for ", f, types)
    MethodInfo(f, types, ln, ir, rts[1])
end

struct MethodSet
    by_localname::Dict{Symbol, MethodInfo}
    by_sig::Dict{Tuple{Function,Tuple}, MethodInfo}
end

MethodSet() = MethodSet(Dict{Symbol, MethodInfo}(), Dict{Tuple{Function,Tuple}, MethodInfo}())

Base.push!(s::MethodSet, x::MethodInfo) = begin
    s.by_localname[x.localname] = x
    s.by_sig[(x.f, x.types)] = x
end

Base.getindex(s::MethodSet, name::Symbol) = s.by_localname[name]
Base.getindex(s::MethodSet, sig::Tuple{Function, Tuple}) = s.by_localname[sig]

Base.in(name::Symbol, s::MethodSet) = name in keys(s.by_localname)
Base.in(sig::Tuple{Function, Tuple}, s::MethodSet, ) = sig in keys(s.by_localname)

build_methodset(f::Function, types::Tuple; recurse::Bool=true) =
   build_methodset!(MethodSet(), f, types, recurse=recurse)

function build_methodset!(s::MethodSet, f::Function, types::Tuple; recurse::Bool=true)
    if (f, types) in s
        return s
    end
    println(f, "(", join(string.(types), ", "), ")")
    push!(s, MethodInfo(f, types))
    if recurse
        for (f1, types1) in invokedfuns(f, types)
            build_methodset!(s, f1, types1)
        end
    end
    return s
end

function remove_comments(ir)
   lines = split(ir, '\n')
   join(filter(s->!startswith(s, ";"), lines) , "\n")
end

function invokedfuns(f, types)
   ast = code_typed(f, types)
   v = Vector{Tuple{Function, Tuple}}()
   @assert length(ast) == 1
   for e in ast[1][1].code
       if e isa Expr && e.head == :invoke
           f1 = eval(e.args[2])
           if f1 isa Function
               push!(v, (f1, Tuple(e.args[1].specTypes.parameters[2:end])))
           end
       end
   end
   return v
end

makename(f, types) = string(f, "_", join(string.(types), "_"))

function getlocalname(ir::String)
    lines = split(ir, '\n')
    def = filter(s->startswith(s, "define"), lines)
    length(def) == 1 || error("function definition not found")
    parts = split(def[1], ' ')
    d = filter(s->startswith(s, "@julia_"), parts)
    length(d) == 1 || error("local name not found")
    return Symbol(split(d[1], '(')[1][2:end])
end

function nametable(namefun, ms::MethodSet, prefix="")
    nt = Vector{Pair{String,String}}()
    for m in values(ms.by_sig)
        push!(nt, String(m.localname) => namefun(m.f, m.types))
    end
    return nt
end

function replaceall(s::AbstractString, reps)
    for r in reps
        s = replace(s, r)
    end
    return s
end

function jlprint(io::IO, ms::MethodSet, nametable, libname)
    ntd = Dict(nametable)
    for m in values(ms.by_sig)
        print(io, m.f, "(")
        join(io, map(i -> string("x", i, "::", m.types[i]), 1:length(m.types)), ",")
        print(io, ") = ccall((:", ntd[string(m.localname)], ", \"", libname, "\"), ")
        print(io, m.return_type, ", ")
        print(io, m.types, ", ")
        join(io, map(i -> string("x", i), 1:length(m.types)), ",")
        println(io, ")")
    end
end

function llprint(io::IO, ms::MethodSet, nametable)
    for m in values(ms.by_sig)
        print(io, replaceall(m.local_ir, nametable))
    end
end

opt(ll, oll) = run(`opt $ll -o $oll`)

llc(ll, asm; level="-O3") = run(`llc $level -o $asm $ll`)

clang(asm, dl) = run(`clang -shared -o $dl $asm`)

function obfuscate(name::AbstractString, ms::MethodSet; namefun=makename, prefix="")
    jl = name * ".jl"
    ll = name * ".ll"
    oll = name * ".bc"
    asm = name * ".s"
    dl = name * "." * Libdl.dlext

    nt = nametable(namefun, ms, prefix)

    open(jl, "w") do f
        jlprint(f, ms, nt, dl)
    end
    open(ll, "w") do f
        llprint(f, ms, nt)
    end

    opt(ll, oll)
    llc(oll, asm)
    clang(asm, dl)
end

end # module
