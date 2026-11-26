_firstarg(verb::Symbol, x, what::String, example::String) = _argerror(verb,
    "the first argument is neither a table nor $what", x,
    "Pass a table, or $example for the pipe form.")

_badvalue(verb::Symbol, key::Symbol, value) = _argerror(verb,
    "the value of $key must be a column name", value, "Write $verb(t; new = :old).")

function _dupname(names::Vector{Symbol})::Union{Symbol,Nothing}
    seen = Set{Symbol}()
    for n in names
        n in seen && return n
        push!(seen, n)
    end
    nothing
end

_kwname(n::Symbol) = Base.isidentifier(n) ? String(n) : "var\"$n\""

_isname(x) = x isa Union{Symbol,AbstractString}

# A vector of non-names may be a row table, not a picker.
function _pickers(verb::Symbol, x, rest::Tuple, example::String)::Tuple
    _ispicker(x) && (!(x isa AbstractVector) || all(_isname, x)) ||
        _firstarg(verb, x, "a column picker", example)
    for p in rest
        _ispicker(p) || _notpicker(verb, p)
        p isa AbstractVector && foreach(n -> _isname(n) || _notnames(verb, n), p)
    end
    (x, rest...)
end

function _checkvalues(verb::Symbol, renames)
    for (new, old) in pairs(renames)
        _isname(old) || _badvalue(verb, new, old)
    end
end

"""
    select(t, picks...; new = :old, ...)
    select(picks...; new = :old, ...)

A table with the columns that `picks` pick, in the order they are picked,
followed by the keyword columns `new = :old`, each of which adds the column
`old` again under the name `new`. A column picked twice appears once; a column
that is both picked and renamed appears under both names. Columns are shared
with `t`, not copied. A pick is any column picker (see [`resolve`](@ref)); an
empty result or two columns with the same name is an error. The second form
returns a function of a table, for use with `|>`.

# Examples
```jldoctest
julia> using TableOps

julia> t = Table(; a = [1, 2], b = ["x", "y"], c = [1.5, 2.5]);

julia> names(select(t, :c, :a))
2-element Vector{Symbol}:
 :c
 :a

julia> names(select(t, startswith("b"); total = :c))
2-element Vector{Symbol}:
 :b
 :total

julia> names(t |> select(:a))
1-element Vector{Symbol}:
 :a
```
"""
function select(x, rest...; kw...)
    _istable(x) && return _select(_table(x, :select), rest, kw)
    picks = _pickers(:select, x, rest, "pickers such as select(:a, :b)")
    _checkvalues(:select, kw)
    t -> select(_table(t, :select), picks...; kw...)
end

function select(; kw...)
    isempty(kw) && _nopicks()
    _checkvalues(:select, kw)
    t -> select(_table(t, :select); kw...)
end

_nopicks() = _argerror(:select, "no columns picked", Text("an empty selection"),
    "Name at least one column, or use everything() for all of them.")

function _select(t::Table, picks::Tuple, renames)::Table
    _checkvalues(:select, renames)
    cols = getfield(t, :columns)
    names = _pickall(:select, picks, t)
    idx = Int[_position(t, n, :select) for n in names]
    for (new, old) in pairs(renames)
        push!(idx, _position(t, Symbol(old), :select))
        push!(names, new)
    end
    isempty(idx) && _nopicks()
    d = _dupname(names)
    d === nothing || _argerror(:select, "two columns would have the same name", d,
        "Rename one of them or leave it out.")
    _newtable(names, AbstractVector[cols[i] for i in idx])
end

"""
    rename(t; new = :old, ...)
    rename(; new = :old, ...)

A table with the column `old` called `new`, for each keyword, in the same
place. Renames apply together, so `rename(t; a = :b, b = :a)` swaps two
names. Columns are shared with `t`, not copied. Giving a column two new
names, or two columns the same name, is an error. The second form returns a
function of a table, for use with `|>`.

# Examples
```jldoctest
julia> using TableOps

julia> t = Table(; a = [1, 2], b = ["x", "y"], c = [1.5, 2.5]);

julia> names(rename(t; x = :a))
3-element Vector{Symbol}:
 :x
 :b
 :c

julia> names(t |> rename(; a = :b, b = :a))
3-element Vector{Symbol}:
 :b
 :a
 :c
```
"""
rename(t; kw...) = _rename(_table(t, :rename), kw)
function rename(; kw...)
    _checkvalues(:rename, kw)
    t -> rename(_table(t, :rename); kw...)
end
rename(p::Pair; kw...) = _renamepair(p)
rename(t, extra, more...; kw...) = _renamepair(extra)

_renamepair(p) = _argerror(:rename, "renames are keywords", p,
    "Write rename(t; new = :old).")

