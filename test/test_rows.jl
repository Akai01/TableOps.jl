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

@testset "desc" begin
    @test repr(desc(:k)) == "desc(:k)" && repr(desc("k")) == "desc(:k)"
    @test repr(desc("a b")) == "desc(Symbol(\"a b\"))"
    @test !(desc(:k) isa Function) && !(desc(:k) isa Symbol)
    @test msg(() -> desc(1)) == "desc: needs a column name. Got 1. Write desc(:a)."
    @test msg(() -> desc(desc(:a))) ==
        "desc: needs a column name. Got desc(:a). Write desc(:a)."
end

@testset "arrange" begin
    nokeys = "arrange: no sort keys. Got no keys. Name at least one column, " *
        "for example arrange(t, :a) or arrange(t, desc(:a))."
    notkey(x) = "arrange: not a sort key. Got $x. Use a column name such as :a, " *
        "or desc(:a); give each key as its own argument."
    noorder(n, T) = "arrange: a sort key has no order. Got $n with element type $T. " *
        "Sort keys need one element type that isless can compare, such as numbers, " *
        "strings or dates; convert the column first."
    bygroup = "arrange: by_group needs a grouped table. Got by_group = true. " *
        "Use group_by first, or leave out by_group."
    flagmsg = "arrange: by_group must be true or false. Got 1. " *
        "Write by_group = true or by_group = false."
    um = Union{Missing,Int}
    s = Table(; k = um[2, 1, 2, 1, missing], v = ["a", "b", "c", "d", "e"])
    r = check_forms_agree(arrange, s, :k)
    @test same_table(r, Table(; k = um[1, 1, 2, 2, missing], v = ["b", "d", "a", "c", "e"]))
    @test rc(r)[1] !== rc(s)[1] && rn(r) !== rn(s)
    @test same_table(arrange(s, desc(:k)),
        Table(; k = um[2, 2, 1, 1, missing], v = ["a", "c", "b", "d", "e"]))
    @test same_table(arrange(s, "k"), r)
    @test same_table(arrange(s, desc("k")), arrange(s, desc(:k)))
    # several keys, mixed directions
    u = Table(; g = ["b", "a", "b", "a"], x = [1, 2, 0, 2], i = [1, 2, 3, 4])
    @test arrange(u, :g, desc(:x)).i == [2, 4, 1, 3]
    @test arrange(u, desc(:g), :x).i == [3, 1, 2, 4]
    @test arrange(u, :g).i == [2, 4, 1, 3] && arrange(u, desc(:g)).i == [1, 3, 2, 4]
    @test arrange(u, :x, :g).i == [3, 1, 2, 4]
    @test arrange(u, :g, :g, :x).i == arrange(u, :g, :x).i
    # NaN is after Inf and missing is last
    f = Table(; x = Union{Missing,Float64}[NaN, 1.0, Inf, -Inf, missing, 0.0],
                i = collect(1:6))
    @test arrange(f, :x).i == [4, 6, 2, 3, 1, 5]
    @test arrange(f, desc(:x)).i == [1, 3, 2, 6, 4, 5]
    @test arrange(Table(; x = [NaN, NaN, 1.0], i = [1, 2, 3]), :x).i == [3, 1, 2]
    pf = Table(; x = [1.0, NaN, -Inf, Inf, 0.0], i = [1, 2, 3, 4, 5])
    @test arrange(pf, desc(:x)).i == [2, 4, 1, 5, 3]
    # -0.0 and 0.0 are one key, so the second key decides
    z = Table(; x = [0.0, -0.0, 0.0, -0.0], y = [4, 3, 2, 1])
    @test arrange(z, :x).y == [4, 3, 2, 1]
    @test arrange(z, :x, :y).y == [1, 2, 3, 4]
    @test arrange(z, desc(:x), :y).y == [1, 2, 3, 4]
    @test signbit.(arrange(z, :x, :y).x) == [true, false, true, false]
    zm = Table(; x = Union{Missing,Float64}[0.0, -0.0, missing], y = [2, 1, 0])
    @test arrange(zm, :x, :y).y == [1, 2, 0]
    # BigFloats that differ only beyond the default precision
    ba, bb = setprecision(BigFloat, 512) do
        big(1), big(1) + big(2)^-300
    end
    @test isequal(arrange(Table(; x = [bb, ba]), :x).x, [ba, bb])
    @test isequal(arrange(Table(; x = [ba, bb]), desc(:x)).x, [bb, ba])
    # strings sort by code point, not locale
    ws = ["b", "B", "a", "ä", "10", "2"]
    @test arrange(Table(; s = ws), :s).s == ["10", "2", "B", "a", "b", "ä"]
    @test arrange(Table(; s = ws), desc(:s)).s == ["ä", "b", "a", "B", "2", "10"]
    @test arrange(Table(; b = [true, false, true], i = [1, 2, 3]), :b).i == [2, 1, 3]
    @test arrange(Table(; s = [:b, :a]), :s).s == [:a, :b]
    q = Table(; var"unit price" = [2.0, 1.0], 名前 = ["x", "y"])
    @test arrange(q, Symbol("unit price")).名前 == ["y", "x"]
    @test arrange(q, "名前").名前 == ["x", "y"]
    @test arrange(q, desc("unit price")).名前 == ["x", "y"]
    # all-missing key, no rows, no columns, one row
    mm = Table(; m = [missing, missing], i = [1, 2])
    @test arrange(mm, :m).i == [1, 2] && arrange(mm, desc(:m)).i == [1, 2]
    @test arrange(mm, :m, desc(:i)).i == [2, 1]
    @test eltype(arrange(mm, :m).m) == Missing
    am = Table(; m = Union{Missing,Int}[missing, missing], i = [1, 2])
    @test same_table(arrange(am, :m), am) && same_table(arrange(am, desc(:m)), am)
    @test arrange(am, :m, desc(:i)).i == [2, 1] && arrange(am, desc(:i), :m).i == [2, 1]
    @test eltype(arrange(am, :m).m) == Union{Missing,Int}
    fm = Table(; x = Union{Missing,Float64}[missing, missing], i = [1, 2])
    @test same_table(arrange(fm, :x), fm) && same_table(arrange(fm, desc(:x)), fm)
    @test arrange(fm, :x, desc(:i)).i == [2, 1]
    @test eltype(arrange(fm, :x).x) == Union{Missing,Float64}
    z0 = Table(; a = Int[], s = String[])
    @test same_table(arrange(z0, :a), z0) && same_table(arrange(z0, desc(:s)), z0)
    @test msg(() -> arrange(Table(), :a)) ==
        "arrange: column not found. Got :a. The table has no columns."
    @test same_table(arrange(Table(; a = [1]), :a), Table(; a = [1]))
    # input unchanged, concrete types, pipe, foreign input
    check_input_unchanged(x -> arrange(x, :g, desc(:x)), u)
    check_concrete_eltypes(arrange(s, :k))
    @test same_table(s |> arrange(:k), arrange(s, :k))
    @test same_table(arrange(:g, desc(:x))(u), arrange(u, :g, desc(:x)))
    @test same_table(arrange((k = [2, 1],), :k), Table(; k = [1, 2]))
    @test arrange(:k) isa Function && arrange(desc(:k), :v) isa Function
    @test same_table(arrange(s, :k; by_group = false), r)
    # errors
    @test msg(() -> arrange(s)) == nokeys
    @test msg(() -> arrange()) == nokeys
    @test msg(() -> arrange(5)) ==
        "arrange: the first argument is neither a table nor a sort key. Got 5. " *
        "Pass a table, or keys such as arrange(:a, desc(:b)) for the pipe form."
    @test msg(() -> arrange(s, 5)) == notkey("5")
    @test msg(() -> arrange(s, [:k, :v])) == notkey("[:k, :v]")
    @test msg(() -> arrange(:k, 5)) == notkey("5")
    @test msg(() -> arrange(s, :zz)) ==
        "arrange: column not found. Got :zz. Available columns: :k, :v."
    @test msg(() -> arrange(s, desc(:zz))) ==
        "arrange: column not found. Got :zz. Available columns: :k, :v."
    @test msg(() -> arrange(Table(; revenue = [1]), :revenu)) ==
        "arrange: column not found. Got :revenu. Did you mean :revenue?"
    @test msg(() -> arrange(Table(; c = [1 + 2im, 3 + 4im]), :c)) ==
        noorder("c", "Complex{Int64}")
    @test msg(() -> arrange(Table(; m = Any[1, "a"]), :m)) == noorder("m", "Any")
    @test msg(() -> arrange(Table(; m = Union{Int,String}[1, "a"]), :m)) ==
        noorder("m", "Union{Int64, String}")
    @test msg(() -> arrange(s, :k; by_group = true)) == bygroup
    @test msg(() -> arrange(:k; by_group = true)(s)) == bygroup
    @test msg(() -> arrange(:k; by_group = 1)) == flagmsg
    @test msg(() -> arrange(; by_group = 1)) == flagmsg
    @test msg(() -> arrange(s, :k; by_group = 1)) == flagmsg
