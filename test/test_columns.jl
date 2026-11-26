using Test, TableOps
isdefined(@__MODULE__, :same_table) || include("checks.jl")

@testset "checks" begin
    a, b = Table(; x = Int[]), Table(; x = Float64[])
    @test isequal(a, b)                              # Base semantics (Phase 1 note)
    @test !same_table(a, b)                          # element types are compared
    @test same_table(a, copy(a))
    @test !same_table(Table(; x = [1], y = [2]), Table(; y = [2], x = [1]))
    @test !same_table(Table(; x = [1]), Table(; x = [2]))
    @test !same_table(Table(; x = [1]), Table(; x = [1.0]))      # == but not same type
    @test same_table(Table(; x = [missing, 1.0]), Table(; x = [missing, 1.0]))
    @test same_table(Table(; x = [NaN]), Table(; x = [NaN]))
    @test same_table(Table(), Table())
    @test !same_table(Table(; x = [1]), Table(; x = [1], y = [2]))

    t = Table(; x = [1, 2], y = ["a", "b"])
    s = snapshot(t)
    @test unchanged(t, s)
    getfield(t, :columns)[1][1] = 9                  # in place
    @test !unchanged(t, s)
    t2 = Table(; x = [1, 2]); s2 = snapshot(t2)
    getfield(t2, :columns)[1] = [1, 2]               # replaced by an equal vector
    @test !unchanged(t2, s2)
    t3 = Table(; x = [1]); s3 = snapshot(t3); push!(getfield(t3, :names), :z)
    @test !unchanged(t3, s3)
    t4 = Table(; x = [1], y = [2]); s4 = snapshot(t4)
    getfield(t4, :lookup)[:x] = 2                    # lookup edited alone
    @test !unchanged(t4, s4)

    for T in (Int, String, Union{Missing,Int}, Missing, Vector{Int}, Float64)
        @test is_concrete_eltype(T)
    end
    for T in (Any, Real, Union{Int,String}, Union{Missing,Real}, Number,
              Union{Missing,Int,String})
        @test !is_concrete_eltype(T)
    end
    # a stand-in verb with both forms
    fake(t, c) = TableOps._newtable([c], AbstractVector[[1, 2]])
    fake(c) = t -> fake(t, c)
    @test same_table(check_forms_agree(fake, t, :q), Table(; q = [1, 2]))
    @test check_input_unchanged(x -> x, t) === t
    rows = [(a = 1, b = 2), (a = 3, b = 4)]      # Table(rows) makes new columns
    @test check_input_unchanged(x -> x, rows) isa Table
    check_concrete_eltypes(t)
end

t = Table(; a = [1, 2, 3], b = ["x", "y", "z"], c = [1.5, missing, 3.5])
cn(x) = getfield(x, :names)
cc(x) = getfield(x, :columns)
struct LastColumn <: AbstractSelector end
TableOps.resolve(::LastColumn, t::Table) = [last(names(t))]

