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