end

@testset "arrange on random tables" begin
    # the reference is a stable merge sort with a comparator
    nz(x) = x isa AbstractFloat && x == 0 ? zero(x) : x
    function refcmp(a, b, d)
        ismissing(a) && return ismissing(b) ? 0 : 1
        ismissing(b) && return -1
        x, y = nz(a), nz(b)
        c = isless(x, y) ? -1 : isless(y, x) ? 1 : 0
        d ? -c : c
    end
    function ref_arrange(cols, descs)
        function lt(i, j)
            for (c, d) in zip(cols, descs)
                c3 = refcmp(c[i], c[j], d)
                c3 != 0 && return c3 < 0
            end
            false
        end
        sort(collect(1:length(first(cols))); lt, alg = Base.Sort.MergeSort)
    end
    rng = StableRNG(5); n = 400
    pool = Union{Missing,Float64}[-0.0, 0.0, 1.0, NaN, Inf, -Inf, missing]
    d = Table(; k1 = rint(rng, n, 4), k2 = [pool[Base.rand(rng, 1:7)] for _ in 1:n],
                k3 = [["b", "a", "B", ""][Base.rand(rng, 1:4)] for _ in 1:n],
                k4 = Union{Missing,Int}[Base.rand(rng) < 0.2 ? missing :
                                        Base.rand(rng, 1:3) for _ in 1:n],
                id = collect(1:n))
    combos = [[:k1], [:k2], [:k3, :k1], [:k4, :k2], [:k1, :k3, :k4], [:k2, :k4]]
    for ks in combos, flips in (falses(length(ks)), trues(length(ks)),
                                [isodd(i) for i in 1:length(ks)])
        spec = [f ? desc(k) : k for (k, f) in zip(ks, flips)]
        rows = ref_arrange([getproperty(d, k) for k in ks], flips)
        got = arrange(d, spec...)
        @test got.id == rows
        @test same_table(got,
            Table(; (nm => c[rows] for (nm, c) in zip(rn(d), rc(d)))...))
    end
    cols = (d.k1, d.k3, d.k2, d.k4, Float64.(filter(!ismissing, d.k2)),
            Union{Missing,Int}[missing, missing], Union{Missing,Float64}[missing, missing],
            [missing, missing])
    for c in cols
        @test @inferred(TableOps._sortpass(c, collect(1:length(c)), false)) isa Vector{Int}
        @test @inferred(TableOps._sortpass(c, collect(1:length(c)), true)) isa Vector{Int}
    end
    mi = Union{Missing,Int}[3, missing, 1]
    @test TableOps._sortpass(mi, [1, 2, 3], false) == [3, 1, 2]
    @test TableOps._sortpass(mi, [1, 2, 3], true) == [1, 3, 2]
    @test TableOps._sortpass([2, 2, 1], [2, 1, 3], false) == [3, 2, 1]
