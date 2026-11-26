# Bounds-checked read: rows may come from users.
function _gather(col::AbstractVector{T}, rows::AbstractVector{Int})::Vector{T} where {T}
    out = Vector{T}(undef, length(rows))
    for (k, r) in enumerate(rows)
        v = col[r]
        @inbounds out[k] = v
    end
    out
end

function _take(t::Table, rows::AbstractVector{Int})::Table
    cols = AbstractVector[_gather(c, rows) for c in getfield(t, :columns)]
    _newtable(copy(getfield(t, :names)), cols)
end

"""
    where(t, conditions...)
    where(conditions...)

Keep the rows of `t` for which every condition is `true`. A condition is a
`Bool` column name such as `:flag`, `:col => f`, `[:a, :b] => f`,
`:col => each(f)`, or a function of the table such as `t -> t.x .> 1`.

`true` keeps a row; `false` and `missing` drop it, as SQL `WHERE` does. So
`!(x == 1)` also drops the rows where `x` is `missing`. Conditions are
combined with AND, and each one sees the whole table. A single value, or a
vector of length 1, applies to every row; any other length is an error, and
so is a value that is not `Bool` or `missing`. With no conditions the table
is returned as it is.

The result never shares columns with the input. Conditions are positional;
to add a column use [`mutate`](@ref). The form `where (x)`, with a space,
does not parse.

# Examples
```jldoctest
julia> using TableOps

julia> t = Table(; a = [3, 1, 2], b = ["x", "y", "z"]);

julia> pull(where(t, :a => each(>(1))), :b)
2-element Vector{String}:
 "x"
 "z"

julia> pull(t |> where(tt -> tt.a .< 3), :b)
2-element Vector{String}:
 "y"
 "z"
```
"""
function where(x, rest...; kw...)
    isempty(kw) || _wherekw(kw)
    if _istable(x)
        _where(_table(x, :where), _specs(:where, rest, (;); allow_unnamed = true))
    else
        (_ispositional(x) || x isa Function) || _firstarg(:where, x, "a condition",
            "conditions such as where(:x => each(>(1)))")
        specs = _specs(:where, (x, rest...), (;); allow_unnamed = true)
        t -> _where(_table(t, :where), specs)
    end
end

function where(; kw...)
    isempty(kw) || _wherekw(kw)
    t -> _where(_table(t, :where), ColSpec[])
end

function _wherekw(kw)
    k, v = first(kw)
    _argerror(:where, "conditions are positional, not keywords",
        Text("$k = $(_fmt_value(v))"),
        "Write a condition such as where(t, :x => each(>(1))); " *
        "to add a column use mutate.")
end

_where(t::Table, specs::Vector{ColSpec})::Table =
    isempty(specs) ? t : _take(t, _where_rows(t, specs))

function _where_rows(t::Table, specs::Vector{ColSpec})::Vector{Int}
    keep = trues(nrow(t))
    for (k, s) in enumerate(specs)
        _andcond!(keep, _run(s, t, :where), k)
    end
    findall(keep)
end

# The call into _and! is the barrier for the typed loop.
function _andcond!(keep::AbstractVector{Bool}, r, k::Int)
    n = length(keep)
    if r isa AbstractVector
        length(r) == n && return _and!(keep, r, k)
        length(r) == 1 || _badcondlength(k, length(r), n)
        r = r[1]
    end
    r === true && return keep
    (r === false || r === missing) && return fill!(keep, false)
    _notbool(k, r, nothing)
end

function _and!(keep::AbstractVector{Bool}, r::AbstractVector, k::Int)
    for i in eachindex(keep)
        x = r[i]
        x === true && continue
        (x === false || x === missing) ? (keep[i] = false) : _notbool(k, x, i)
    end
    keep
end

function _notbool(k::Int, x, i::Union{Int,Nothing})
    at = i === nothing ? "" : " in row $i"
    _argerror(:where, "a condition must give true, false or missing",
        Text("condition $k gave $(_fmt_value(x)) of type $(typeof(x))$at"),
        "Return Bool values, for example :x => each(>(1)).")
end

_badcondlength(k::Int, m::Int, n::Int) = _argerror(:where,
    "a condition has the wrong length",
    Text("condition $k has $m rows, the table has $n"),
    "Return one true or false per row, or a single one for every row.")

struct Desc
    name::Symbol
end
Base.show(io::IO, d::Desc) = print(io, "desc(", repr(d.name), ")")

