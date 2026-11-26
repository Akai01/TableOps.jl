using Test, TableOps
isdefined(@__MODULE__, :same_table) || include("checks.jl")

@testset "specs" begin
    S = TableOps._specs
    s = S(:mutate, (), (; c = :a))[1]
    @test (s.name, s.inputs, s.f, s.calls) == (:c, [:a], identity, ())
    s = S(:mutate, (), (; c = :a => sum))[1]
    @test (s.name, s.inputs, s.f, s.calls) == (:c, [:a], sum, ())
    s = S(:mutate, (), (; c = ["a", :b] => (x, y) -> x))[1]
    @test s.inputs == [:a, :b]
    @test S(:mutate, (), (; c = "a" => sum))[1].inputs == [:a]   # String on the left
    s = S(:mutate, (), (; c = :a => each(sqrt)))[1]
    @test s.f isa TableOps.Each && s.f([4, 9]) == [2.0, 3.0] && s.inputs == [:a]
    s = S(:mutate, (), (; c = t -> 1))[1]
    @test s.inputs == Symbol[] && s.f(nothing) == 1
    v = [1, 2, 3]
    c = S(:mutate, (), (; c = "EU", d = v, e = missing))
    @test [x.name for x in c] == [:c, :d, :e]                    # keyword order
    @test all(x -> x.inputs == Symbol[] && x.f isa Returns && x.calls === (), c)
    @test c[1].f(nothing) == "EU" && c[2].f(nothing) === v && ismissing(c[3].f(nothing))
    @test S(:mutate, (), (;)) == []
    # positional, unnamed (allowed for where)
    u = S(:where, (:a => each(>(1)), :flag), (;); allow_unnamed = true)
    @test [x.name for x in u] == [Symbol(""), Symbol("")]
    @test u[2].inputs == [:flag] && u[2].f === identity
    # keyword specs keep their order
    o = S(:mutate, (), (; b = 1, a = 2)); @test [x.name for x in o] == [:b, :a]
    # positional specs come before keyword specs
    @test [x.name for x in S(:where, (:x,), (; b = :y); allow_unnamed = true)] ==
        [Symbol(""), :b]
    @test S(:mutate, (), (; var"unit price" = :a))[1].name == Symbol("unit price")
    @test S(:mutate, (), (; 名前 = 1))[1].name == :名前
    @test eltype(S(:mutate, (), (; c = 1))) == TableOps.ColSpec

    @test msg(() -> S(:mutate, (:a => sum,), (;))) ==
        "mutate: a column specification needs a name. Got :a => sum. " *
        "Write name = :a => sum."
    @test msg(() -> S(:mutate, (:a,), (;))) ==
        "mutate: a column specification needs a name. Got :a. Write name = :a."
    @test msg(() -> S(:where, (5,), (;); allow_unnamed = true)) ==
        "where: not a valid condition. Got 5. Use :flag (a Bool column), " *
        ":col => f, [:a, :b] => f, :col => each(f) or a function of the table " *
        "such as t -> t.x .> 1."
    @test msg(() -> S(:mutate, (5,), (;))) ==
        "mutate: not a valid column specification. Got 5. Use :col, :col => f, " *
        "[:a, :b] => f, :col => each(f), name = :col, name = value or name = t -> …."
    @test msg(() -> S(:mutate, (), (; c = 1 => sum))) ==
        "mutate: the left side of => must be a column name or a non-empty vector " *
        "of names. Got 1. Write :a => f or [:a, :b] => f."
    @test msg(() -> S(:mutate, (), (; c = Symbol[] => sum))) ==
        "mutate: the left side of => must be a column name or a non-empty vector " *
        "of names. Got Symbol[]. Write :a => f or [:a, :b] => f."
    @test msg(() -> S(:mutate, (), (; c = [:a, 1] => sum))) ==
        "mutate: the left side of => must be a column name or a non-empty vector " *
        "of names. Got Any[:a, 1]. Write :a => f or [:a, :b] => f."
    @test msg(() -> S(:mutate, (), (; c = :a => 5))) ==
        "mutate: the right side of => must be a function or each(f). Got 5. " *
        "Write :a => f, where f takes whole columns, " *
        "or :a => each(f) to apply f to each element."
    @test msg(() -> S(:mutate, (), (; c = :a => Float64))) ==
        "mutate: the right side of => must be a function or each(f). Got Float64. " *
        "Write :a => f, where f takes whole columns, " *
        "or :a => each(f) to apply f to each element."
    @test msg(() -> S(:mutate, (:a => each(sqrt),), (;))) ==
        "mutate: a column specification needs a name. Got :a => each(sqrt). " *
        "Write name = :a => each(sqrt)."
    @test msg(() -> S(:mutate, (), (; c = each(sin)))) ==
        "mutate: each(f) needs a column to work on. Got each(f). " *
        "Write :col => each(f)."
    @test msg(() -> S(:mutate, (each(sin),), (;))) ==
        "mutate: each(f) needs a column to work on. Got each(f). " *
        "Write :col => each(f)."
    @test msg(() -> S(:mutate, (), (; c = (1, 2)))) ==
        "mutate: a value must be a single value or a vector. Got (1, 2). " *
        "Pass a vector with one value per row (collect a generator first), " *
        "or wrap the value in a vector: name = [x]."
    @test msg(() -> S(:mutate, (), (; c = [1 2; 3 4]))) ==
        "mutate: a value must be a single value or a vector. Got [1 2; 3 4]. " *
        "Pass a vector with one value per row (collect a generator first), " *
        "or wrap the value in a vector: name = [x]."
    for (bad, shown) in (((a = 1,), "(a = 1,)"), (Set([1]), "Set([1])"),
                         (Dict(:a => 1), "Dict(:a => 1)"))
        @test msg(() -> S(:mutate, (), (; c = bad))) ==
            "mutate: a value must be a single value or a vector. Got $shown. " *
            "Pass a vector with one value per row (collect a generator first), " *
            "or wrap the value in a vector: name = [x]."
    end
    g = (x for x in 1:3)
    @test occursin("a value must be a single value or a vector. Got Base.Generator",
        msg(() -> S(:mutate, (), (; c = g))))
    @test S(:mutate, (), (; c = [(a = 1,)])) isa Vector       # wrapped: fine
    @test msg(() -> S(:mutate, (), (; c = skipmissing([1])))) ==
        "mutate: a value must be a single value or a vector. Got skipmissing([1]). " *
        "Pass a vector with one value per row (collect a generator first), " *
        "or wrap the value in a vector: name = [x]."
    @test occursin("Got ", msg(() -> S(:mutate, (), (; c = zip(1:2, 3:4)))))
    @test occursin("a value must be",
        msg(() -> S(:mutate, (), (; c = Iterators.take(1:5, 2)))))
    @test msg(() -> S(:mutate, (), (; c = Table(; z = [1])))) ==
        "mutate: a value is a whole table. Got " * TableOps._fmt_value(Table(; z = [1])) *
        ". To add one of its columns write name = pull(other, :col); " *
        "to combine tables use a join."
    @test msg(() -> S(:mutate, (), (; c = nothing))) ==
        "mutate: a function returned nothing for c. Got nothing. " *
        "Return a value; use missing for an absent one."
    @test S(:mutate, (), (; c = [(a = 1,), (a = 2,)])) isa Vector