@testset "select" begin
    m1 = "select: not a column picker. Got 5. Use a name, a vector of names, " *
        "a predicate such as startswith(\"a\") or contains(r\"^q\"), everything(), " *
        "of_type(T) or except(...)."
    s1 = "select: no columns picked. Got an empty selection. " *
        "Name at least one column, or use everything() for all of them."
    r = check_forms_agree(select, t, :c, :a)
    @test cn(r) == [:c, :a]
    @test cc(r)[1] === cc(t)[3] && cc(r)[2] === cc(t)[1]                # shared
    @test cn(select(t, :a, "a", :b)) == [:a, :b]                         # once
    @test cn(select(t, startswith("b"), everything())) == [:b, :a, :c]
    @test cn(select(t, except(:b))) == [:a, :c]
    @test cn(select(t, of_type(Real))) == [:a, :c]
    @test cn(select(t, [:b, :a])) == [:b, :a]
    @test cn(select(t, LastColumn())) == [:c]
    @test cn(select(t; x = :a)) == [:x] && cc(select(t; x = :a))[1] === cc(t)[1]
    @test cn(select(t, :c; x = :a, y = "b")) == [:c, :x, :y]             # renames last
    s = select(t, :a; a2 = :a)
    @test cn(s) == [:a, :a2] && cc(s)[1] === cc(s)[2]                    # shared
    @test cn(select(t; a = :a)) == [:a]
    @test cn(select(t; b = :a, a = :b)) == [:b, :a]
    check_input_unchanged(x -> select(x, :a, :c), t)
    check_concrete_eltypes(select(t, :a, :c))
    @test same_table(t |> select(:a, :c), select(t, :a, :c))
    @test same_table(select(:a; z = :c)(t), select(t, :a; z = :c))
    @test @inferred(TableOps._select(t, (:c, :a), (;))) isa Table
    # input kinds
    @test cn(select((a = [1], b = [2]), :b)) == [:b]
    @test cn(select([(a = 1, b = 2)], :b)) == [:b]
    # names make a picker; an empty row table is a table
    @test select([:a, :b]) isa Function && select(Symbol[]) isa Function
    @test msg(() -> select(NamedTuple[], :a)) ==
        "select: column not found. Got :a. The table has no columns."
    # edge cases
    z = Table(; a = Int[], b = String[])
    @test eltype(cc(select(z, :b))[1]) == String && nrow(select(z, :b)) == 0
    t1 = Table(; a = [1]); @test cc(select(t1, :a))[1] === cc(t1)[1]
    m = Table(; m = [missing, missing], n = [NaN, 1.0])
    @test eltype(cc(select(m, :m))[1]) == Missing
    u = Table(; var"unit price" = [1.0], 名前 = ["x"])
    @test cn(select(u, Symbol("unit price"))) == [Symbol("unit price")]
    @test cn(select(u, "名前", contains("price"))) == [:名前, Symbol("unit price")]
    @test cn(select(u; var"new name" = Symbol("unit price"))) == [Symbol("new name")]
    @test cn(select(u; renamed = "名前")) == [:renamed]
    # errors
    @test msg(() -> select(t, startswith("zz"))) == s1
    @test msg(() -> select(t)) == s1
    @test msg(() -> select()) == s1
    @test msg(() -> select(Table(), :a)) ==
        "select: column not found. Got :a. The table has no columns."
    @test msg(() -> select(t, :zz)) ==
        "select: column not found. Got :zz. Available columns: :a, :b, :c."
    @test msg(() -> select(Table(; revenue = [1]), :revenu)) ==
        "select: column not found. Got :revenu. Did you mean :revenue?"
    @test msg(() -> select(t; x = :zz)) == msg(() -> select(t, :zz))
    @test msg(() -> select(t; x = 1)) ==
        "select: the value of x must be a column name. Got 1. Write select(t; new = :old)."
    @test msg(() -> select(t, :a; a = :b)) ==
        "select: two columns would have the same name. Got :a. " *
        "Rename one of them or leave it out."
    @test msg(() -> select(t, 5)) == m1
    @test msg(() -> select(5, :a)) ==
        "select: the first argument is neither a table nor a column picker. Got 5. " *
        "Pass a table, or pickers such as select(:a, :b) for the pipe form."
    @test msg(() -> select(:a, 5)) == m1
    @test msg(() -> select(t, except(5))) == m1
end

@testset "rename" begin
    r = check_forms_agree(rename, t; x = :a)
    @test cn(r) == [:x, :b, :c] && cc(r)[1] === cc(t)[1]
    s = rename(t; a = :b, b = :a)                                       # swap
    @test cn(s) == [:b, :a, :c] && cc(s)[1] === cc(t)[1] && cc(s)[2] === cc(t)[2]
    @test cn(rename(t; x = "a")) == [:x, :b, :c]
    @test cn(rename(t; a = :a)) == cn(t)
    @test same_table(rename(t), t)
    @test cn(rename(Table(; var"my col" = [1]); ok = Symbol("my col"))) == [:ok]
    @test cn(rename(Table(; a = [1]); var"new name" = :a)) == [Symbol("new name")]
    @test cn(rename((a = [1], b = [2]); z = :b)) == [:a, :z]            # NamedTuple in
    check_input_unchanged(x -> rename(x; x = :a), t)
    check_concrete_eltypes(rename(t; x = :c))
    @test rename(; x = :a) isa Function &&
        same_table(t |> rename(; x = :a), rename(t; x = :a))
    z = Table(; a = Int[])
    @test eltype(cc(rename(z; q = :a))[1]) == Int && nrow(rename(z; q = :a)) == 0
    for r in (rename(t; x = :a), rename(t))                        # nothing shared
        @test getfield(r, :names) !== getfield(t, :names)
        @test getfield(r, :lookup) !== getfield(t, :lookup)
    end
    @test ncol(rename(Table())) == 0
    @test msg(() -> rename(Table(); x = :a)) ==
        "rename: column not found. Got :a. The table has no columns."
    @test msg(() -> rename(t; var"x y" = :a, z = :a)) ==
        "rename: a column cannot get two new names. Got :a. Rename it once, " *
        "then add a copy: mutate(rename(t; var\"x y\" = :a); z = Symbol(\"x y\"))."
    @test msg(() -> rename(t; x = :zz)) ==
        "rename: column not found. Got :zz. Available columns: :a, :b, :c."
    @test msg(() -> rename(t; b = :a)) ==
        "rename: two columns would have the same name. Got :b. " *
        "Rename the other one too, or drop it first with select."
    @test msg(() -> rename(t; x = :a, y = :a)) ==
        "rename: a column cannot get two new names. Got :a. Rename it once, " *
        "then add a copy: mutate(rename(t; x = :a); y = :x)."
    @test msg(() -> rename(t, :a => :x)) ==
        "rename: renames are keywords. Got :a => :x. Write rename(t; new = :old)."
    @test msg(() -> rename(:a => :x)) == msg(() -> rename(t, :a => :x))
    @test msg(() -> rename(t; x = 1)) ==
        "rename: the value of x must be a column name. Got 1. " *
        "Write rename(t; new = :old)."
    @test startswith(msg(() -> rename(5; x = :a)),
        "rename: input is not a Tables.jl table. Got Int64.")
