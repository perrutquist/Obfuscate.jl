using Obfuscate
using Test

@noinline f(x) = 2x + 3
h(x) = f(x)^2

println(remove_comments(llvmstring(f, (Int64,))))

ir = remove_comments(llvmstring(h, (Float64,)))

println(ir)

println(invokedfuns(h, (Float64,)))

println(makename(h, (Float64,)))

println(getlocalname(llvmstring(h, (Float64,))))

ms = build_methodset(h, (Float64,))

nt = nametable(makename, ms, "tst")

println(nt)

jlprint(stdout, ms, nt, "tst.dylib")

llprint(stdout, ms, nt)

println("Generating files in ", pwd())

obfuscate("tst", ms, prefix="t_")

h3 = h(3.0)

include("tst.jl")

@test h(3.0) === h3

#;rm tst.jl tst.ll tst.opt.ll tst.s tst.dylib
