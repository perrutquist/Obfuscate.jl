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
build_methodset!(ms, h, (Float32,))
build_methodset!(ms, h, (Int64,))

nt = nametable(makename, ms, "tst")

println(nt)

jlprint(stdout, ms, nt, "tst.dylib")

llprint(stdout, ms, nt)

println("Generating files in ", pwd())

obfuscate("tst", ms, prefix="t_")

module Loopback
include("tst.jl")
end

@test h(3.0) === Loopback.h(3.0)
@test h(Float32(3.0)) === Loopback.h(Float32(3.0))
@test h(3) === Loopback.h(3)

#;rm tst.jl tst.ll tst.opt.ll tst.s tst.dylib
