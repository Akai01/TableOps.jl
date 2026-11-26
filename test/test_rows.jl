using Test, TableOps, StableRNGs
isdefined(@__MODULE__, :same_table) || include("checks.jl")
rn(x) = getfield(x, :names)
rc(x) = getfield(x, :columns)
rint(rng, n, hi) = [Base.rand(rng, 1:hi) for _ in 1:n]

@testset "_gather and _take" begin
    cols = (Int => [10, 20, 30], Float64 => [1.5, NaN, 3.5],
            String => ["a", "b", "c"],
            Union{Missing,Float64} => Union{Missing,Float64}[1.0, missing, 3.0])
    for (T, c) in cols
        @test @inferred(TableOps._gather(c, [3, 1, 1])) isa Vector{T}
        @test @inferred(TableOps._gather(c, 2:3)) isa Vector{T}
        @test isequal(TableOps._gather(c, [3, 1, 1]), c[[3, 1, 1]])
        @test isequal(TableOps._gather(c, 2:3), c[2:3])
        @test TableOps._gather(c, Int[]) isa Vector{T}
        @test isempty(TableOps._gather(c, Int[]))
        @test TableOps._gather(c, [1]) !== c
    end
    @test TableOps._gather(view([1, 2, 3], 1:3), [2]) isa Vector{Int}
    @test TableOps._gather(1:3, [3, 2]) == [3, 2]
    @test TableOps._gather([10, 20, 30], Base.IdentityUnitRange(2:3)) == [20, 30]
    @test TableOps._gather(BitVector([true, false]), [2, 1]) isa Vector{Bool}
    @test TableOps._gather(Union{Missing,Int}[1, 2], [2]) isa Vector{Union{Missing,Int}}
    @test TableOps._gather([missing, missing], [1]) isa Vector{Missing}
    @test_throws BoundsError TableOps._gather([1, 2], [3])
    @test_throws BoundsError TableOps._gather([1, 2], [0])

    t = Table(; a = [1, 2, 3], b = ["x", "y", "z"])
    r = TableOps._take(t, [3, 1])
    @test same_table(r, Table(; a = [3, 1], b = ["z", "x"]))
    @test rc(r)[1] !== rc(t)[1]
    @test rc(r)[2] !== rc(t)[2]
    @test rn(r) !== rn(t)
    @test getfield(r, :lookup) !== getfield(t, :lookup)
    @test same_table(TableOps._take(t, 1:3), t)
    @test rc(TableOps._take(t, 1:3))[1] !== rc(t)[1]
    @test same_table(TableOps._take(t, Int[]), Table(; a = Int[], b = String[]))
    @test nrow(TableOps._take(Table(), Int[])) == 0
    @test ncol(TableOps._take(Table(), Int[])) == 0
    @test @inferred(TableOps._take(t, [1])) isa Table
    u = Table(; var"unit price" = [1.0, 2.0], 名前 = ["x", "y"])
    @test rn(TableOps._take(u, [2])) == [Symbol("unit price"), :名前]
    check_input_unchanged(x -> TableOps._take(x, [2, 2]), t)
    w = Table(; a = [1], m = [missing], f = [1.5, 2.5][1:1])
    check_concrete_eltypes(TableOps._take(w, [1]))
end

