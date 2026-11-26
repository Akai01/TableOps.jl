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
    for T in (Any, Real, Union{Int,String}, Union{Missing,Real}, Number)
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
        "rename: a column cannot get two new names. Got :a. " *
        "To keep it under both names use select(t; var\"x y\" = :a, z = :a)."
    @test msg(() -> rename(t; x = :zz)) ==
        "rename: column not found. Got :zz. Available columns: :a, :b, :c."
    @test msg(() -> rename(t; b = :a)) ==
        "rename: two columns would have the same name. Got :b. " *
        "Rename the other one too, or drop it first with select."
    @test msg(() -> rename(t; x = :a, y = :a)) ==
        "rename: a column cannot get two new names. Got :a. " *
        "To keep it under both names use select(t; x = :a, y = :a)."
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
