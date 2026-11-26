# One column spec: f of the input columns, or of the table.
struct ColSpec{F,C<:Tuple}
    name::Symbol
    inputs::Vector{Symbol}
    f::F
    calls::C
end

struct Each{F}
    f::F
end

Base.show(io::IO, e::Each) = print(io, "each(", e.f, ")")

(e::Each)(cols::AbstractVector...) = map(e.f, cols...)

"""
    each(f)

Apply `f` element by element in a column specification, as in
`:a => each(f)`. With several columns, `[:a, :b] => each(f)` calls `f` on
the values of one row at a time.

# Examples
```jldoctest
julia> using TableOps

julia> each(x -> x * 2)([1, 2])
2-element Vector{Int64}:
 2
 4
```
"""
each(f::Function) = Each(f)
each(x) = _argerror(:each, "needs a function", x,
    "Write each(f), for example :a => each(round).")

_ispositional(x) = x isa Union{Symbol,Pair,Each}

function _specs(verb::Symbol, args::Tuple, kwargs; allow_unnamed::Bool = false)
    out = ColSpec[]
    for x in args
        _ispositional(x) || _argerror(verb, "not a valid column specification", x,
            "Use :col, :col => f, [:a, :b] => f, :col => each(f), name = :col, " *
            "name = value or name = t -> ….")
        s = _spec(verb, Symbol(""), x)
        allow_unnamed || _argerror(verb, "a column specification needs a name", x,
            "Write name = $(_fmt_value(x)).")
        push!(out, s)
    end
    for (name, x) in pairs(kwargs)
        push!(out, _spec(verb, name, x))
    end
    out
end

_spec(verb::Symbol, name::Symbol, x::Symbol) = ColSpec(name, [x], identity, ())
_spec(verb::Symbol, name::Symbol, x::Function) = ColSpec(name, Symbol[], x, ())
_spec(verb::Symbol, name::Symbol, x::Each) = _argerror(verb,
    "each(f) needs a column to work on", Text("each(f)"), "Write :col => each(f).")

function _spec(verb::Symbol, name::Symbol, x::Pair)
    inputs = _inputs(verb, x.first)
    x.second isa Union{Function,Each} || _argerror(verb,
        "the right side of => must be a function or each(f)", x.second,
        "Write :a => f, where f takes whole columns, " *
        "or :a => each(f) to apply f to each element.")
    ColSpec(name, inputs, x.second, ())
end

function _spec(verb::Symbol, name::Symbol, x)
    if x isa Tuple || (x isa AbstractArray && !(x isa AbstractVector))
        _argerror(verb, "a value must be a single value or a vector", x,
            "Pass a vector with one value per row, " *
            "or wrap one tuple or array in a vector: name = [x].")
    end
    ColSpec(name, Symbol[], Returns(x), ())
end

_inputs(verb::Symbol, x::Union{Symbol,AbstractString}) = Symbol[Symbol(x)]
function _inputs(verb::Symbol, x::AbstractVector)
    ok = !isempty(x) && all(n -> n isa Union{Symbol,AbstractString}, x)
    ok || _badinputs(verb, x)
    Symbol[Symbol(n) for n in x]
end
_inputs(verb::Symbol, x) = _badinputs(verb, x)

_badinputs(verb::Symbol, x) = _argerror(verb,
    "the left side of => must be a column name or a non-empty vector of names", x,
    "Write :a => f or [:a, :b] => f.")

function _run(s::ColSpec, t::Table, verb::Symbol)
    isempty(s.inputs) && return s.f isa Returns ? s.f(nothing) : s.f(t)
    s.f(AbstractVector[_column(t, c, verb) for c in s.inputs]...)
end
