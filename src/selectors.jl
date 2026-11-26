"""
    AbstractSelector

The supertype of column pickers such as `everything()`, `of_type(T)` and
`except(...)`. To add a picker, subtype it and add a method of the one public
signature

    resolve(selector, t::Table)::Vector{Symbol}

which returns the picked names, in order and without repeats. It may look at
`names(t)` and at the element types of the columns of `t`.

# Examples
```jldoctest
julia> using TableOps

julia> import TableOps: resolve

julia> struct LastColumn <: AbstractSelector end

julia> resolve(::LastColumn, t::Table) = [last(names(t))];

julia> resolve(LastColumn(), Table(; a = [1], b = [2]))
1-element Vector{Symbol}:
 :b

julia> select(Table(; a = [1], b = [2]), LastColumn())
1×1 Table
     b
 Int64
 ─────
     2
```
"""
abstract type AbstractSelector end

struct Everything <: AbstractSelector end
struct OfType{T} <: AbstractSelector end
struct Except{P<:Tuple} <: AbstractSelector
    picks::P
end

"""
    everything()

A column picker for every column of the table, in table order.

# Examples
```jldoctest
julia> using TableOps

julia> resolve(everything(), Table(; a = [1], b = [2]))
2-element Vector{Symbol}:
 :a
 :b
```
"""
everything() = Everything()

"""
    of_type(T)

A column picker for the columns whose element type is a subtype of `T`.
`missing` is ignored: a `Union{Missing,Float64}` column is a `Float64` column.
A column whose element type is `Missing` (such as `[missing, missing]`) is
picked only by an `of_type(T)` with `Missing <: T`. An empty column of element
type `Union{}` is picked by every `of_type`. `Bool` is an `Integer`, so
`of_type(Integer)` picks `Bool` columns too; use `of_type(Int)` to avoid it.

# Examples
```jldoctest
julia> using TableOps

julia> t = Table(; a = [1, 2], b = [1.5, missing], c = ["x", "y"]);

julia> resolve(of_type(Real), t)
2-element Vector{Symbol}:
 :a
 :b
```
"""
of_type(::Type{T}) where {T} = OfType{T}()
of_type(x) = _argerror(:of_type, "needs a type", x, "Write of_type(Int) or of_type(Real).")

"""
    except(picks...)

A column picker for every column that none of `picks` picks. Each pick is any
column picker; a name that is not a column is an error.

# Examples
```jldoctest
julia> using TableOps

julia> resolve(except(:a), Table(; a = [1], b = [2], c = [3]))
2-element Vector{Symbol}:
 :b
 :c
```
"""
except(picks...) = Except(picks)

const _Plain = Union{Symbol,AbstractString,AbstractVector,Function}

"""
    resolve(picker, t::Table)

The names of the columns of `t` that `picker` picks, as a `Vector{Symbol}`.
A picker is a name (`Symbol` or `String`), a vector of names, a predicate on
the column name as a `String` (`startswith("re")`, `endswith`, `contains`, or
any function that returns `true` or `false`), `everything()`, `of_type(T)`,
`except(picks...)` or a subtype of [`AbstractSelector`](@ref). A name that is
not a column is an error; a predicate that picks nothing gives an empty vector.
A name in a vector appears once, at its first place.

# Examples
```jldoctest
julia> using TableOps

julia> t = Table(; revenue = [1], region = [2], cost = [3]);

julia> resolve(startswith("re"), t)
2-element Vector{Symbol}:
 :revenue
 :region

julia> resolve(of_type(Int), t)
3-element Vector{Symbol}:
 :revenue
 :region
 :cost
```
"""
function resolve end

function resolve(sel, t)
    t isa Table || throw(MethodError(resolve, (sel, t)))
    sel isa AbstractSelector && _argerror(:resolve, "a selector needs a resolve method",
        Text(string(typeof(sel))),
        "Define TableOps.resolve(::$(typeof(sel)), t::Table) returning the picked names.")
    _notpicker(:resolve, sel)
end
resolve(sel::_Plain, t::Table)::Vector{Symbol} = _resolve(:resolve, sel, t)
resolve(sel::Except, t::Table)::Vector{Symbol} = _resolve(:resolve, sel, t)
resolve(::Everything, t::Table)::Vector{Symbol} = copy(getfield(t, :names))
function resolve(::OfType{T}, t::Table)::Vector{Symbol} where {T}
    Symbol[n for (n, c) in zip(getfield(t, :names), getfield(t, :columns))
           if _hastype(c, T)]
end

_notpicker(verb::Symbol, x) = _argerror(verb, "not a column picker", x,
    "Use a name, a vector of names, a predicate such as startswith(\"a\") " *
    "or contains(r\"^q\"), everything(), of_type(T) or except(...).")

_notnames(verb::Symbol, x) = _argerror(verb,
    "a vector of columns holds only names", x,
    "Put Symbols or Strings in the vector; " *
    "give a predicate or picker as its own argument.")

_ispicker(x) = x isa Union{Symbol,AbstractString,AbstractVector,Function,AbstractSelector}

# The verb names the caller in errors.
function _resolve(verb::Symbol, sel::AbstractSelector, t::Table)
    out = Vector{Symbol}(resolve(sel, t))
    for n in out
        _position(t, n, verb)
    end
    unique!(out)
end
_resolve(verb::Symbol, sel, t::Table) = _notpicker(verb, sel)
function _resolve(verb::Symbol, sel::Symbol, t::Table)
    _position(t, sel, verb)
    Symbol[sel]
end
_resolve(verb::Symbol, sel::AbstractString, t::Table) = _resolve(verb, Symbol(sel), t)
function _resolve(verb::Symbol, sel::AbstractVector, t::Table)
    out = Symbol[]
    for x in sel
        x isa Union{Symbol,AbstractString} || _notnames(verb, x)
        append!(out, _resolve(verb, Symbol(x), t))
    end
    unique!(out)
end
function _resolve(verb::Symbol, sel::Function, t::Table)
    out = Symbol[]
    for n in getfield(t, :names)
        r = sel(String(n))
        r isa Bool || _argerror(verb, "a column predicate must return true or false",
            Text("$(repr(String(n))) gave $(repr(r))"),
            "Return a Bool, for example startswith(\"rev\") or n -> length(n) > 3.")
        r && push!(out, n)
    end
    out
end
function _resolve(verb::Symbol, sel::Except, t::Table)
    gone = Set(_pickall(verb, sel.picks, t))
    Symbol[n for n in getfield(t, :names) if !(n in gone)]
end

_pickall(verb::Symbol, picks::Tuple, t::Table)::Vector{Symbol} =
    unique!(reduce(vcat, (_resolve(verb, p, t) for p in picks); init = Symbol[]))

function _hastype(col::AbstractVector, ::Type{T}) where {T}
    E = eltype(col)
    U = nonmissingtype(E)
    (U === Union{} ? E : U) <: T
end