@testset "where" begin
    w = Table(; a = [3, 1, 2, 1], b = ["x", "y", "z", "w"],
                c = Union{Missing,Float64}[1.5, missing, 3.5, 0.5])
    cm = Union{Missing,Float64}
    whatif = "where: a condition must give true, false or missing. Got condition "
    bool_fix = ". Return Bool values, for example :x => each(>(1))."
    shapes = "Use :flag (a Bool column), :col => f, [:a, :b] => f, :col => each(f) " *
        "or a function of the table such as t -> t.x .> 1."
    kwmsg(kv) = "where: conditions are positional, not keywords. Got $kv. " *
        "Write a condition such as where(t, :x => each(>(1))); " *
        "to add a column use mutate."
    lenmsg(m) = "where: a condition has the wrong length. Got condition 1 has $m rows, " *
        "the table has 4. Return one true or false per row, or a single one for every row."
    r = check_forms_agree(where, w, :a => each(>(1)))
    @test same_table(r, Table(; a = [3, 2], b = ["x", "z"], c = cm[1.5, 3.5]))
    @test all(i -> rc(r)[i] !== rc(w)[i], 1:3) && rn(r) !== rn(w)
    @test same_table(where(w, :c => each(>(1))), r)
    @test same_table(where(w, :c => each(<(3))),
        Table(; a = [3, 1], b = ["x", "w"], c = cm[1.5, 0.5]))
    @test same_table(where(w, :a => each(>(1)), :c => each(<(3))),
        Table(; a = [3], b = ["x"], c = cm[1.5]))
    @test same_table(where(w, [:a, :c] => (a, c) -> (a .> 1) .& (c .< 4)), r)
    @test same_table(where(w, tt -> tt.a .> 1), r)
    @test same_table(where(w, :a => each(>(1)), tt -> tt.a .< 3),
        Table(; a = [2], b = ["z"], c = cm[3.5]))
    @test same_table(where((x = [1, missing, 3],), :x => each(>(1))),
        Table(; x = Union{Missing,Int}[3]))
    k = Table(; k = Union{Missing,Bool}[true, false, missing, true], i = [1, 2, 3, 4])
    @test same_table(where(k, :k),
        Table(; k = Union{Missing,Bool}[true, true], i = [1, 4]))
    @test same_table(where(Table(; k = [true, false], i = [1, 2]), :k),
        Table(; k = [true], i = [1]))
    @test same_table(where(k, :k => each(!ismissing)),
        Table(; k = Union{Missing,Bool}[true, false, true], i = [1, 2, 4]))
    # a single value or a length-1 result applies to every row
    none = Table(; a = Int[], b = String[], c = cm[])
    @test same_table(where(w, tt -> true), w)
    @test rc(where(w, tt -> true))[1] !== rc(w)[1]
    @test same_table(where(w, tt -> false), none)
    @test same_table(where(w, tt -> missing), none)
    @test same_table(where(w, :a => (a -> sum(a) > 5)), w)
    @test same_table(where(w, :a => (a -> [true])), w)
    @test same_table(where(w, :a => (a -> [false])), none)
    @test same_table(where(w, :a => (a -> [missing])), none)
    x = Table(; x = cm[NaN, 1.0, 2.0, missing])
    @test same_table(where(x, :x => each(isnan)), Table(; x = cm[NaN]))
    @test same_table(where(x, :x => each(>(0))), Table(; x = cm[1.0, 2.0]))
    z = Table(; a = Int[], s = String[])
    @test same_table(where(z, :a => each(>(0))), z)
    @test same_table(where(z, tt -> true), z)
    @test same_table(where(Table(), tt -> true), Table())
    @test same_table(where(Table(; a = [5]), :a => each(>(1))), Table(; a = [5]))
    @test same_table(where(Table(; a = [5]), :a => each(<(1))), Table(; a = Int[]))
    mm = Table(; m = [missing, missing], i = [1, 2])
    @test same_table(where(mm, :m), Table(; m = Missing[], i = Int[]))
    u = Table(; var"unit price" = [1.0, 2.0], 名前 = ["x", "y"])
    @test same_table(where(u, Symbol("unit price") => each(>(1.5))),
        Table(; var"unit price" = [2.0], 名前 = ["y"]))
    @test same_table(where(u, "名前" => each(==("x"))),
        Table(; var"unit price" = [1.0], 名前 = ["x"]))
    @test where(w) === w && where()(w) === w
    @test where((a = [1],)) isa Table
    # every condition sees the whole table
    boom = :b => each(s -> s == "y" ? error("boom") : true)
    @test_throws(ErrorException, where(w, :a => each(>(1)), boom))
    check_input_unchanged(x -> where(x, :a => each(>(1))), w)
    check_concrete_eltypes(where(w, :a => each(>(1))))
    @test same_table(w |> where(:a => each(>(1))), where(w, :a => each(>(1))))
    @test same_table(where(:a => each(>(1)), tt -> tt.a .< 3)(w),
        where(w, :a => each(>(1)), tt -> tt.a .< 3))
    @test where(:k) isa Function && where(tt -> true) isa Function
    @test same_table(where((a = [1, 2],), :a => each(>(1))), Table(; a = [2]))
    sp = TableOps._specs(:where, (:a => each(>(1)),), (;); allow_unnamed = true)
    @test @inferred(TableOps._where_rows(w, sp)) == [1, 3]
    keep = trues(4)
    mb = Union{Missing,Bool}[true, missing, false, true]
    @test @inferred(TableOps._and!(keep, mb, 1)) === keep
    @test keep == [true, false, false, true]
    # errors
    @test msg(() -> where(5)) ==
        "where: the first argument is neither a table nor a condition. Got 5. " *
        "Pass a table, or conditions such as where(:x => each(>(1))) " *
        "for the pipe form."
    @test msg(() -> where(w, 5)) == "where: not a valid condition. Got 5. " * shapes
    @test msg(() -> where(w, "a")) == "where: not a valid condition. Got \"a\". " * shapes
    @test msg(() -> where(w, true)) == "where: not a valid condition. Got true. " * shapes
    @test msg(() -> where(w; a = :b)) == kwmsg("a = :b")
    @test msg(() -> where(; a = 1)) == kwmsg("a = 1")
    @test msg(() -> where(w, :a => each(>(1)); z = 1)) == kwmsg("z = 1")
    @test msg(() -> where(:a => 5)) ==
        "where: the right side of => must be a function or each(f). Got 5. " *
        "Write :a => f, where f takes whole columns, " *
        "or :a => each(f) to apply f to each element."
    @test msg(() -> where(w, :zz => each(>(1)))) ==
        "where: column not found. Got :zz. Available columns: :a, :b, :c."
    @test msg(() -> where(w, :zz)) ==
        "where: column not found. Got :zz. Available columns: :a, :b, :c."
    @test msg(() -> where(w, :a => each(x -> x))) ==
        whatif * "1 gave 3 of type Int64 in row 1" * bool_fix
    @test msg(() -> where(w, :a => each(>(0)), :a => each(x -> x))) ==
        whatif * "2 gave 3 of type Int64 in row 1" * bool_fix
    @test msg(() -> where(w, tt -> 5)) == whatif * "1 gave 5 of type Int64" * bool_fix
    @test msg(() -> where(w, tt -> nothing)) ==
        whatif * "1 gave nothing of type Nothing" * bool_fix
    @test msg(() -> where(w, tt -> Any[true, 1, false, true])) ==
        whatif * "1 gave 1 of type Int64 in row 2" * bool_fix
    @test msg(() -> where(w, :b => each(s -> "true"))) ==
        whatif * "1 gave \"true\" of type String in row 1" * bool_fix
    @test msg(() -> where(w, :a => (a -> [true, false]))) == lenmsg(2)
    @test msg(() -> where(w, :a => (a -> Bool[]))) == lenmsg(0)
    @test msg(() -> where(5, :a)) == msg(() -> where(5))
    # values are checked also in rows already dropped
    @test msg(() -> where(w, tt -> false, tt -> 5)) ==
        whatif * "2 gave 5 of type Int64" * bool_fix
    @test msg(() -> where(w, :a => each(<(0)), :a => each(x -> x))) ==
        whatif * "2 gave 3 of type Int64 in row 1" * bool_fix
    @test msg(() -> where(w, :a => (a -> [5]))) ==
        whatif * "1 gave 5 of type Int64" * bool_fix
    @test msg(() -> where(Table(; a = Int[]), :a => (a -> [true, false]))) ==
        "where: a condition has the wrong length. Got condition 1 has 2 rows, " *
        "the table has 0. Return one true or false per row, or a single one for " *
        "every row."
    check_input_unchanged(x -> where(x, :k), Table(; k = [true, false], i = [1, 2]))
end

@testset "where on random tables" begin
    rng = StableRNG(11); n = 1000
    xs = rint(rng, n, 5)
    ys = [Base.rand(rng) < 0.1 ? missing : Base.rand(rng) < 0.1 ? NaN : Base.rand(rng)
          for _ in 1:n]
    ss = [string(Base.rand(rng, 1:20)) for _ in 1:n]
    d = Table(; x = xs, y = ys, s = ss)
    keep = [(xs[i] > 2) === true && (ys[i] < 0.5) === true for i in 1:n]
    ref = Table(; x = xs[keep], y = ys[keep], s = ss[keep])
    @test same_table(where(d, :x => each(>(2)), :y => each(<(0.5))), ref)
    sp = TableOps._specs(:where, (:x => each(>(2)), :y => each(<(0.5))), (;);
        allow_unnamed = true)
    @test @inferred(TableOps._where_rows(d, sp)) == findall(keep)
end