function _rename(t::Table, renames)::Table
    names = copy(getfield(t, :names))
    _checkvalues(:rename, renames)
    done = Dict{Int,Symbol}()
    for (new, old) in pairs(renames)
        i = _position(t, Symbol(old), :rename)
        if haskey(done, i)
            prev = done[i]
            _argerror(:rename, "a column cannot get two new names", Symbol(old),
                "Rename it once, then add a copy: mutate(rename(t; " *
                "$(_kwname(prev)) = $(repr(Symbol(old)))); " *
                "$(_kwname(new)) = $(repr(prev))).")
        end
        done[i] = new
        names[i] = new
    end
    d = _dupname(names)
    d === nothing || _argerror(:rename, "two columns would have the same name", d,
        "Rename the other one too, or drop it first with select.")
    _newtable(names, copy(getfield(t, :columns)))
end

"""
    relocate(t, picks...; before = nothing, after = nothing)
    relocate(picks...; before = nothing, after = nothing)

A table with the columns that `picks` pick moved to the front, in the order
they are picked, or just before the column `before`, or just after the column
`after`. The other columns keep their order. Columns are shared with `t`, not
copied. Giving both `before` and `after`, or an anchor that is one of the
moved columns, is an error. The second form returns a function of a table,
for use with `|>`.

# Examples
```jldoctest
julia> using TableOps

julia> t = Table(; a = [1, 2], b = ["x", "y"], c = [1.5, 2.5]);

julia> names(relocate(t, :c))
3-element Vector{Symbol}:
 :c
 :a
 :b

julia> names(t |> relocate(:a; after = :b))
3-element Vector{Symbol}:
 :b
 :a
 :c
```
"""
function relocate(x, rest...; before = nothing, after = nothing)
    _istable(x) && return _relocate(_table(x, :relocate), rest, before, after)
    picks = _pickers(:relocate, x, rest, "pickers such as relocate(:a; after = :b)")
    _anchor(before, after)
    t -> relocate(_table(t, :relocate), picks...; before, after)
end

function relocate(; before = nothing, after = nothing)
    _anchor(before, after)
    t -> relocate(_table(t, :relocate); before, after)
end

function _anchor(before, after)::Union{Symbol,Nothing}
    before === nothing || after === nothing || _argerror(:relocate,
        "before and after cannot both be given",
        Text("before = $(repr(before)), after = $(repr(after))"),
        "Use only one of them.")
    anchor = before === nothing ? after : before
    anchor === nothing && return nothing
    _isname(anchor) || _argerror(:relocate, "the anchor must be a column name",
        anchor, "Write before = :a or after = :a.")
    Symbol(anchor)
end

function _relocate(t::Table, picks::Tuple, before, after)::Table
    anchor = _anchor(before, after)
    anchor === nothing || _position(t, anchor, :relocate)
    moved = _pickall(:relocate, picks, t)
    anchor in moved && _argerror(:relocate,
        "the anchor is also one of the columns to move", anchor,
        "Choose an anchor that stays where it is.")
    gone = Set(moved)
    rest = Symbol[n for n in getfield(t, :names) if !(n in gone)]
    order = if anchor === nothing
        vcat(moved, rest)
    else
        k = findfirst(==(anchor), rest)::Int
        cut = before === nothing ? k : k - 1
        vcat(rest[1:cut], moved, rest[cut + 1:end])
    end
    cols = getfield(t, :columns)
    _newtable(order, AbstractVector[cols[_position(t, n, :relocate)] for n in order])
end

"""
    pull(t, col)
    pull(col)

The column `col` (a `Symbol` or `String`) of `t` as a vector. The vector is
the one `t` holds, not a copy: changing it changes `t`. The second form
returns a function of a table, for use with `|>`.

# Examples
```jldoctest
julia> using TableOps

julia> t = Table(; a = [1, 2], b = ["x", "y"]);

julia> pull(t, :b)
2-element Vector{String}:
 "x"
 "y"

julia> t |> pull(:a)
2-element Vector{Int64}:
 1
 2
```
"""
pull(t, col) = _pull(_table(t, :pull), col)
function pull(col)
    _colname(:pull, col)
    t -> pull(t, col)
end

_colname(verb::Symbol, x::Union{Symbol,AbstractString}) = Symbol(x)
_colname(verb::Symbol, x) = _argerror(verb, "needs a column name", x,
    "Write pull(t, :a); to use a position write pull(t, names(t)[1]).")

_pull(t::Table, col)::AbstractVector = _column(t, _colname(:pull, col), :pull)

