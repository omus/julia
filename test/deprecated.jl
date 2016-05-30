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