end

@testset "distinct" begin
    um = Union{Missing,Int}
    d = Table(; a = [1, 2, 1, 2, 1], b = ["x", "y", "x", "z", "x"], c = [1, 2, 3, 4, 5])
    r = check_forms_agree(distinct, d, :a, :b)
    @test same_table(r, Table(; a = [1, 2, 2], b = ["x", "y", "z"]))
    @test same_table(distinct(d, :a, :b; keep_all = true),
        Table(; a = [1, 2, 2], b = ["x", "y", "z"], c = [1, 2, 4]))
    @test same_table(distinct(d, :b, :a), Table(; b = ["x", "y", "z"], a = [1, 2, 2]))
    @test same_table(distinct(d, :a), Table(; a = [1, 2]))
    @test same_table(distinct(d, :a, :a), Table(; a = [1, 2]))
    @test same_table(distinct(d, :a; keep_all = true),
        Table(; a = [1, 2], b = ["x", "y"], c = [1, 2]))
    @test same_table(distinct(d), d) && rc(distinct(d))[1] !== rc(d)[1]
    @test rn(distinct(d)) !== rn(d)
    @test same_table(distinct(d; keep_all = true), d)
    @test same_table(distinct(d, startswith("a")), Table(; a = [1, 2]))
    @test same_table(distinct(d, ["b", "a"]), distinct(d, :b, :a))
    @test same_table(distinct(d, except(:c)), distinct(d, :a, :b))
    @test same_table(distinct(d, of_type(String)), Table(; b = ["x", "y", "z"]))
    # missing is one value, NaN equals NaN, -0.0 equals 0.0
    @test same_table(distinct(Table(; x = um[missing, 1, missing, 1])),
        Table(; x = um[missing, 1]))
    @test same_table(distinct(Table(; x = [NaN, NaN, 1.0, NaN])), Table(; x = [NaN, 1.0]))
    z = distinct(Table(; x = [0.0, -0.0, 0.0]))
    @test z.x == [0.0] && !signbit(z.x[1])
    z = distinct(Table(; x = [-0.0, 0.0]))
    @test z.x == [0.0] && signbit(z.x[1])
    z = distinct(Table(; x = Float32[-0.0, 0.0, 1.0]))
    @test z.x == Float32[0.0, 1.0] && z.x isa Vector{Float32} && signbit(z.x[1])
    z = distinct(Table(; x = Union{Missing,Float64}[0.0, -0.0, missing, -0.0]))
    @test isequal(z.x, Union{Missing,Float64}[0.0, missing]) && !signbit(z.x[1])
    z = distinct(Table(; x = Any[-0.0, 0.0, 0.0f0, 1, 1.0, missing, missing]))
    @test isequal(z.x, Any[-0.0, 1, missing]) && z.x isa Vector{Any} && signbit(z.x[1])
    @test z.x[2] isa Int
    z = distinct(Table(; x = [-0.0, 0.0, 1.0], y = [1, 1, 2]))
    @test z.x == [0.0, 1.0] && signbit(z.x[1]) && z.y == [1, 2]
    z = distinct(Table(; x = [0.0, -0.0, 1.0], y = [1, 1, 2]), :y; keep_all = true)
    @test z.x == [0.0, 1.0] && !signbit(z.x[1])
    @test same_table(distinct(Table(; x = [NaN, -NaN, NaN, Inf, -Inf, Inf])),
        Table(; x = [NaN, Inf, -Inf]))
    @test same_table(distinct(Table(; x = [missing, missing], y = [1, 1])),
        Table(; x = Missing[missing], y = [1]))
    @test same_table(distinct(Table(; x = um[missing, missing, missing], y = [1, 1, 2])),
        Table(; x = um[missing, missing], y = [1, 2]))
    @test same_table(distinct(Table(; x = [missing, missing])), Table(; x = [missing]))
    # BigFloats that differ only beyond the default precision
    ba, bb = setprecision(BigFloat, 512) do
        big(1), big(1) + big(2)^-300
    end
    @test ba != bb && precision(BigFloat) < 512
    zb = distinct(Table(; x = [ba, bb, ba]))
    @test nrow(zb) == 2 && isequal(zb.x, [ba, bb])
    @test nrow(distinct(Table(; x = [big(-0.0), big(0.0)]))) == 1
    @test !signbit(distinct(Table(; x = [big(0.0), big(-0.0)])).x[1])
    # strings, Unicode and space names, edge sizes
    u = Table(; var"unit price" = [1.0, 1.0, 2.0], 名前 = ["x", "x", "y"])
    @test same_table(distinct(u),
        Table(; var"unit price" = [1.0, 2.0], 名前 = ["x", "y"]))
    @test same_table(distinct(u, "名前"), Table(; 名前 = ["x", "y"]))
    z0 = Table(; a = Int[], s = String[])
    @test same_table(distinct(z0), z0)
    @test same_table(distinct(z0, :s), Table(; s = String[]))
    @test same_table(distinct(Table()), Table())
    e = Table()
    @test distinct(e) !== e && same_table(distinct(e), Table())
    @test distinct(e; keep_all = true) !== e && ncol(distinct(e; keep_all = true)) == 0
    @test msg(() -> distinct(e, :a)) ==
        "distinct: column not found. Got :a. The table has no columns."
    @test msg(() -> distinct(e, startswith("a"))) ==
        "distinct: no columns picked. Got an empty selection. Name at least one " *
        "column, or call distinct(t) for all of them."
    @test same_table(distinct(d, :c, :a; keep_all = true),
        Table(; a = [1, 2, 1, 2, 1], b = ["x", "y", "x", "z", "x"], c = [1, 2, 3, 4, 5]))
    @test same_table(distinct(d, :b, :a; keep_all = true),
        Table(; a = [1, 2, 2], b = ["x", "y", "z"], c = [1, 2, 4]))
    @test same_table(distinct(Table(; a = [1])), Table(; a = [1]))
    # forms, input, types, pipe
    check_input_unchanged(x -> distinct(x, :a), d)
    check_input_unchanged(x -> distinct(x, :a; keep_all = true), d)
    check_concrete_eltypes(distinct(d, :a, :b))
    @test same_table(d |> distinct(:a), distinct(d, :a))
    @test same_table(distinct(:a; keep_all = true)(d), distinct(d, :a; keep_all = true))
    @test same_table(distinct()(d), distinct(d)) && distinct(; keep_all = true) isa Function
    @test same_table(distinct((a = [1, 1],)), Table(; a = [1]))
    @test @inferred(TableOps._codes([5, 6, 5])) == ([1, 2, 1], 2)
    @test @inferred(TableOps._codes(["a", "b", "a"])) == ([1, 2, 1], 2)
    @test TableOps._codes(Union{Missing,Float64}[NaN, missing, NaN, -0.0, 0.0]) ==
        ([1, 2, 1, 3, 3], 3)
    @test @inferred(TableOps._codes(Union{Missing,Float64}[NaN, missing, NaN])) ==
        ([1, 2, 1], 2)
    @test @inferred(TableOps._codes(Float32[-0.0, 0.0, 1.0])) == ([1, 1, 2], 2)
    @test @inferred(TableOps._codes(Any[-0.0, 0.0, missing, 1, 1.0])) ==
        ([1, 1, 2, 3, 3], 3)
    @test TableOps._codes(Int[]) == (Int[], 0)
    @test TableOps._codes([missing, missing]) == ([1, 1], 1)
    @test @inferred(TableOps._combine([1, 2, 1], [1, 1, 2], 2)) == ([1, 2, 3], 3)
    @test TableOps._combine([1, 1, 2, 2], [1, 1, 1, 1], 1) == ([1, 1, 2, 2], 2)
    # the pairs (1, 23) and (12, 3) must stay apart
    @test @inferred(TableOps._combine([1, 12, 1, 12], [23, 3, 23, 3], 23)) ==
        ([1, 2, 1, 2], 2)
    @test TableOps._combine([1, 2, 1], [1, 2, 3], 3) == ([1, 2, 3], 3)
    @test TableOps._combine([2, 1, 2], [1, 3, 1], 3) == ([1, 2, 1], 2)
    @test @inferred(TableOps._firstrows(AbstractVector[[1, 1, 2], ["a", "a", "b"]])) ==
        [1, 3]
    @test @inferred(TableOps._firstrows(AbstractVector[Int[]])) == Int[]
    # errors
    @test msg(() -> distinct(d, startswith("zz"))) ==
        "distinct: no columns picked. Got an empty selection. Name at least one " *
        "column, or call distinct(t) for all of them."
    @test msg(() -> distinct(d, except(:a, :b, :c))) ==
        msg(() -> distinct(d, startswith("zz")))
    @test msg(() -> distinct(d, :zz)) ==
        "distinct: column not found. Got :zz. Available columns: :a, :b, :c."
    @test msg(() -> distinct(Table(; revenue = [1]), :revenu)) ==
        "distinct: column not found. Got :revenu. Did you mean :revenue?"
    flagmsg = "distinct: keep_all must be true or false. Got 1. " *
        "Write keep_all = true or keep_all = false."
    @test msg(() -> distinct(d; keep_all = 1)) == flagmsg
    @test msg(() -> distinct(:a; keep_all = 1)) == flagmsg
    @test msg(() -> distinct(; keep_all = 1)) == flagmsg
    @test msg(() -> distinct(d, :a; keep_all = 1)) == flagmsg
    notpicker(x) = "distinct: not a column picker. Got $x. Use a name, a vector of " *
        "names, a predicate such as startswith(\"a\") or contains(r\"^q\"), " *
        "everything(), of_type(T) or except(...)."
    @test msg(() -> distinct(d, 5)) == notpicker(5)
    @test msg(() -> distinct(:a, 5)) == notpicker(5)
    firstarg = "distinct: the first argument is neither a table nor a column picker. " *
        "Got 5. Pass a table, or pickers such as distinct(:a, :b) for the pipe form."
    @test msg(() -> distinct(5)) == firstarg
    @test msg(() -> distinct(5, :a)) == firstarg