"""
    desc(name)

Mark the sort key `name` (a `Symbol` or `String`) as descending, for use in
[`arrange`](@ref).

# Examples
```jldoctest
julia> using TableOps

julia> desc(:a)
desc(:a)
```
"""
desc(x::Union{Symbol,AbstractString}) = Desc(Symbol(x))
desc(x) = _argerror(:desc, "needs a column name", x, "Write desc(:a).")

_checkflag(verb::Symbol, name::Symbol, x) = x isa Bool ? x : _argerror(verb,
    "$name must be true or false", x, "Write $name = true or $name = false.")

_iskey(x) = x isa Union{Symbol,AbstractString,Desc}

function _sortkeys(keys::Tuple)::Vector{Tuple{Symbol,Bool}}
    isempty(keys) && _argerror(:arrange, "no sort keys", Text("no keys"),
        "Name at least one column, for example arrange(t, :a) or arrange(t, desc(:a)).")
    Tuple{Symbol,Bool}[k isa Desc ? (k.name, true) : _iskey(k) ? (Symbol(k), false) :
        _argerror(:arrange, "not a sort key", k, "Use a column name such as :a, or " *
            "desc(:a); give each key as its own argument.") for k in keys]
end

"""
    arrange(t, keys...; by_group = false)
    arrange(keys...; by_group = false)

Sort the rows of `t` by one or more keys. A key is a column name (`:a` or
`"a"`) for ascending order, or `desc(:a)` for descending order. The sort is
stable: rows that tie keep their input order, and later keys break ties of
earlier ones.

`missing` comes last in both directions. `NaN` comes after `Inf` in ascending
order and first in descending order. `-0.0` and `0.0` are the same key, so they
tie. Strings sort by Unicode code point, not by locale, and `false` comes
before `true`. Each key column needs one element type, apart from `missing`,
that `isless` can compare, such as numbers, strings, symbols or dates.

`by_group = true` is for grouped tables and is an error on a plain `Table`. The
result never shares columns with the input.

# Examples
```jldoctest
julia> using TableOps

julia> t = Table(; a = [3, 1, 2], b = ["x", "y", "z"]);

julia> pull(arrange(t, desc(:a)), :b)
3-element Vector{String}:
 "x"
 "z"
 "y"

julia> pull(t |> arrange(:a), :b)
3-element Vector{String}:
 "y"
 "z"
 "x"
```
"""
function arrange(x, rest...; by_group = false)
    g = _checkflag(:arrange, :by_group, by_group)
    _istable(x) && return _arrange(_table(x, :arrange), _sortkeys(rest), g)
    _iskey(x) || _firstarg(:arrange, x, "a sort key", "keys such as arrange(:a, desc(:b))")
    keys = _sortkeys((x, rest...))
    t -> _arrange(_table(t, :arrange), keys, g)
end

arrange(; by_group = false) = (_checkflag(:arrange, :by_group, by_group); _sortkeys(()))

function _arrange(t::Table, keys, by_group::Bool)::Table
    by_group && _argerror(:arrange, "by_group needs a grouped table",
        Text("by_group = true"), "Use group_by first, or leave out by_group.")
    _take(t, _arrange_rows(:arrange, t, keys))
end

function _arrange_rows(verb::Symbol, t::Table, keys)::Vector{Int}
    for (name, _) in keys
        _checksortable(verb, name, _column(t, name, verb))
    end
    p = collect(1:nrow(t))
    for (name, d) in Iterators.reverse(keys)
        p = _sortpass(_column(t, name, verb), p, d)
    end
    p
end

function _checksortable(verb::Symbol, name::Symbol, col::AbstractVector)
    S = nonmissingtype(eltype(col))
    S === Union{} || (isconcretetype(S) && hasmethod(isless, Tuple{S,S})) ||
        _argerror(verb, "a sort key has no order",
            Text("$name with element type $(eltype(col))"),
            "Sort keys need one element type that isless can compare, such as " *
            "numbers, strings or dates; convert the column first.")
end

_nz(x) = x
_nz(x::AbstractFloat) = iszero(x) ? zero(x) : x
_sortkey(col::AbstractVector) = col
_sortkey(col::AbstractVector{<:Union{Missing,AbstractFloat}}) = map(_nz, col)