"""
    mutate(t, specs...; name = spec, ...)
    mutate(specs...; name = spec, ...)

A table with the columns that the keyword specifications compute, added at the
end, or replacing the column of the same name in its place. Specifications run
in the order written and each sees the table with all earlier results, so
`mutate(t; b = :a => each(x -> x + 1), c = :b)` works. The specifications are:

| Spec | Meaning |
|---|---|
| `name = :a` | a copy of column `a` |
| `name = :a => f` | `f(a)`, a function of the whole column |
| `name = [:a, :b] => f` | `f(a, b)` |
| `name = :a => each(f)` | `f` applied to each element of `a` |
| `name = t -> …` | a function of the table so far |
| `name = value` | a constant, repeated for every row |
| `name = vector` | a new column, one value per row |

A `Symbol` on the right of `name =` is a column, a `String` is a constant.
A result of length 1 is repeated for every row; any other length except the row
count is an error. A result that is not a `Vector` (a range, a view) is
copied into one. A result that is a column of the table is copied, so two
columns never share a vector; a vector you pass that is not a column of the table
is kept as it is, not copied, as in `Table`. A result with an abstract element
type, such as `Vector{Any}`, becomes a vector of the one concrete type it
holds (plus `missing`), or `Vector{Missing}` when it holds no value other than
`missing`; a mixture of types is an error. A tuple, `NamedTuple`, matrix,
generator, set or dictionary is an error, not a constant: write `name = [x]` to
put one in every row. Unchanged columns are shared with `t`.
A specification without a name, such as `mutate(t, :a => sum)`, is an error.
A table with no columns has no rows. The second form returns a function of
a table, for use with `|>`.

# Examples
```jldoctest
julia> using TableOps

julia> t = Table(; a = [1, 2], b = ["x", "y"], c = [1.5, 2.5]);

julia> pull(mutate(t; d = :a => each(x -> x + 1)), :d)
2-element Vector{Int64}:
 2
 3

julia> pull(mutate(t; total = [:a, :c] => (a, c) -> a .+ c), :total)
2-element Vector{Float64}:
 2.5
 4.5

julia> pull(mutate(t; region = "EU"), :region)
2-element Vector{String}:
 "EU"
 "EU"
```
"""
function mutate(x, rest...; kw...)
    if _istable(x)
        _mutate(_table(x, :mutate), _specs(:mutate, rest, kw))
    else
        _ispositional(x) || _firstarg(:mutate, x, "a column specification",
            "specifications such as mutate(c = :a)")
        specs = _specs(:mutate, (x, rest...), kw)
        t -> _mutate(_table(t, :mutate), specs)
    end
end

function mutate(; kw...)
    specs = _specs(:mutate, (), kw)
    t -> _mutate(_table(t, :mutate), specs)
end

function _mutate(t::Table, specs::Vector{ColSpec})::Table
    for s in specs
        t = _setcolumn(t, s.name, _finish(:mutate, s.name, _run(s, t, :mutate), t))
    end
    t
end

function _finish(verb::Symbol, name::Symbol, r, t::Table)::Vector
    n = nrow(t)
    v = _concrete(verb, name, _asvector(verb, name, r, n))
    if length(v) != n
        length(v) == 1 || _badlength(verb, name, length(v), t, n)
        v = _recycle(v, n)
    end
    any(c -> Base.mightalias(c, v), getfield(t, :columns)) ? copy(v) : v
end

function _asvector(verb::Symbol, name::Symbol, r, n::Int)::Vector
    r isa Vector && return r
    if r isa AbstractVector
        Base.has_offset_axes(r) && _argerror(verb,
            "column $name does not use 1-based indexing", axes(r),
            "Convert it to a 1-based vector, for example with collect.")
        return Vector(r)
    end
    _checkvalue(verb, r)
    fill(r, n)
end

function _concrete(verb::Symbol, name::Symbol, v::Vector{T})::Vector where {T}
    U = nonmissingtype(T)
    (T === Missing || isconcretetype(U)) && return v
    S, miss = _scantypes(verb, name, v)
    S === nothing ? Vector{Missing}(v) : _narrow(v, S, miss)
end

# Stops at the second type so the error names two.
function _scantypes(verb::Symbol, name::Symbol, v::Vector)
    S, miss = nothing, false
    for x in v
        if x === missing
            miss = true
        elseif S === nothing
            S = typeof(x)
        elseif typeof(x) !== S
            _argerror(verb, "a column mixes element types",
                Text("$name holds $S and $(typeof(x))"),
                "Make the function return one type, for example by converting inside it.")
        end
    end
    S, miss
end

_narrow(v::Vector, ::Type{S}, miss::Bool) where {S} =
    miss ? Vector{Union{Missing,S}}(v) : Vector{S}(v)

function _recycle(v::Vector{T}, n::Int)::Vector{T} where {T}
    out = Vector{T}(undef, n)
    fill!(out, v[1])
    out
end

_badlength(verb::Symbol, name::Symbol, len::Int, t::Table, n::Int) = _argerror(verb,
    "a column has the wrong length", Text("$name has $len rows, the table has $n"),
    isempty(getfield(t, :columns)) ?
    "Build a table from vectors with Table(; name = vector)." :
    "Return a single value (repeated for every row) or exactly $n values.")

function _setcolumn(t::Table, name::Symbol, v::Vector)::Table
    names, cols = copy(getfield(t, :names)), copy(getfield(t, :columns))
    i = get(getfield(t, :lookup), name, 0)
    if i == 0
        push!(names, name)
        push!(cols, v)
    else
        cols[i] = v
    end
    _newtable(names, cols)
end
