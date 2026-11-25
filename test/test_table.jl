import Tables

struct ZeroBased <: AbstractVector{Int}
    n::Int
end
Base.size(z::ZeroBased) = (z.n,)
Base.axes(z::ZeroBased) = (0:(z.n - 1),)
Base.getindex(z::ZeroBased, i::Int) = i

struct TupleColumns end
Tables.istable(::Type{TupleColumns}) = true
Tables.columnaccess(::Type{TupleColumns}) = true
Tables.columns(x::TupleColumns) = x
Tables.columnnames(::TupleColumns) = (:a, "b")
Tables.getcolumn(::TupleColumns, i::Int) = i == 1 ? (1, 2) : [3, 4]
Tables.getcolumn(x::TupleColumns, n::Symbol) = Tables.getcolumn(x, n === :a ? 1 : 2)

struct SharedColumns
    v::Vector{Int}
end
Tables.istable(::Type{SharedColumns}) = true
Tables.columnaccess(::Type{SharedColumns}) = true
Tables.columns(x::SharedColumns) = x
Tables.columnnames(::SharedColumns) = (:a,)
Tables.getcolumn(x::SharedColumns, ::Int) = x.v
Tables.getcolumn(x::SharedColumns, ::Symbol) = x.v

@testset "Table construction" begin
    v = [1, 2, 3]
    t = Table((a = v, b = ["x", "y", "z"]))
    @test getfield(t, :names) == [:a, :b]
    @test getfield(t, :columns)[1] === v                     # no copy
    @test getfield(t, :lookup) == Dict(:a => 1, :b => 2)
    @test Table(t) === t

    r = Table([(a = 1, b = "x"), (a = 2, b = "y")])          # row table
    @test getfield(r, :columns)[1] == [1, 2]
    @test getfield(r, :columns)[2] == ["x", "y"]

    k = Table(; a = v, b = 1:3)
    @test getfield(k, :columns)[1] === v
    @test getfield(k, :columns)[2] === 1:3                   # kept as is

    @test getfield(Table(), :names) == Symbol[]              # no columns
    z = Table(; a = Int[], b = String[])                     # no rows
    @test eltype(getfield(z, :columns)[2]) == String
    u = Table(; var"unit price" = [1.0], 名前 = ["x"])        # Unicode, spaces
    @test getfield(u, :names) == [Symbol("unit price"), :名前]
    m = Table(; a = [missing, missing])                      # all missing
    @test eltype(getfield(m, :columns)[1]) == Missing
    d = Table(Dict(:a => [1, 2], :b => [3, 4]))
    dl = getfield(d, :lookup)
    @test Set(getfield(d, :names)) == Set([:a, :b])
    @test getfield(d, :columns)[dl[:a]] == [1, 2]
    @test getfield(d, :columns)[dl[:b]] == [3, 4]

    w = [1, 2]
    s = Table(SharedColumns(w))                              # not a NamedTuple
    @test getfield(s, :columns)[1] === w                     # no copy

    one = Table(; a = [1])                                   # one row
    @test getfield(one, :columns)[1] == [1]
    nan = Table(; a = [NaN, 1.0])
    @test isnan(getfield(nan, :columns)[1][1])

    # non-vector source columns are collected; names become Symbols
    c = Table(TupleColumns())
    @test getfield(c, :names) == [:a, :b]
    @test getfield(c, :columns)[1] == [1, 2]
    @test getfield(c, :columns)[1] isa Vector{Int}

    # unchanged input
    nt = (a = [1, 2], b = [3, 4])
    Table(nt)
    @test nt == (a = [1, 2], b = [3, 4])

    msg(f) = try f(); nothing catch e e.msg end
    @test_throws ArgumentError Table(1)
    @test startswith(msg(() -> Table(1)),
        "Table: input is not a Tables.jl table. Got Int64.")
    @test occursin("Table(collect(x))", msg(() -> Table((a = i,) for i in 1:2)))
    @test msg(() -> Table(; a = 1)) ==
        "Table: column a is not a vector. Got 1. Wrap a single value in a vector: a = [1]."
    @test msg(() -> Table(; a = [1, 2, 3], b = [1, 2])) ==
        "Table: columns have different lengths. Got a has 3 rows, b has 2. Give every column the same number of rows."
    @test msg(() -> Table(; a = [1, 2], b = [1, 2], c = [1])) ==
        "Table: columns have different lengths. Got a has 2 rows, c has 1. Give every column the same number of rows."
    dup = Tables.table([1 2]; header = [:a, :a])
    @test msg(() -> Table(dup)) ==
        "Table: duplicate column name. Got :a. Give every column its own name."
    @test msg(() -> Table(; a = ZeroBased(3))) ==
        "Table: column a does not use 1-based indexing. Got (0:2,). Convert it to a 1-based vector, for example with collect."
    @test msg(() -> Table((a = ZeroBased(3),))) ==
        "Table: column a does not use 1-based indexing. Got (0:2,). Convert it to a 1-based vector, for example with collect."

    @test TableOps._istable(t) && TableOps._istable((a = [1],))
    @test !TableOps._istable(1) && !TableOps._istable([1, 2])
    @test TableOps._table(t) === t
    @test TableOps._table((a = [1],)) isa Table

    n = TableOps._newtable([:x, :y], AbstractVector[[1], [2]])
    @test n isa Table && getfield(n, :lookup) == Dict(:x => 1, :y => 2)
end