end

@testset "distinct on random tables" begin
    # reference: a loop and a Dict on tuples, -0.0 mapped to 0.0
    rz(x) = x isa AbstractFloat && x == 0 ? zero(x) : x
    function ref_distinct(cols)
        seen = Dict{Any,Bool}(); rows = Int[]
        for i in 1:length(cols[1])
            key = Tuple(rz(c[i]) for c in cols)
            haskey(seen, key) || (seen[key] = true; push!(rows, i))
        end
        rows
    end
    rng = StableRNG(21); n = 600
    pool = Union{Missing,Float64}[-0.0, 0.0, 1.0, NaN, missing]
    cols = AbstractVector[rint(rng, n, 5), [pool[Base.rand(rng, 1:5)] for _ in 1:n],
        [["a", "b", "c"][Base.rand(rng, 1:3)] for _ in 1:n],
        Union{Missing,Int}[Base.rand(rng) < 0.3 ? missing : Base.rand(rng, 1:2)
                           for _ in 1:n],
        Float32[[-0.0f0, 0.0f0, 2.0f0][Base.rand(rng, 1:3)] for _ in 1:n],
        Any[[-0.0, 0.0, missing, NaN, 1][Base.rand(rng, 1:5)] for _ in 1:n]]
    for sel in ([1], [2], [3], [4], [5], [6], [1, 2], [2, 3, 4], [1, 2, 3, 4], [5, 6],
                [1, 2, 3, 4, 5, 6])
        @test TableOps._firstrows(cols[sel]) == ref_distinct(cols[sel])
    end
    big = rint(rng, 20_000, 50_000)
    @test TableOps._firstrows(AbstractVector[big]) == ref_distinct([big])
    d = Table(; k1 = cols[1], k2 = cols[2], k3 = cols[3], k4 = cols[4], id = collect(1:n))
    for ks in ([:k1], [:k2], [:k3, :k4], [:k1, :k2, :k3])
        rows = ref_distinct([getproperty(d, k) for k in ks])
        @test distinct(d, ks...; keep_all = true).id == rows
        @test same_table(distinct(d, ks...),
            Table(; (k => getproperty(d, k)[rows] for k in ks)...))
    end