end

@testset "relocate" begin
    t4 = Table(; a = [1], b = [2], c = [3], d = [4])
    @test cn(relocate(t4, :c)) == [:c, :a, :b, :d]
    @test cn(relocate(t4, :c, :a)) == [:c, :a, :b, :d]                  # pick order
    @test cn(relocate(t4, :a; after = :c)) == [:b, :c, :a, :d]
    @test cn(relocate(t4, :d; before = :b)) == [:a, :d, :b, :c]
    @test cn(relocate(t4, :a; after = :d)) == [:b, :c, :d, :a]
    @test cn(relocate(t4, :d; before = :a)) == [:d, :a, :b, :c]
    @test cn(relocate(t4, startswith("c"), :a; after = :d)) == [:b, :d, :c, :a]
    @test cn(relocate(t4, :a; before = "c")) == [:b, :a, :c, :d]
    @test cn(relocate(t4, startswith("zz"))) == [:a, :b, :c, :d]         # nothing to move
    @test cn(relocate(t4)) == [:a, :b, :c, :d]
    r = check_forms_agree(relocate, t4, :c; after = :d)
    @test cn(r) == [:a, :b, :d, :c] && cc(r)[4] === cc(t4)[3]            # shared
    @test same_table(relocate(:c)(t4), relocate(t4, :c))
    @test same_table(relocate(; before = :b)(t4), t4)
    check_input_unchanged(x -> relocate(x, :c), t4)
    check_concrete_eltypes(relocate(t, :c))
    z = Table(; a = Int[], b = String[]); @test cn(relocate(z, :b)) == [:b, :a]
    @test cn(relocate(Table(; var"unit price" = [1], 名前 = ["x"]), "名前")) ==
        [:名前, Symbol("unit price")]
    for r in (relocate(t4, :c), relocate(t4))                       # nothing shared
        @test getfield(r, :names) !== getfield(t4, :names)
        @test getfield(r, :lookup) !== getfield(t4, :lookup)
    end
    @test ncol(relocate(Table())) == 0
    @test msg(() -> relocate(Table(), :a)) ==
        "relocate: column not found. Got :a. The table has no columns."
    @test msg(() -> relocate(t4, :a; before = :b, after = :c)) ==
        "relocate: before and after cannot both be given. " *
        "Got before = :b, after = :c. Use only one of them."
    @test msg(() -> relocate(t4, :a, :b; after = :a)) ==
        "relocate: the anchor is also one of the columns to move. Got :a. " *
        "Choose an anchor that stays where it is."
    @test msg(() -> relocate(t4, :a; after = :zz)) ==
        "relocate: column not found. Got :zz. Available columns: :a, :b, :c, :d."
    @test msg(() -> relocate(t4, :a; after = 1)) ==
        "relocate: the anchor must be a column name. Got 1. " *
        "Write before = :a or after = :a."
    @test msg(() -> relocate(t4, :zz)) ==
        "relocate: column not found. Got :zz. Available columns: :a, :b, :c, :d."
    @test msg(() -> relocate(t4, :a, 5)) ==
        "relocate: not a column picker. Got 5. Use a name, a vector of names, " *
        "a predicate such as startswith(\"a\") or contains(r\"^q\"), everything(), " *
        "of_type(T) or except(...)."
    @test msg(() -> relocate(t4, [1])) ==
        "relocate: a vector of columns holds only names. Got 1. " *
        "Put Symbols or Strings in the vector; " *
        "give a predicate or picker as its own argument."
    @test msg(() -> relocate(5, :a)) ==
        "relocate: the first argument is neither a table nor a column picker. Got 5. " *
        "Pass a table, or pickers such as relocate(:a; after = :b) for the pipe form."
