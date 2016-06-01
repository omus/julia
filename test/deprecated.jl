# This file is a part of Julia. License is MIT: http://julialang.org/license

# Note: Tests usually run with `--depwarn=error` (2)

# Calling the same deprecated function from different callers should generate multiple
# warnings
let
    io = IOBuffer()
    @noinline deprecated_16617() = Base.depwarn(io, "message", :deprecated_16617, mode=1)
    @noinline f1_16617() = deprecated_16617()
    @noinline f2_16617() = deprecated_16617()
    @noinline function f3_16617()
        f1_16617()
        f2_16617()
    end
    f3_16617()  # This line should print two depwarn
    @test length(matchall(r"WARNING", readstring(seekstart(io)))) == 2
end

# Calling the same deprecated function from the same caller should result in one warning.
let
    io = IOBuffer()
    @noinline deprecated_16617() = Base.depwarn(io, "message", :deprecated_16617, mode=1)
    @noinline g1_16617() = deprecated_16617()
    @noinline function g2_16617()
        g1_16617()
        g1_16617()
    end
    g2_16617()  # This line should print only one depwarn
    @test length(matchall(r"WARNING", readstring(seekstart(io)))) == 1
end

### MANUAL TESTS

iterations = 1000
io = IOBuffer()
@noinline function f()
    Base.depwarn(io, "f is deprecated", :f)
end
for limit in 3:7, julia_only in (true,), incr in (1, limit)
    seekstart(io)
    Base.set_depwarn(limit, julia_only, incr)
    Base.DWOptions.calls = 0
    Base.DWOptions.failsafe = 0
    Base.DWOptions.displayed = 0
    func = @eval $(gensym())() = f()
    duration = @elapsed for i in 1:iterations func() end
    @printf("%4d %5s %4d: %0.8f %4d %4d %4d\n",
        limit, julia_only, incr, duration/iterations,
        Base.DWOptions.calls, Base.DWOptions.failsafe, Base.DWOptions.displayed,
    )
    seekstart(io)
    println(readstring(io))
    println("*" ^ 40)
end

function bench(limit, julia_only, incr)
    Base.set_depwarn(limit, julia_only, incr)
    Base.DWOptions.calls = 0
    # Base.DWOptions.failsafe = 0
    Base.DWOptions.displayed = 0
    func = @eval $(gensym())() = f()
    duration = @elapsed for i in 1:iterations func() end
    @printf("%4d %5s %4d: %0.8f %4d %4d\n",
        limit, julia_only, incr, duration/iterations,
        Base.DWOptions.calls, Base.DWOptions.displayed,
    )
end


for limit in 3:7, julia_only in (true,), incr in (1, limit)
    bench(limit, julia_only, incr)
end
