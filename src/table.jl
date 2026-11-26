abstract type AbstractTable end

"""
    Table(x)
    Table(; name = column, ...)

A table with named columns. `Table(x)` accepts any Tables.jl table, and
`Table(; a = [1, 2], b = ["x", "y"])` builds one from keyword columns, in
keyword order.

Columns are shared, not copied: `Table(x)` keeps the source's column vectors
as they are, so changing a vector in place changes every table that holds
it. A column that is not an `AbstractVector` is collected into one. A
`Table` passed to `Table` is returned as is.

`t.revenue` returns the stored column, whatever the column is called, and
throws an `ArgumentError` with a suggestion for an unknown name. A `Table`
cannot be changed in place: `t.revenue = v` throws. `names(t)` returns the
column names as a `Vector{Symbol}` (a copy). `copy(t)` copies every column
with `copy`, so the result is independent of `t` except for the elements
themselves: a column of vectors shares its inner vectors. `isequal` compares
names and columns with `isequal`; `==` follows Julia's three-valued rule and
can return `missing`.

Every column must use 1-based indexing, all names must be unique, and all
columns must have the same length; otherwise an `ArgumentError` says how to
fix it.

# Examples
```jldoctest
julia> using TableOps

julia> Table(; a = [1, 2], b = ["x", "y"])
2×2 Table
     a  b
 Int64  String
 ─────────────
     1  x
     2  y
```

A `Table` prints its size, the column names and types and the first and
last rows, fitted to the display; `glimpse` shows one line per column.
In the REPL, rows and columns are fitted to the screen; written elsewhere, all
rows and columns are shown.
"""
struct Table <: AbstractTable
    names::Vector{Symbol}
    columns::Vector{AbstractVector}
    lookup::Dict{Symbol,Int}
end

function _newtable(names::Vector{Symbol}, columns::Vector{AbstractVector})::Table
    Table(names, columns, Dict{Symbol,Int}(n => i for (i, n) in enumerate(names)))
end

function _dupname(names::Vector{Symbol})::Union{Symbol,Nothing}
    seen = Set{Symbol}()
    for n in names
        n in seen && return n
        push!(seen, n)
    end
    nothing
end

_kwname(n::Symbol) = Base.isidentifier(n) ? String(n) : "var\"$n\""

_checkaxes(verb::Symbol, name::Symbol, col) = Base.has_offset_axes(col) &&
    _argerror(verb, "column $name does not use 1-based indexing", axes(col),
        "Convert it to a 1-based vector, for example with collect.")

function _checkcolumns(names::Vector{Symbol}, columns::Vector{AbstractVector})
    for (n, col) in zip(names, columns)
        _checkaxes(:Table, n, col)
    end
    d = _dupname(names)
    d === nothing || _argerror(:Table, "duplicate column name", d,
        "Give every column its own name.")
    for i in 2:length(columns)
        length(columns[i]) == length(columns[1]) && continue
        _argerror(:Table, "columns have different lengths",
            Text("$(names[1]) has $(length(columns[1])) rows, " *
                 "$(names[i]) has $(length(columns[i]))"),
            "Give every column the same number of rows.")
    end
end

function _notatable(verb::Symbol, x)
    _argerror(verb, "input is not a Tables.jl table", typeof(x),
        "Pass a NamedTuple of vectors, a vector of NamedTuples or another " *
        "Tables.jl table; collect a generator first: Table(collect(x)).")
end

function _samerownames(rows::AbstractVector)
    isempty(rows) && return nothing
    base = Tables.columnnames(rows[1])
    for i in 2:length(rows)
        names = Tables.columnnames(rows[i])
        (names == base || issetequal(names, base)) && continue
        _argerror(:Table, "rows have different column names",
            Text("row 1 has $(join(base, ", ")), row $i has $(join(names, ", "))"),
            "Give every row the same names; use missing for a value that is absent.")
    end
end

function Table(x)
    Tables.istable(x) || _notatable(:Table, x)
    x isa AbstractVector && !Tables.columnaccess(x) && Tables.schema(x) === nothing &&
        _samerownames(x)
    cols = Tables.columns(x)
    raw = collect(Tables.columnnames(cols))
    names = Symbol[Symbol(n) for n in raw]
    columns = AbstractVector[]
    for i in eachindex(raw)
        col = Tables.getcolumn(cols, i)
        col isa AbstractVector || (col = collect(col))
        col isa AbstractVector || _argerror(:Table, "column $(names[i]) is not a vector",
            typeof(col), "Give a one-dimensional column.")
        push!(columns, col)
    end
    _checkcolumns(names, columns)
    _newtable(names, columns)
end

Table(t::Table) = t

function _vectorfix(n::Symbol, v)::String
    arg = _kwname(n)
    v isa Tuple && return "Convert it to a vector: $arg = collect(x)."
    "Wrap a single value in a vector: $arg = [$(_fmt_value(v))]."