# Missing keys are set aside so that they stay last.
_sortpass(col::AbstractVector{Missing}, p::Vector{Int}, rev::Bool) = p
function _sortpass(col::AbstractVector{T}, p::Vector{Int}, rev::Bool) where {T}
    g = _gather(_sortkey(col), p)
    T === nonmissingtype(T) && return p[sortperm(g; rev)]
    present = findall(!ismissing, g)
    vals = collect(skipmissing(g))
    vcat(p[present[sortperm(vals; rev)]], p[findall(ismissing, g)])
end

"""
    distinct(t, picks...; keep_all = false)
    distinct(picks...; keep_all = false)

Keep the first row of each distinct key, in the original order. The key is
the columns that `picks` pick (any column picker, see [`resolve`](@ref)); with
no picks it is every column. The result has the picked columns in pick order;
with `keep_all = true` it has every column of `t`, taken from the first row
of each key.

Keys are equal when they are `isequal` (so `missing` is one value and `NaN`
equals `NaN`), with one addition: `-0.0` equals `0.0`, and the value of the
first row is kept. A pick that picks no column is an error, because a table without
columns has no rows. The result never shares columns with the input.

# Examples
```jldoctest
julia> using TableOps

julia> d = Table(; a = [1, 2, 1], b = ["x", "y", "x"]);

julia> pull(distinct(d, :a), :a)
2-element Vector{Int64}:
 1
 2

julia> nrow(d |> distinct())
2
```
"""
function distinct(x, rest...; keep_all = false)
    k = _checkflag(:distinct, :keep_all, keep_all)
    _istable(x) && return _distinct(_table(x, :distinct), rest, k)
    picks = _pickers(:distinct, x, rest, "pickers such as distinct(:a, :b)")
    t -> _distinct(_table(t, :distinct), picks, k)
end

function distinct(; keep_all = false)
    k = _checkflag(:distinct, :keep_all, keep_all)
    t -> _distinct(_table(t, :distinct), (), k)
end

function _distinct(t::Table, picks::Tuple, keep_all::Bool)::Table
    isempty(picks) && ncol(t) == 0 && return _take(t, Int[])
    names = isempty(picks) ? getfield(t, :names) : _pickall(:distinct, picks, t)
    isempty(names) && _argerror(:distinct, "no columns picked", Text("an empty selection"),
        "Name at least one column, or call distinct(t) for all of them.")
    kcols = AbstractVector[_column(t, n, :distinct) for n in names]
    _take(keep_all ? t : _newtable(copy(names), kcols), _firstrows(kcols))
end

# Codes by first appearance; -0.0 and 0.0 are one key.
function _codes(col::AbstractVector{T}) where {T}
    d = Dict{T,Int}()
    codes = Vector{Int}(undef, length(col))
    for i in eachindex(col)
        codes[i] = get!(d, _nz(col[i]), length(d) + 1)
    end
    codes, length(d)
end

function _combine(a::Vector{Int}, b::Vector{Int}, nb::Int)
    d = Dict{Int,Int}()
    out = similar(a)
    for i in eachindex(a)
        out[i] = get!(d, (a[i] - 1) * nb + b[i], length(d) + 1)
    end
    out, length(d)
end

# Phase 4 replaces the body by encode_keys(cols).
function _firstrows(cols::Vector{AbstractVector})
    codes, k = _codes(cols[1])
    for j in 2:length(cols)
        c, nc = _codes(cols[j])
        codes, k = _combine(codes, c, nc)
    end
    rows = Vector{Int}(undef, k)
    seen = 0
    for i in eachindex(codes)
        codes[i] > seen && (seen += 1; rows[seen] = i)
    end
    rows
end

_isrowno(x) = x isa Integer && !(x isa Bool)

# Wide integers stay as given for the range error.
function _rownumbers(rows)
    _isrowno(rows) && return [rows]
    ok = rows isa AbstractVector && !(eltype(rows) <: Bool) &&
        (eltype(rows) <: Integer && !(Bool <: eltype(rows)) || all(_isrowno, rows))
    ok || _argerror(:slice, "row numbers must be integers", rows,
        "Pass integers such as slice(t, 2:3) or slice(t, [1, 3]); " *
        "use where to keep rows by a Bool condition.")
    rows
end

# Mixed integer types compare exactly, with no conversion.
function _checkrows(rows::AbstractVector, N::Int)
    isempty(rows) && return
    lo, hi = extrema(rows)
    1 <= lo && hi <= N && return
    _badrow(rows, N)
