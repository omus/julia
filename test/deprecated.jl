# This file is a part of Julia. License is MIT: http://julialang.org/license

let
    @noinline f() = backtrace()
    @noinline g() = f()
    bt = g()

    caller = Base.firstcaller(bt, :f)  # Determine the caller of `f`
    @test first(StackTraces.lookup(caller)).func == :g
end

let
    io = IOBuffer()
    @noinline function f1()
        Base.depwarn(io, "1", :f)
    end
    @noinline function f2()
        Base.depwarn(io, "1", :f)
    end
    @noinline function f3()
        f1()
        f2()
    end
    f3()  # This line should print two depwarn

    seekstart(io)
    @test length(matchall(r"WARNING", readstring(io))) == 2
end

let
    io = IOBuffer()
    @noinline function f()
        Base.depwarn(io, "f is deprecated", :f)
    end

    iterations = 1000
    duration = @elapsed for i in 1:iterations f() end

    seekstart(io)
    @test length(matchall(r"WARNING", readstring(io))) == 1
    @test duration/iterations < 0.002
end

# Pre-improvements
# Mac OS X: 0.00025
# Windows:  0.00061

# For loop test (incr 1000)
# Mac OS X: new 0.0014990471809999998 alt 0.000242912625
# Windows:  new 0.002716              alt 0.000625

# For loop test (incr 1)
# Mac OS X: new 0.001858608892        alt 0.000287275577

Something isn't adding up. I don't think the for loop test accurately tests the issue seen
with building TimeZones