end

@testset "pull" begin
    @test pull(t, :a) === cc(t)[1]                                       # no copy
    @test pull(t, "b") == ["x", "y", "z"]
    @test isequal(pull(t, :c), [1.5, missing, 3.5])
    @test pull(:a)(t) === pull(t, :a) && (t |> pull(:c)) === cc(t)[3]
    v = [1, 2]; @test pull((a = v,), :a) === v
    @test pull(Table(; a = Int[]), :a) == Int[]
    @test pull(Table(; var"unit price" = [1.0]), Symbol("unit price")) == [1.0]
    @test eltype(pull(Table(; m = [missing]), :m)) == Missing
    @test (@inferred AbstractVector TableOps._pull(t, :a)) === cc(t)[1]
    @test msg(() -> pull(t, :zz)) ==
        "pull: column not found. Got :zz. Available columns: :a, :b, :c."
    @test msg(() -> pull(t, 1)) ==
        "pull: needs a column name. Got 1. " *
        "Write pull(t, :a); to use a position write pull(t, names(t)[1])."
    @test msg(() -> pull(1)) == msg(() -> pull(t, 1))
    @test startswith(msg(() -> pull(5, :a)),
        "pull: input is not a Tables.jl table. Got Int64.")
end

struct FakeTable <: TableOps.AbstractTable end
TableOps.select(::FakeTable, picks...; kw...) = :select
TableOps.rename(::FakeTable; kw...) = :rename
TableOps.relocate(::FakeTable, picks...; kw...) = :relocate
TableOps._mutate(::FakeTable, specs) = :mutate
struct NoMutateTable <: TableOps.AbstractTable end

@testset "pipe forms check early and call the public verb" begin
    m2 = "select: a vector of columns holds only names. Got 1. " *
        "Put Symbols or Strings in the vector; " *
        "give a predicate or picker as its own argument."
    sv = "select: the value of x must be a column name. Got 1. " *
        "Write select(t; new = :old)."
    @test msg(() -> select(Any[(a = 1, b = 2)], :a)) ==
        "select: the first argument is neither a table nor a column picker. " *
        "Got Any[(a = 1, b = 2)]. " *
        "Pass a table, or pickers such as select(:a, :b) for the pipe form."
    @test msg(() -> relocate(Any[(a = 1,)], :a)) ==
        "relocate: the first argument is neither a table nor a column picker. " *
        "Got Any[(a = 1,)]. " *
        "Pass a table, or pickers such as relocate(:a; after = :b) for the pipe form."
    @test msg(() -> select(:a, [1])) == m2
    @test msg(() -> relocate(:a, [1])) == replace(m2, "select" => "relocate")
    @test select(Any[:a, "b"]) isa Function && select(Any[], :a) isa Function
    @test same_table(select(Any[:a, "b"])(t), select(t, :a, :b))
    @test msg(() -> select(:a; x = 1)) == sv
    @test msg(() -> select(; x = 1)) == sv
    @test msg(() -> rename(; x = 1)) ==
        "rename: the value of x must be a column name. Got 1. " *
        "Write rename(t; new = :old)."
    @test msg(() -> relocate(:a; before = :b, after = :c)) ==
        "relocate: before and after cannot both be given. " *
        "Got before = :b, after = :c. Use only one of them."
    @test msg(() -> relocate(:a; after = 1)) ==
        "relocate: the anchor must be a column name. Got 1. " *
        "Write before = :a or after = :a."
    @test msg(() -> relocate(; after = 1)) == msg(() -> relocate(:a; after = 1))
    f = FakeTable()
    @test select(:a)(f) === :select && select(; x = :a)(f) === :select
    @test rename(; x = :a)(f) === :rename
    @test relocate(:a)(f) === :relocate && relocate(; after = :a)(f) === :relocate