end

@testset "slice, slice_head, slice_tail" begin
    d = Table(; a = [10, 20, 30, 40, 50], b = ["p", "q", "r", "s", "t"])
    empty_d = Table(; a = Int[], b = String[])
    s1(got) = "slice: row numbers must be integers. Got $got. " *
        "Pass integers such as slice(t, 2:3) or slice(t, [1, 3]); " *
        "use where to keep rows by a Bool condition."
    s2(got) = "slice: row number out of range. Got $got. " *
        "The table has 5 rows, numbered 1 to 5."
    notable(v) = "$v: input is not a Tables.jl table. Got Int64. " *
        "Pass a NamedTuple of vectors, a vector of NamedTuples or another " *
        "Tables.jl table; collect a generator first: Table(collect(x))."
    n1(v, got) = "$v: n must be a whole number of 0 or more. Got $got. " *
        "Write, for example, n = 3."
    @test same_table(check_forms_agree(slice, d, 2:3),
        Table(; a = [20, 30], b = ["q", "r"]))
    @test slice(d, [5, 1, 1]).a == [50, 10, 10]
    @test same_table(slice(d, 2), Table(; a = [20], b = ["q"]))
    @test slice(d, 1:2:5).a == [10, 30, 50] && slice(d, 5:-1:4).a == [50, 40]
    @test slice(d, UInt8[2, 3]).a == [20, 30]
    @test slice(d, Int16(1):Int16(2)).a == [10, 20]
    @test slice(d, Int32[3, 1]).a == [30, 10]
    @test slice(d, UInt8[0x02]).a == [20]
    @test slice(d, Any[2, UInt8(3)]).a == [20, 30]
    @test slice(d, Base.IdentityUnitRange(2:3)).a == [20, 30]
    @test slice(d, view([1, 2, 3, 4], 2:3)).a == [20, 30]
    @test slice(d, Base.IdentityUnitRange(Int32(2):Int32(3))).a == [20, 30]
    @test slice(d, Base.IdentityUnitRange(UInt8(2):UInt8(3))).a == [20, 30]
    v = Any[1, 2]
    p = slice(v)
    v[1] = true
    @test p(d).a == [10, 20]
    v = Any[1, 2]
    p = slice(v)
    v[1] = 3
    @test p(d).a == [10, 20]
    w = [1, 2]
    p = slice(w)
    w[1] = 99
    @test p(d).a == [10, 20]
    @test same_table(slice(d, Int[]), empty_d)
    @test same_table(slice(d, 1:0), empty_d)
    @test same_table(slice(d, Any[]), empty_d)
    @test same_table(slice(d, 1:5), d) && rc(slice(d, 1:5))[1] !== rc(d)[1]
    @test same_table(slice(Table(), 1:0), Table())
    @test same_table(slice(Table(; a = [7]), 1), Table(; a = [7]))
    @test slice(Table(; var"unit price" = [1.0, 2.0]), [2]).var"unit price" == [2.0]
    @test same_table(slice(Table(; m = [missing, missing]), [2]),
        Table(; m = Missing[missing]))
    check_input_unchanged(x -> slice(x, [3, 3]), d)
    check_concrete_eltypes(slice(d, 2:3))
    @test same_table(d |> slice([2, 3]), slice(d, [2, 3])) && slice(2:3) isa Function
    @test same_table(slice((a = [1, 2],), 2), Table(; a = [2]))
    @test @inferred(TableOps._rownumbers(2:3)) === 2:3
    @test @inferred(TableOps._rownumbers([2, 3])) == [2, 3]
    @test @inferred(TableOps._asint([2, 3])) == [2, 3]
    @test @inferred(TableOps._asint(Int32[2, 3])) isa Vector{Int}
    @test @inferred(TableOps._checkrows(2:3, 5)) === nothing
    @test @inferred(TableOps._slice(d, 2:3)) isa Table
    @test msg(() -> slice(d, 6)) == s2(6)
    @test msg(() -> slice(d, 0)) == s2(0)
    @test msg(() -> slice(d, [1, -1, 9])) == s2(-1)
    @test msg(() -> slice(d, 4:7)) == s2(6)
    @test msg(() -> slice(d, UInt8[9])) == s2("0x09")
    @test msg(() -> slice(d, Base.IdentityUnitRange(4:7))) == s2(6)
    @test msg(() -> slice(d, [big(10)^30])) == s2(big(10)^30)
    @test msg(() -> slice(d, Any[1, big(10)^30])) == s2(big(10)^30)
    @test msg(() -> slice(d, -big(10)^30)) == s2(-big(10)^30)
    @test msg(() -> slice(d, typemax(UInt))) == s2("0xffffffffffffffff")
    @test msg(() -> slice(d, typemax(Int))) == s2(typemax(Int))
    @test msg(() -> slice(Table(; a = Int[]), 1)) ==
        "slice: row number out of range. Got 1. The table has no rows."
    @test msg(() -> slice(Table(), 1)) ==
        "slice: row number out of range. Got 1. The table has no rows."
    @test msg(() -> slice(2:9)(d)) == msg(() -> slice(d, 2:9))
    @test msg(() -> slice(2:9)(d)) == s2(6)
    @test msg(() -> slice(d, [1.5])) == s1("[1.5]")
    @test msg(() -> slice([1.5])) == s1("[1.5]")
    @test msg(() -> slice(d, [true, false, true, false, true])) ==
        s1("Bool[1, 0, 1, 0, 1]")
    @test msg(() -> slice(d, trues(5))) == s1("Bool[1, 1, 1, 1, 1]")
    @test msg(() -> slice(d, true)) == s1("true")
    @test msg(() -> slice(d, "a")) == s1("\"a\"")
    @test msg(() -> slice(d, 1.0)) == s1("1.0")
    @test msg(() -> slice(d, [1, missing])) == s1("Union{Missing, Int64}[1, missing]")
    @test msg(() -> slice(d, Any[1, true])) == s1("Any[1, true]")
    @test msg(() -> slice(d, Integer[1, true])) == s1("Integer[1, true]")
    @test msg(() -> slice(d, Union{Int,Bool}[1, true])) ==
        s1("Union{Bool, Int64}[1, true]")
    @test msg(() -> slice(d, Union{Int,Bool}[true])) == s1("Union{Bool, Int64}[true]")
    @test slice(d, Integer[2, 3]).a == [20, 30]
    @test slice(d, Union{Int,Bool}[2, 3]).a == [20, 30]
    @test slice(d, Union{Missing,Int}[2, 3]).a == [20, 30]
    @test msg(() -> slice(d, 1:6)) == s2(6)
    @test @elapsed(msg(() -> slice(d, 1:typemax(Int)))) < 1
    @test msg(() -> slice(d, 1:typemax(Int))) == s2(6)
    @test msg(() -> slice(d, typemin(Int):5)) == s2(typemin(Int))
    um = Table(; m = Union{Missing,Int}[1, missing, 3], 名前 = ["x", "y", "z"])
    @test same_table(slice(um, [2, 3]),
        Table(; m = Union{Missing,Int}[missing, 3], 名前 = ["y", "z"]))
    @test same_table(slice_head(um; n = 2),
        Table(; m = Union{Missing,Int}[1, missing], 名前 = ["x", "y"]))
    @test same_table(slice_tail(um; n = 0),
        Table(; m = Union{Missing,Int}[], 名前 = String[]))
    @test msg(() -> slice(d)) == s1(TableOps._fmt_value(d))
    @test msg(() -> slice(5, 1)) == notable(:slice)

    h = check_forms_agree(slice_head, d; n = 2)
    @test same_table(h, Table(; a = [10, 20], b = ["p", "q"]))
    @test same_table(slice_head(d; n = 0), empty_d)
    @test same_table(slice_head(d; n = 5), d) && same_table(slice_head(d; n = 99), d)
    @test same_table(slice_head(d; n = typemax(Int)), d)
    @test rc(slice_head(d; n = 99))[1] !== rc(d)[1]
    @test same_table(slice_head(d; n = typemax(UInt)), d)
    @test same_table(slice_head(d; n = big(10)^30), d)
    @test same_table(slice_tail(d; n = big(10)^30), d)
    @test same_table(slice_tail(d; n = typemax(UInt)), d)
    @test same_table(slice_head(d; n = UInt8(1)), Table(; a = [10], b = ["p"]))
    @test same_table(check_forms_agree(slice_tail, d; n = 2),
        Table(; a = [40, 50], b = ["s", "t"]))
    @test same_table(slice_tail(d; n = 0), empty_d)
    @test same_table(slice_tail(d; n = 99), d) && slice_tail(d; n = 5).a == d.a
    @test rc(slice_tail(d; n = 99))[1] !== rc(d)[1]
    @test slice_head(Table(; a = Int[]); n = 3).a == Int[]
    @test ncol(slice_tail(Table(); n = 2)) == 0
    @test slice_head(Table(; a = [1]); n = 1).a == [1]
    @test slice_tail(Table(; a = [1]); n = 3).a == [1]
    @test same_table(d |> slice_head(; n = 1), slice_head(d; n = 1))
    @test slice_head(; n = 1) isa Function && slice_tail(; n = 1) isa Function
    check_input_unchanged(x -> slice_tail(x; n = 2), d)
    check_input_unchanged(x -> slice_head(x; n = 2), d)
    check_concrete_eltypes(slice_head(d; n = 2))
    check_concrete_eltypes(slice_tail(d; n = 2))
    @test @inferred(TableOps._checkn(:slice_head, 3)) === 3
    @test TableOps._checkn(:slice_head, typemax(UInt)) === typemax(Int)
    @test TableOps._checkn(:slice_head, big(10)^30) === typemax(Int)
    @test @inferred(TableOps._slice_head(d, 2)) isa Table
    @test @inferred(TableOps._slice_tail(d, 2)) isa Table
    for v in (slice_head, slice_tail)
        name = nameof(v)
        @test msg(() -> v(d; n = -1)) == n1(name, -1)
        @test msg(() -> v(d; n = -big(10)^30)) == n1(name, -big(10)^30)
        @test msg(() -> v(d; n = 1.5)) == n1(name, 1.5)
        @test msg(() -> v(d; n = true)) == n1(name, true)
        @test msg(() -> v(d; n = 2.0)) == n1(name, 2.0)
        @test msg(() -> v(d; n = missing)) == n1(name, missing)
        @test msg(() -> v(d; n = "2")) == n1(name, "\"2\"")
        @test msg(() -> v(d)) == "$name: n is required. Got no n. " *
            "Write, for example, n = 3."
        @test msg(() -> v(; n = nothing)) == msg(() -> v(d))
        @test msg(() -> v(; n = -1)) == n1(name, -1)
        @test msg(() -> v(5; n = 1)) == notable(name)
    end
end