end

@testset "each" begin
    e = each(x -> x + 1)
    @test e([1, 2]) == [2, 3] && eltype(e([1, 2])) == Int
    @test @inferred(e([1, 2])) == [2, 3]
    @test each((x, y) -> x + y)([1, 2], [10.0, 20.0]) == [11.0, 22.0]    # zipped
    @test isequal(each(x -> x * 2)([1, missing]), [2, missing])          # missing in
    @test each(x -> x + 1)(Int[]) == Int[] && eltype(each(x -> x + 1)(Int[])) == Int
    @test !(e isa Function)
    @test repr(each(sqrt)) == "each(sqrt)"
    @test msg(() -> each(5)) ==
        "each: needs a function. Got 5. Write each(f), for example :a => each(round)."
end

@testset "_run" begin
    S = TableOps._specs
    run1(spec, t) = TableOps._run(S(:mutate, (), spec)[1], t, :mutate)
    t = Table(; a = [1, 2, 3], b = [10, 20, 30])
    @test run1((; c = :a), t) === t.a
    @test run1((; c = :a => sum), t) == 6
    @test run1((; c = [:a, :b] => (x, y) -> x .+ y), t) == [11, 22, 33]
    @test run1((; c = :a => each(x -> x * 2)), t) == [2, 4, 6]
    @test run1((; c = t -> nrow(t)), t) == 3
    @test run1((; c = "EU"), t) == "EU"
    @test run1((; c = [7, 8, 9]), Table(; a = [1, 2, 3])) == [7, 8, 9]
    @test run1((; c = :a => sum), Table(; a = Int[])) == 0
    t0 = Table()
    @test run1((; c = 5), t0) == 5
    @test run1((; c = t -> nrow(t)), t0) == 0
    @test msg(() -> run1((; c = :zz => sum), t)) ==
        "mutate: column not found. Got :zz. Available columns: :a, :b."
end

@testset "specs for where (Phase 3)" begin
    S = TableOps._specs
    f = S(:where, (tt -> tt.a .> 1, :a => each(>(1))), (;); allow_unnamed = true)
    @test f[1].inputs == Symbol[] && f[1].f isa Function && f[1].name == Symbol("")
    # mutate keeps the column wording, rejects a function
    @test msg(() -> S(:mutate, (sum,), (;))) ==
        "mutate: not a valid column specification. Got sum. Use :col, :col => f, " *
        "[:a, :b] => f, :col => each(f), name = :col, name = value or name = t -> …."
    empty = NamedTuple{(Symbol(""),)}((1,))
    gave = "a column name cannot be empty. Got Symbol(\"\"). Give the column a name."
    @test msg(() -> S(:mutate, (), empty)) == "mutate: " * gave
    @test msg(() -> S(:where, (), empty)) == "where: " * gave
end