end

@testset "verbs and Base" begin
    @test TableOps.rename !== Base.rename
end

@testset "mutate" begin
    c5msg(shown) = "mutate: a value must be a single value or a vector. Got " *
        shown * ". Pass a vector with one value per row (collect a generator first), " *
        "or wrap the value in a vector: name = [x]."
    t = Table(; a = [1, 2, 3], b = [10.0, 20.0, 30.0])
    t3 = Table(; a = [1, 2, 3], b = ["x", "y", "z"], c = [1.5, missing, 3.5])
    r = check_forms_agree(mutate, t; c = :a)
    @test cn(r) == [:a, :b, :c] && r.c == [1, 2, 3] && r.c !== t.a        # a copy
    @test cc(r)[1] === cc(t)[1] && cc(r)[2] === cc(t)[2]                   # shared
    v = [7, 8, 9]
    @test mutate(t; c = v).c === v                                         # kept
    @test mutate(t; c = :a => sum).c == [6, 6, 6]
    @test eltype(mutate(t; c = :a => sum).c) == Int
    @test mutate(t; c = [:a, :b] => (x, y) -> x .+ y).c == [11.0, 22.0, 33.0]
    @test mutate(t; c = :a => each(x -> x * 2)).c == [2, 4, 6]
    @test eltype(mutate(t; c = :a => each(x -> x * 2)).c) == Int
    @test mutate(t; c = [:a, :b] => each((x, y) -> x / y)).c == [0.1, 0.1, 0.1]
    @test mutate(t; c = "a" => each(x -> -x)).c == [-1, -2, -3]            # String left
    @test mutate(t; c = tt -> tt.a .+ 1).c == [2, 3, 4]
    @test mutate(t; r = "EU").r == ["EU", "EU", "EU"]
    @test eltype(mutate(t; r = "EU").r) == String
    @test eltype(mutate(t; k = 1).k) == Int && eltype(mutate(t; k = 2.5).k) == Float64
    @test eltype(mutate(t; k = missing).k) == Missing
    # position, order, visibility
    @test cn(mutate(t; a = :b)) == [:a, :b] && mutate(t; a = :b).a == [10.0, 20.0, 30.0]
    @test cn(mutate(t; z = 1, y = 2)) == [:a, :b, :z, :y]
    @test mutate(t; c = :a => each(x -> x + 1), d = :c => each(x -> x * 10)).d ==
        [20, 30, 40]
    @test mutate(t; a = :a => each(x -> x + 1), c = :a).c == [2, 3, 4]   # sees it
    @test cn(mutate(t; a = :a => each(x -> x + 1), c = 0)) == [:a, :b, :c]
    @test mutate(t; c = tt -> tt.a .+ 1, d = tt -> tt.c .* 2).d == [4, 6, 8]  # table has c
    @test same_table(mutate(t), t)
    # lengths
    @test mutate(t; c = [5]).c == [5, 5, 5] && eltype(mutate(t; c = [5]).c) == Int
    @test eltype(mutate(t; c = Union{Missing,Int}[5]).c) == Union{Missing,Int}
    @test mutate(Table(; a = [1]); c = [5, 6][1:1]).c == [5]
    @test @inferred(TableOps._recycle([1], 3)) == [1, 1, 1]
    @test @inferred(TableOps._recycle(Union{Missing,Int}[1], 0)) == Int[]
    @test @inferred(TableOps._concrete(:mutate, :c, [1, 2])) == [1, 2]
    # materialise, alias, narrow
    @test mutate(t; c = 1:3).c isa Vector{Int}
    @test mutate(t; c = :a => (x -> view(x, 1:3))).c isa Vector{Int}
    @test mutate(t; c = :a => (x -> BitVector([true, false, true]))).c isa Vector{Bool}
    al = mutate(t; c = :a => identity); @test al.c == t.a && al.c !== t.a
    @test mutate(t; c = t.a).c !== t.a
    two = mutate(t; c = [1, 2, 3], d = :c); @test two.d == two.c && two.d !== two.c
    @test mutate(t; c = :a => (x -> Any[1, 2, 3])).c isa Vector{Int}
    @test mutate(t; c = :a => (x -> Any[1, missing, 3])).c isa Vector{Union{Missing,Int}}
    @test mutate(t; c = :a => (x -> Real[1, 2, 3])).c isa Vector{Int}
    @test mutate(t; c = :a => (x -> Any[missing, missing, missing])).c isa Vector{Missing}
    @test mutate(t; c = :a => each(x -> x == 1 ? "p" : "q")).c isa Vector{String}
    # missing and NaN in the data
    d = mutate(t3; d = :c => each(x -> x * 2))
    @test isequal(d.d, [3.0, missing, 7.0]) && eltype(d.d) == Union{Missing,Float64}
    @test isequal(mutate(t3; s = :c => sum).s, [missing, missing, missing])
    @test eltype(mutate(t3; s = :c => sum).s) == Missing
    nan = Table(; x = [NaN, 1.0])
    @test mutate(nan; y = :x => each(isnan)).y == [true, false]
    # all-missing column, no rows, no columns, one row
    m = Table(; m = [missing, missing])
    @test eltype(mutate(m; k = :m).k) == Missing
    @test eltype(mutate(m; k = :m => each(x -> x)).k) == Missing
    z = Table(; a = Int[])
    @test mutate(z; c = 1).c == Int[] && eltype(mutate(z; c = 1).c) == Int
    @test eltype(mutate(z; c = :a => each(x -> x + 1)).c) == Int
    @test mutate(z; c = [1]).c == Int[] && mutate(z; c = Int[]).c == Int[]
    @test nrow(mutate(Table(); a = 1)) == 0 && cn(mutate(Table(); a = 1)) == [:a]
    row1 = Table(; a = [1]); @test mutate(row1; c = [5]).c == [5]
    # Unicode and space names
    u = Table(; var"unit price" = [1.0, 2.0], 名前 = ["x", "y"])
    @test mutate(u; var"total x" = Symbol("unit price") => each(x -> 2x)).var"total x" ==
        [2.0, 4.0]
    @test mutate(u; 値 = "名前" => each(uppercase)).値 == ["X", "Y"]
    # forms, immutability, types
    check_input_unchanged(x -> mutate(x; c = :a => each(sqrt)), t)
    check_concrete_eltypes(mutate(t3; k = 1, s = "q", e = :c => each(x -> x), f = :a))
    @test same_table(mutate(c = :a)(t), mutate(t; c = :a))
    @test same_table(t |> mutate(c = :a => sum), mutate(t; c = :a => sum))
    @test mutate(; c = 1) isa Function
    @test cn(mutate((a = [1, 2],); b = :a => each(x -> x + 1))) == [:a, :b]  # NamedTuple in
    # a pipe closure builds its specs once
    f = mutate(c = :a => each(x -> x + 1))
    @test same_table(f(t), f(t)) && f(t).c == [2, 3, 4]
    # a NamedTuple per row is a vector, so allowed
    nt = mutate(t; c = [(a = 1,)])
    @test eltype(nt.c) == NamedTuple{(:a,),Tuple{Int}} && length(nt.c) == 3
    # empty abstract results have no values to narrow
    ze = Table(; a = Int[])
    @test mutate(ze; c = :a => (x -> Any[])).c isa Vector{Missing}
    @test mutate(ze; c = :a => (x -> Real[])).c isa Vector{Missing}
    @test mutate(ze; c = :a => (x -> Union{Missing,Real}[])).c isa Vector{Missing}
    @test mutate(ze; c = :a => (x -> Int[])).c isa Vector{Int}
    @test mutate(ze; c = :a => (x -> Union{Missing,Int}[])).c isa Vector{Union{Missing,Int}}
    @test mutate(ze; c = :a => (x -> Union{}[])).c isa Vector{Missing}
    @test mutate(ze; c = :a => each(uppercase)).c isa Vector{Missing}
    @test @inferred(TableOps._concrete(:mutate, :c, Union{Missing,Int}[])) ==
        Union{Missing,Int}[]
    # shared memory is copied, not only the same vector
    rs = mutate(t; s = :a => (x -> reshape(x, 3)))
    @test rs.s == t.a && !Base.mightalias(rs.s, cc(rs)[1])
    # a column must use 1-based indexing
    off = "mutate: column c does not use 1-based indexing. Got " *
        "(Base.IdentityUnitRange(0:2),). Convert it to a 1-based vector, " *
        "for example with collect."
    @test msg(() -> mutate(t; c = Base.IdentityUnitRange(0:2))) == off
    @test msg(() -> mutate(t; c = :a => (x -> Base.IdentityUnitRange(0:2)))) == off
    # other AbstractTable types: a method, or a MethodError
    fk = FakeTable()
    @test mutate(fk; c = 1) === :mutate && mutate(c = 1)(fk) === :mutate
    @test_throws MethodError mutate(NoMutateTable(); c = 1)
    @test_throws MethodError mutate(c = 1)(NoMutateTable())
    # the pipe form checks its specs at call time
    @test msg(() -> mutate(c = (1, 2))) == c5msg("(1, 2)")
    @test msg(() -> mutate(c = :a => 5)) ==
        "mutate: the right side of => must be a function or each(f). Got 5. " *
        "Write :a => f, where f takes whole columns, " *
        "or :a => each(f) to apply f to each element."
    # errors
    @test msg(() -> mutate(t, :a => sum)) ==
        "mutate: a column specification needs a name. Got :a => sum. " *
        "Write name = :a => sum."
    @test msg(() -> mutate(:a => sum)) == msg(() -> mutate(t, :a => sum))
    @test msg(() -> mutate(5; c = 1)) ==
        "mutate: the first argument is neither a table nor a column specification. " *
        "Got 5. Pass a table, or specifications such as mutate(c = :a) for the pipe form."
    @test msg(() -> mutate(t; c = :zz)) ==
        "mutate: column not found. Got :zz. Available columns: :a, :b."
    @test msg(() -> mutate(t; c = :zz => sum)) == msg(() -> mutate(t; c = :zz))
    @test msg(() -> mutate(t; c = [1, 2])) ==
        "mutate: a column has the wrong length. Got c has 2 rows, the table has 3. " *
        "Return a single value (repeated for every row) or exactly 3 values."
    @test msg(() -> mutate(t; c = Int[])) ==
        "mutate: a column has the wrong length. Got c has 0 rows, the table has 3. " *
        "Return a single value (repeated for every row) or exactly 3 values."
    @test msg(() -> mutate(Table(); a = [1, 2])) ==
        "mutate: a column has the wrong length. Got a has 2 rows, the table has 0. " *
        "Build a table from vectors with Table(; name = vector)."
    @test msg(() -> mutate(row1; c = [5, 6])) ==
        "mutate: a column has the wrong length. Got c has 2 rows, the table has 1. " *
        "Return a single value (repeated for every row) or exactly 1 values."
    c5 = "mutate: a value must be a single value or a vector. Got "
    c5fix = ". Pass a vector with one value per row (collect a generator first), " *
        "or wrap the value in a vector: name = [x]."
    @test msg(() -> mutate(t; c = (1, 2))) == c5 * "(1, 2)" * c5fix
    @test msg(() -> mutate(t; c = :a => (x -> (1, 2)))) == c5 * "(1, 2)" * c5fix
    @test msg(() -> mutate(t; c = (a = 1,))) == c5 * "(a = 1,)" * c5fix
    @test msg(() -> mutate(t; c = :a => (x -> (a = 1,)))) == c5 * "(a = 1,)" * c5fix
    @test msg(() -> mutate(t; c = Set([1]))) == c5 * "Set([1])" * c5fix
    @test msg(() -> mutate(t; c = :a => (x -> Set([1])))) == c5 * "Set([1])" * c5fix
    @test msg(() -> mutate(t; c = Dict(:a => 1))) == c5 * "Dict(:a => 1)" * c5fix
    @test msg(() -> mutate(t; c = :a => (x -> Dict(:a => 1)))) ==
        c5 * "Dict(:a => 1)" * c5fix
    @test msg(() -> mutate(t; c = [1 2; 3 4])) == c5 * "[1 2; 3 4]" * c5fix
    @test msg(() -> mutate(t; c = (x for x in 1:3)))[1:length(c5) + 14] ==
        c5 * "Base.Generator"
    @test msg(() -> mutate(t; c = :a => (x -> (y for y in x))))[1:length(c5) + 14] ==
        c5 * "Base.Generator"
    # lazy iterators are an error, by value and from a function
    lazies = (skipmissing([1, 2, 3]), zip(1:3, 4:6), enumerate([1, 2, 3]),
        Iterators.filter(isodd, 1:3), Iterators.take(1:5, 3), Iterators.drop(1:5, 2),
        Iterators.flatten([[1], [2]]), Iterators.cycle([1]), Iterators.repeated(1),
        Iterators.product(1:2, 1:2), Iterators.partition(1:4, 2),
        Iterators.takewhile(<(3), 1:5), Iterators.dropwhile(<(3), 1:5),
        Iterators.accumulate(+, 1:3), Iterators.Stateful(1:3), Iterators.rest(1:3, 2),
        values(Dict(:a => 1)), keys(Dict(:a => 1)))
    for x in lazies
        for m in (msg(() -> mutate(t; c = x)), msg(() -> mutate(t; c = :a => (_ -> x))))
            @test startswith(m, c5) && endswith(m, c5fix)
        end
    end
    @test msg(() -> mutate(t; c = skipmissing([1, 2, 3]))) ==
        c5 * "skipmissing([1, 2, 3])" * c5fix
    @test msg(() -> mutate(t; c = values(Dict(:a => 1)))) ==
        c5 * repr(values(Dict(:a => 1))) * c5fix
    # tables are an error; a vector of rows is a column
    c8 = "mutate: a value is a whole table. Got "
    c8fix = ". To add one of its columns write name = pull(other, :col); " *
        "to combine tables use a join."
    z3 = Table(; z = [1, 2, 3])
    @test msg(() -> mutate(t; c = z3)) == c8 * TableOps._fmt_value(z3) * c8fix
    @test msg(() -> mutate(t; c = :a => (_ -> z3))) == c8 * TableOps._fmt_value(z3) * c8fix
    @test msg(() -> mutate(c = z3)) == c8 * TableOps._fmt_value(z3) * c8fix
    @test msg(() -> mutate(t; c = (z = [1, 2, 3],))) ==
        c5 * "(z = [1, 2, 3],)" * c5fix                      # C5 comes first
    @test msg(() -> mutate(t; c = :a => (_ -> (z = [1, 2, 3],)))) ==
        c5 * "(z = [1, 2, 3],)" * c5fix
    rows3 = [(a = 1,), (a = 2,), (a = 3,)]
    @test mutate(t; c = rows3).c == rows3
    @test mutate(t; c = :a => (_ -> rows3)).c == rows3
    @test mutate(t; c = :a => each(x -> (a = x,))).c == rows3
    # nothing is an error, not a column or a constant
    c9 = "mutate: a function returned nothing for c. Got nothing. " *
        "Return a value; use missing for an absent one."
    @test msg(() -> mutate(t; c = nothing)) == c9
    @test msg(() -> mutate(c = nothing)) == c9
    @test msg(() -> mutate(t; c = :a => (_ -> nothing))) == c9
    @test msg(() -> mutate(t; c = tt -> nothing)) == c9
    @test msg(() -> mutate(t; c = :a => each(_ -> nothing))) == c9
    @test msg(() -> mutate(t; c = :a => (_ -> Any[nothing, nothing, nothing]))) == c9
    @test msg(() -> mutate(t; c = :a => (_ -> Any[nothing, missing, nothing]))) == c9
    @test msg(() -> mutate(t; c = [nothing])) == c9
    @test msg(() -> mutate(Table(; a = Int[]); c = :a => each(_ -> nothing))) == c9
    @test msg(() -> mutate(t; c = :a => (_ -> Any[1, nothing, 3]))) ==
        "mutate: a column mixes element types. Got c holds Int64 and Nothing. " *
        "Give the column one element type, for example by converting the values."
    # the fix text names no function when none is used
    @test msg(() -> mutate(t; d = Any[1, "a", 2])) ==
        "mutate: a column mixes element types. Got d holds Int64 and String. " *
        "Give the column one element type, for example by converting the values."
    @test msg(() -> mutate(Table(; q = Any[1, "x", 2]); c = :q)) ==
        "mutate: a column mixes element types. Got c holds Int64 and String. " *
        "Give the column one element type, for example by converting the values."
    @test msg(() -> mutate(t; c = :a => each(x -> x == 1 ? 1 : 2.5))) ==
        "mutate: a column mixes element types. Got c holds Int64 and Float64. " *
        "Give the column one element type, for example by converting the values."
    @test msg(() -> mutate(t; c = :a => (x -> Union{Int,String}[1, "a", 2]))) ==
        "mutate: a column mixes element types. Got c holds Int64 and String. " *
        "Give the column one element type, for example by converting the values."
    @test msg(() -> mutate(t; c = :a => 5)) ==
        "mutate: the right side of => must be a function or each(f). Got 5. " *
        "Write :a => f, where f takes whole columns, " *
        "or :a => each(f) to apply f to each element."
    @test_throws DomainError mutate(t; c = :a => each(x -> sqrt(-x)))  # user errors pass
end
