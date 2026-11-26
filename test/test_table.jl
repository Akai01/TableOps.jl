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

    # Non-vector columns are collected; names become Symbols.
    c = Table(TupleColumns())
    @test getfield(c, :names) == [:a, :b]
    @test getfield(c, :columns)[1] == [1, 2]
    @test getfield(c, :columns)[1] isa Vector{Int}

    # unchanged input
    nt = (a = [1, 2], b = [3, 4])
    Table(nt)
    @test nt == (a = [1, 2], b = [3, 4])

    msg(f) = try f(); nothing catch e e isa ArgumentError ? e.msg : e end
    @test_throws ArgumentError Table(1)
    @test startswith(msg(() -> Table(1)),
        "Table: input is not a Tables.jl table. Got Int64.")
    @test_throws ArgumentError Table((a = i,) for i in 1:2)
    @test occursin("Table(collect(x))", msg(() -> Table((a = i,) for i in 1:2)))
    @test_throws ArgumentError Table(; a = 1)
    @test msg(() -> Table(; a = 1)) ==
        "Table: column a is not a vector. Got 1. Wrap a single value in a vector: a = [1]."
    @test_throws ArgumentError Table(; a = [1, 2, 3], b = [1, 2])
    @test msg(() -> Table(; a = [1, 2, 3], b = [1, 2])) ==
        "Table: columns have different lengths. Got a has 3 rows, b has 2. Give every column the same number of rows."
    @test_throws ArgumentError Table(; a = [1, 2], b = [1, 2], c = [1])
    @test msg(() -> Table(; a = [1, 2], b = [1, 2], c = [1])) ==
        "Table: columns have different lengths. Got a has 2 rows, c has 1. Give every column the same number of rows."
    dup = Tables.table([1 2]; header = [:a, :a])
    @test_throws ArgumentError Table(dup)
    @test msg(() -> Table(dup)) ==
        "Table: duplicate column name. Got :a. Give every column its own name."
    @test_throws ArgumentError Table(; a = ZeroBased(3))
    @test_throws ArgumentError Table((a = ZeroBased(3),))
    @test msg(() -> Table(; a = ZeroBased(3))) ==
        "Table: column a does not use 1-based indexing. Got (0:2,). Convert it to a 1-based vector, for example with collect."
    @test msg(() -> Table((a = ZeroBased(3),))) ==
        "Table: column a does not use 1-based indexing. Got (0:2,). Convert it to a 1-based vector, for example with collect."

    # the fix shows the value and a valid Julia name
    @test msg(() -> Table(; a = "x")) ==
        "Table: column a is not a vector. Got \"x\". " *
        "Wrap a single value in a vector: a = [\"x\"]."
    @test msg(() -> Table(; var"unit price" = 2.5)) ==
        "Table: column unit price is not a vector. Got 2.5. " *
        "Wrap a single value in a vector: var\"unit price\" = [2.5]."
    @test msg(() -> Table(; a = (1, 2))) ==
        "Table: column a is not a vector. Got (1, 2). " *
        "Convert it to a vector: a = collect(x)."
    @test msg(() -> Table(; var"b c" = (1, 2))) ==
        "Table: column b c is not a vector. Got (1, 2). " *
        "Convert it to a vector: var\"b c\" = collect(x)."
    @test_throws ArgumentError Table(; a = "x")
    @test_throws ArgumentError Table(; a = (1, 2))

    @test getfield(Table(NamedTuple()), :names) == Symbol[]
    @test getfield(Table(NamedTuple()), :columns) == AbstractVector[]
    ux = Table((var"unit price" = [1.0], 名前 = ["x"]))
    @test getfield(ux, :names) == [Symbol("unit price"), :名前]
    @test getfield(Table([(var"unit price" = 1.0, 名前 = "x")]), :names) ==
        [Symbol("unit price"), :名前]
    mx = Table(; a = [1, missing, 3])
    @test eltype(getfield(mx, :columns)[1]) == Union{Missing,Int}
    @test @inferred(TableOps._newtable(Symbol[:a], AbstractVector[[1]])) isa Table

    @test TableOps._istable(t) && TableOps._istable((a = [1],))
    @test !TableOps._istable(1) && !TableOps._istable([1, 2])
    @test TableOps._table(t) === t
    @test TableOps._table((a = [1],)) isa Table

    n = TableOps._newtable([:x, :y], AbstractVector[[1], [2]])
    @test n isa Table && getfield(n, :lookup) == Dict(:x => 1, :y => 2)
end

