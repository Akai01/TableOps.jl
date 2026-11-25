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

Every column must use 1-based indexing, all names must be unique, and all
columns must have the same length; otherwise an `ArgumentError` says how to
fix it.

# Examples
```jldoctest
julia> using TableOps

julia> Table(; a = [1, 2], b = ["x", "y"]) isa Table
true
```
"""
struct Table <: AbstractTable
    names::Vector{Symbol}
    columns::Vector{AbstractVector}
    lookup::Dict{Symbol,Int}
end

function _newtable(names::Vector{Symbol}, columns::Vector{AbstractVector})::Table
    Table(names, columns, Dict{Symbol,Int}(n => i for (i, n) in enumerate(names)))
end

function _checkcolumns(names::Vector{Symbol}, columns::Vector{AbstractVector})
    for (n, col) in zip(names, columns)
        Base.has_offset_axes(col) && _argerror(:Table,
            "column $n does not use 1-based indexing", axes(col),
            "Convert it to a 1-based vector, for example with collect.")
    end
    seen = Set{Symbol}()
    for n in names
        n in seen && _argerror(:Table, "duplicate column name", n,
            "Give every column its own name.")
        push!(seen, n)
    end
    for i in 2:length(columns)
        length(columns[i]) == length(columns[1]) && continue
        _argerror(:Table, "columns have different lengths",
            Text("$(names[1]) has $(length(columns[1])) rows, " *
                 "$(names[i]) has $(length(columns[i]))"),
            "Give every column the same number of rows.")
    end
end

function Table(x)
    Tables.istable(x) || _argerror(:Table, "input is not a Tables.jl table", typeof(x),
        "Pass a NamedTuple of vectors, a vector of NamedTuples or another " *
        "Tables.jl table; collect a generator first: Table(collect(x)).")
    cols = Tables.columns(x)
    raw = collect(Tables.columnnames(cols))
    names = Symbol[Symbol(n) for n in raw]
    columns = AbstractVector[]
    for i in eachindex(raw)
        col = Tables.getcolumn(cols, i)
        push!(columns, col isa AbstractVector ? col : collect(col))
    end
    _checkcolumns(names, columns)
    _newtable(names, columns)
end

Table(t::Table) = t

function Table(; kwargs...)
    names = collect(Symbol, keys(kwargs))
    columns = AbstractVector[]
    for (n, v) in kwargs
        v isa AbstractVector || _argerror(:Table, "column $n is not a vector", v,
            "Wrap a single value in a vector: $n = [1].")
        push!(columns, v)
    end
    _checkcolumns(names, columns)
    _newtable(names, columns)
end

_istable(x) = x isa AbstractTable || Tables.istable(x)

_table(x::AbstractTable) = x
_table(x) = Table(x)