end

function Table(; kwargs...)
    names = collect(Symbol, keys(kwargs))
    columns = AbstractVector[]
    for (n, v) in kwargs
        v isa AbstractVector || _argerror(:Table, "column $n is not a vector", v,
            _vectorfix(n, v))
        push!(columns, v)
    end
    _checkcolumns(names, columns)
    _newtable(names, columns)
end

_istable(x) = x isa AbstractTable || Tables.istable(x)

_table(x::AbstractTable, verb::Symbol = :Table) = x
function _table(x, verb::Symbol = :Table)
    Tables.istable(x) || _notatable(verb, x)
    Table(x)
end

function _available(names::Vector{Symbol})::String
    isempty(names) && return "The table has no columns."
    list = join((repr(n) for n in first(names, 10)), ", ")
    length(names) > 10 ? "Available columns: $list … ($(length(names)) columns)." :
        "Available columns: $list."
end

function _notfound(verb::Symbol, name::Symbol, names::Vector{Symbol})
    near = _suggest(name, names)
    _argerror(verb, "column not found", name,
        near === nothing ? _available(names) : "Did you mean $(repr(near))?")
end

function _position(t::Table, name::Symbol, verb::Symbol)::Int
    i = get(getfield(t, :lookup), name, 0)
    i == 0 && _notfound(verb, name, getfield(t, :names))
    i
end

_column(t::Table, name::Symbol, verb::Symbol)::AbstractVector =
    getfield(t, :columns)[_position(t, name, verb)]

Base.getproperty(t::Table, name::Symbol) = _column(t, name, :getproperty)

Base.setproperty!(t::Table, name::Symbol, v) = _argerror(:setproperty!,
    "a Table cannot be changed in place", name,
    "Use mutate to get a new table with the changed column.")

Base.propertynames(t::Table, private::Bool = false) = Tuple(getfield(t, :names))

"""
    names(t::Table)

The column names of `t` as a `Vector{Symbol}`. The vector is a copy.

# Examples
```jldoctest
julia> using TableOps

julia> names(Table(; a = [1, 2], b = ["x", "y"]))
2-element Vector{Symbol}:
 :a
 :b
```
"""
Base.names(t::Table) = copy(getfield(t, :names))

"""
    nrow(t::Table)

The number of rows of `t`. A table with no columns has no rows.

# Examples
```jldoctest
julia> using TableOps

julia> nrow(Table(; a = [1, 2, 3]))
3

julia> nrow(Table())
0
```
"""
nrow(t::Table)::Int = isempty(getfield(t, :columns)) ? 0 : length(getfield(t, :columns)[1])

"""
    ncol(t::Table)

The number of columns of `t`.

# Examples
```jldoctest
julia> using TableOps

julia> ncol(Table(; a = [1, 2, 3], b = ["x", "y", "z"]))
2
```
"""
ncol(t::Table) = length(getfield(t, :names))

"""
    as_table(x)

Convert `x` to a `Table`: a `Table` is returned as is, and any other
Tables.jl table is wrapped as in `Table(x)`.

# Examples
```jldoctest
julia> using TableOps

julia> as_table((a = [1, 2],)) isa Table
true

julia> t = Table(; a = [1]); as_table(t) === t
true
```
"""
as_table(t::Table) = t
as_table(x) = Table(x)

Base.copy(t::Table) = _newtable(copy(getfield(t, :names)),
    AbstractVector[copy(c) for c in getfield(t, :columns)])

function Base.isequal(a::Table, b::Table)
    getfield(a, :names) == getfield(b, :names) || return false
    ca, cb = getfield(a, :columns), getfield(b, :columns)
    all(i -> isequal(ca[i], cb[i]), eachindex(ca))
end

Base.hash(t::Table, h::UInt) =
    hash(getfield(t, :columns), hash(getfield(t, :names), hash(:Table, h)))

function Base.:(==)(a::Table, b::Table)
    getfield(a, :names) == getfield(b, :names) || return false
    nrow(a) == nrow(b) || return false
    ca, cb = getfield(a, :columns), getfield(b, :columns)
    unknown = false
    for i in eachindex(ca)
        r = ca[i] == cb[i]
        r === false && return false
        unknown |= ismissing(r)
    end
    unknown ? missing : true
end

Tables.istable(::Type{Table}) = true
Tables.columnaccess(::Type{Table}) = true
Tables.columns(t::Table) = t
Tables.getcolumn(t::Table, i::Int) = getfield(t, :columns)[i]
Tables.getcolumn(t::Table, name::Symbol) = _column(t, name, :getcolumn)
Tables.columnnames(t::Table) = copy(getfield(t, :names))
Tables.schema(t::Table) =
    Tables.Schema(getfield(t, :names), Type[eltype(c) for c in getfield(t, :columns)])