@testset "Table interface" begin
    t = Table(; store = ["A", "B"], revenue = [1.0, missing])
    @test t.store == ["A", "B"]
    @test t.store === getfield(t, :columns)[1]
    @test propertynames(t) == (:store, :revenue)
    @test propertynames(t) isa Tuple
    @test names(t) == [:store, :revenue]
    push!(names(t), :x); @test names(t) == [:store, :revenue]   # a copy
    @test (nrow(t), ncol(t)) == (2, 2)
    @test (nrow(Table()), ncol(Table())) == (0, 0)
    @test (nrow(Table(; a = Int[])), ncol(Table(; a = Int[]))) == (0, 1)
    w = Table(; columns = [1], names = [2], lookup = [3])       # field-named columns
    @test (w.columns, w.names, w.lookup) == ([1], [2], [3])
    @test nrow(w) == 1 && ncol(w) == 3 && names(w) == [:columns, :names, :lookup]

    msg(f) = try f(); nothing catch e e isa ArgumentError ? e.msg : e end
    @test_throws ArgumentError t.revenu
    @test msg(() -> t.revenu) ==
        "getproperty: column not found. Got :revenu. Did you mean :revenue?"
    @test msg(() -> t.zzz) ==
        "getproperty: column not found. Got :zzz. Available columns: :store, :revenue."
    @test msg(() -> Tables.getcolumn(t, :zzz)) ==
        "getcolumn: column not found. Got :zzz. Available columns: :store, :revenue."
    @test msg(() -> Table().a) ==
        "getproperty: column not found. Got :a. The table has no columns."
    @test msg(() -> Table(; var"unit price" = [1]).zzz) ==
        "getproperty: column not found. Got :zzz. " *
        "Available columns: Symbol(\"unit price\")."
    wide = Table(; (Symbol("c", i) => [i] for i in 1:25)...)
    @test msg(() -> wide.xyz) ==
        "getproperty: column not found. Got :xyz. Available columns: " *
        ":c1, :c2, :c3, :c4, :c5, :c6, :c7, :c8, :c9, :c10 … (25 columns)."
    ten = Table(; (Symbol("c", i) => [i] for i in 1:10)...)
    @test msg(() -> ten.xyz) ==
        "getproperty: column not found. Got :xyz. Available columns: " *
        ":c1, :c2, :c3, :c4, :c5, :c6, :c7, :c8, :c9, :c10."
    @test_throws ArgumentError t.revenue = [2.0, 3.0]
    @test msg(() -> (t.revenue = [2.0, 3.0])) ==
        "setproperty!: a Table cannot be changed in place. Got :revenue. " *
        "Use mutate to get a new table with the changed column."
    @test isequal(t.revenue, [1.0, missing])

    c = copy(t)
    @test isequal(c, t) && getfield(c, :columns)[1] !== getfield(t, :columns)[1]
    c.store[1] = "Z"; @test t.store[1] == "A"                    # independent
    @test getfield(c, :names) !== getfield(t, :names)
    nested = Table(; v = [[1], [2]])
    @test copy(nested).v[1] === nested.v[1]                      # shallow per element

    @test isequal(t, Table(; store = ["A", "B"], revenue = [1.0, missing]))
    @test hash(t) == hash(Table(; store = ["A", "B"], revenue = [1.0, missing]))
    @test !isequal(t, Table(; revenue = [1.0, missing], store = ["A", "B"]))
    @test !isequal(t, Table(; store = ["A", "B"], revenue = [1.0, 2.0]))
    @test !isequal(t, Table(; store = ["A"], revenue = [1.0]))
    @test isequal(Table(; a = 1:2), Table(; a = [1, 2]))
    @test hash(Table(; a = 1:2)) == hash(Table(; a = [1, 2]))
    @test isequal(Table(; a = [NaN]), Table(; a = [NaN]))
    @test hash(Table(; a = [NaN])) == hash(Table(; a = [NaN]))
    @test isequal(Table(), Table()) && hash(Table()) == hash(Table())
    @test ismissing(t == copy(t))                                # three-valued
    @test (Table(; a = [NaN]) == Table(; a = [NaN])) === false
    @test (Table(; a = [1]) == Table(; b = [1])) === false
    @test (Table(; a = [1], b = [2]) == Table(; b = [2], a = [1])) === false
    @test (Table(; a = [1, 2]) == Table(; a = [1])) === false
    @test (Table(; a = [1, missing]) == Table(; a = [2, missing])) === false
    @test (Table(; a = [1, 2]) == Table(; a = [1.0, 2.0])) === true
    @test (Table() == Table()) === true
    @test (Table(; a = Int[]) == Table(; a = Int[])) === true

    @test as_table(t) === t
    @test as_table((a = [1],)) isa Table
    @test as_table(Dict(:a => [1])) isa Table
    @test_throws ArgumentError as_table(1)

    @test Tables.istable(t) && Tables.columnaccess(t)
    @test Tables.columns(t) === t
    @test Tables.getcolumn(t, 1) === t.store
    @test Tables.getcolumn(t, :revenue) === t.revenue
    @test Tables.columnnames(t) == [:store, :revenue]
    push!(Tables.columnnames(t), :x); @test names(t) == [:store, :revenue]
    @test Tables.schema(t) ==
        Tables.Schema([:store, :revenue], [String, Union{Missing,Float64}])
    @test isequal(Tables.columntable(t), (store = ["A", "B"], revenue = [1.0, missing]))
    @test length(Tables.rowtable(t)) == 2
    @test isequal(Table(Tables.rowtable(t)), t)
    @test @inferred(nrow(t)) == 2
    @test @inferred(ncol(t)) == 2

    @test_throws MethodError nrow((a = [1],))                    # Table only
    @test_throws MethodError ncol((a = [1],))
end