end

# findfirst fails on ranges whose length overflows Int.
function _badrow(rows::AbstractVector, N::Int)
    for r in rows
        (r < 1 || r > N) && _argerror(:slice, "row number out of range", r,
            N == 0 ? "The table has no rows." : "The table has $N rows, numbered 1 to $N.")
    end
end

_asint(rows::Union{AbstractUnitRange{Int},Vector{Int}}) = rows
_asint(rows::AbstractVector) = Vector{Int}(rows)

function _slice(t::Table, rows::AbstractVector)::Table
    _checkrows(rows, nrow(t))
    _take(t, _asint(rows))
end

"""
    slice(t, rows)
    slice(rows)

Keep the rows of `t` with the given row numbers. `rows` is one integer, a
range or a vector of integers (any integer type, but not `Bool`). The rows come
in the order given and duplicates are kept, so `slice(t, [3, 1, 1])` returns
row 3, then row 1 twice. A number outside `1:nrow(t)` (zero, negative or too
large) is an error that shows the first bad number and the valid range. There
are no negative numbers to drop rows, and a `Bool` vector is an error: to keep
rows by a condition use [`where`](@ref).

In the pipe form the row numbers are checked when `slice(rows)` is called and
their range when the result is applied to a table. The result never shares
columns with the input.

# Examples
```jldoctest
julia> using TableOps

julia> t = Table(; a = [3, 1, 2], b = ["x", "y", "z"]);

julia> pull(slice(t, [3, 1]), :b)
2-element Vector{String}:
 "z"
 "x"

julia> pull(t |> slice(2:3), :b)
2-element Vector{String}:
 "y"
 "z"
```
"""
slice(t, rows) = _slice(_table(t, :slice), _rownumbers(rows))
function slice(rows)
    r = copy(_rownumbers(rows))
    t -> _slice(_table(t, :slice), r)
end

function _checkn(verb::Symbol, n)
    n === nothing && _argerror(verb, "n is required", Text("no n"),
        "Write, for example, n = 3.")
    n isa Integer && !(n isa Bool) && n >= 0 || _argerror(verb,
        "n must be a whole number of 0 or more", n, "Write, for example, n = 3.")
    Int(min(n, typemax(Int)))
end

"""
    slice_head(t; n)
    slice_head(; n)

Keep the first `n` rows of `t`, in their order. `n` is a whole number of 0 or
more (any integer type, but not `Bool`) and is required. `n = 0` gives no rows
and keeps the column types; an `n` larger than the number of rows returns all
rows. The result never shares columns with the input.

# Examples
```jldoctest
julia> using TableOps

julia> t = Table(; a = [3, 1, 2], b = ["x", "y", "z"]);

julia> pull(slice_head(t; n = 2), :b)
2-element Vector{String}:
 "x"
 "y"

julia> pull(t |> slice_head(; n = 1), :b)
1-element Vector{String}:
 "x"
```
"""
function slice_head(t; n = nothing)
    _slice_head(_table(t, :slice_head), _checkn(:slice_head, n))
end
function slice_head(; n = nothing)
    k = _checkn(:slice_head, n)
    t -> _slice_head(_table(t, :slice_head), k)
end
_slice_head(t::Table, n::Int) = _take(t, 1:min(n, nrow(t)))

"""
    slice_tail(t; n)
    slice_tail(; n)

Keep the last `n` rows of `t`, in their original order (not reversed). `n` is
a whole number of 0 or more (any integer type, but not `Bool`) and is
required. `n = 0` gives no rows and keeps the column types; an `n` larger than
the number of rows returns all rows. The result never shares columns with the
input.

# Examples
```jldoctest
julia> using TableOps

julia> t = Table(; a = [3, 1, 2], b = ["x", "y", "z"]);

julia> pull(slice_tail(t; n = 2), :b)
2-element Vector{String}:
 "y"
 "z"

julia> pull(t |> slice_tail(; n = 1), :b)
1-element Vector{String}:
 "z"
```
"""
function slice_tail(t; n = nothing)
    _slice_tail(_table(t, :slice_tail), _checkn(:slice_tail, n))
end
function slice_tail(; n = nothing)
    k = _checkn(:slice_tail, n)
    t -> _slice_tail(_table(t, :slice_tail), k)
end
function _slice_tail(t::Table, n::Int)
    N = nrow(t)
    _take(t, N - min(n, N) + 1:N)
end
