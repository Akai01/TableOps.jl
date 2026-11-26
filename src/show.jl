const _MAXWIDTH = 20

# Cut to w columns, ending in "…".
function _cutto(s::AbstractString, w::Int)::String
    textwidth(s) <= w && return String(s)
    out = IOBuffer()
    used = 0
    for c in s
        cw = textwidth(c)
        used + cw > w - 1 && break
        used += cw
        print(out, c)
    end
    print(out, '…')
    String(take!(out))
end

_cap(s::AbstractString) = _cutto(s, _MAXWIDTH)

function _escape(s::String)::String
    all(isprint, s) && return s
    join(isprint(c) ? string(c) : escape_string(string(c)) for c in s)
end

# :limit stops a huge cell from printing in full.
function _plain(x)::String
    s = x isa AbstractString ? String(x) :
        sprint(print, x; context = (:compact => true, :limit => true))
    _escape(s)
end

_cell(x) = ismissing(x) ? "missing" : _cap(_plain(x))

# A nullable label keeps its "?" when the type name is cut.
function _typelabel(T::Type)::String
    T isa Union && Missing <: T ? _cutto(string(nonmissingtype(T)), _MAXWIDTH - 1) * "?" :
        _cap(string(T))
end

_name(n::Symbol) = _cap(_escape(String(n)))

function _isreal(T::Type)::Bool
    S = nonmissingtype(T)
    S !== Union{} && S <: Real
end

# Function barrier: row 0 stands for the "⋮" row.
function _cells(col::AbstractVector, rows::Vector{Int})
    cells = Vector{String}(undef, length(rows))
    miss = falses(length(rows))
    for (k, i) in enumerate(rows)
        if i == 0
            cells[k] = "⋮"
        else
            x = col[i]
            cells[k] = _cell(x)
            miss[k] = x === missing
        end
    end
    cells, miss
end

struct _ShowCol
    name::String
    type::String
    cells::Vector{String}
    miss::BitVector
    right::Bool
    width::Int
end

function _showcol(name::Symbol, col::AbstractVector, rows::Vector{Int})
    cells, miss = _cells(col, rows)
    n = _name(name)
    ty = _typelabel(eltype(col))
    w = max(textwidth(n), textwidth(ty), maximum(textwidth, cells; init = 0))
    _ShowCol(n, ty, cells, miss, _isreal(eltype(col)), w)
end

function _rowindex(n::Int, budget::Int)::Vector{Int}
    n <= budget && return collect(1:n)
    vcat(1:cld(budget, 2), 0, (n - fld(budget, 2) + 1):n)
end

# A line is pieces of (text, grey); padding is plain text.
function _parts(cols::Vector{_ShowCol}, text)
    parts = Tuple{String,Bool}[(" ", false)]
    for (k, c) in enumerate(cols)
        k > 1 && push!(parts, ("  ", false))
        s, grey = text(c)
        gap = " "^(c.width - textwidth(s))
        c.right && push!(parts, (gap, false))
        push!(parts, (s, grey))
        c.right || push!(parts, (gap, false))
    end
    parts
end

function _putline(io::IO, parts::Vector{Tuple{String,Bool}})
    while !isempty(parts) && all(==(' '), parts[end][1])
        pop!(parts)
    end
    for (k, (s, grey)) in enumerate(parts)
        s = k == length(parts) ? rstrip(s) : s
        grey ? printstyled(io, s; color = :light_black) : print(io, s)
    end
end

_title(t::Table) = "$(nrow(t))×$(ncol(t)) Table"

Base.show(io::IO, t::Table) = print(io, _title(t))

function Base.show(io::IO, ::MIME"text/plain", t::Table)
    print(io, _title(t))
    nms = getfield(t, :names)
    isempty(nms) && return
    height, width = displaysize(io)
    limit = get(io, :limit, false)::Bool
    rows = _rowindex(nrow(t), limit ? max(height - 7, 2) : typemax(Int))
    cols = getfield(t, :columns)
    shown = _ShowCol[]
    used = 1
    for j in eachindex(nms)
        c = _showcol(nms[j], cols[j], rows)
        need = used + c.width + (isempty(shown) ? 0 : 2)
        !limit || isempty(shown) || need <= width || break
        push!(shown, c)
        used = need
    end
    print(io, '\n')
    _putline(io, _parts(shown, c -> (c.name, false)))
    print(io, '\n')
    _putline(io, _parts(shown, c -> (c.type, false)))
    print(io, '\n', " ", "─"^(used - 1))
    for r in eachindex(rows)
        print(io, '\n')
        _putline(io, _parts(shown, c -> (c.cells[r], c.miss[r])))
    end
    hidden = length(nms) - length(shown)
    hidden == 0 && return
    list = join((_escape(String(n)) for n in nms[(length(shown) + 1):end]), ", ")
    noun = hidden == 1 ? "column" : "columns"
    print(io, '\n', _cutto("… and $hidden more $noun: $list", width))
end

# Keeps room for ", …" so no value is cut in half.
function _glimpse_values(col::AbstractVector, avail::Int)
    cells = String[]
    miss = Bool[]
    used = 0
    for x in col
        c = _cell(x)
        add = textwidth(c) + (isempty(cells) ? 0 : 2)
        used + add > avail && break
        push!(cells, c)
        push!(miss, x === missing)
        used += add
    end
    length(cells) == length(col) && return cells, miss, ""
    while !isempty(cells) && sum(textwidth, cells) + 2 * length(cells) + 1 > avail
        pop!(cells)
        pop!(miss)
    end
    cells, miss, isempty(cells) ? "…" : ", …"
end

_padright(s::String, w::Int) = s * " "^(w - textwidth(s))

"""
    glimpse(x)
    glimpse(io::IO, x)

Print a compact overview of the table `x`, any Tables.jl table: the size,
then one line per column with its name, its element type and its first
values, as many as fit in the width of `io` (the terminal for `glimpse(x)`).
Returns `nothing`. Names, types and values wider than 20 columns are cut
with `…`, and `Union{Missing,T}` is shown as `T?`.

# Examples
```jldoctest
julia> using TableOps

julia> glimpse(Table(; a = [1, 2, 3], b = ["x", "y", "z"]))
3×2 Table
 a  Int64   1, 2, 3
 b  String  x, y, z
```
"""
function glimpse end

function glimpse(io::IO, x)
    t = _table(x)
    println(io, _title(t))
    nms = getfield(t, :names)
    isempty(nms) && return nothing
    width = displaysize(io)[2]
    cols = getfield(t, :columns)
    labels = String[_name(n) for n in nms]
    types = String[_typelabel(eltype(c)) for c in cols]
    wn = maximum(textwidth, labels)
    wt = maximum(textwidth, types)
    for j in eachindex(nms)
        prefix = " " * _padright(labels[j], wn) * "  " * _padright(types[j], wt) * "  "
        cells, miss, tail = _glimpse_values(cols[j], width - textwidth(prefix))
        if isempty(cells)
            println(io, _cutto(rstrip(prefix * tail), width))
            continue
        end
        parts = Tuple{String,Bool}[(prefix, false)]
        for (k, c) in enumerate(cells)
            k > 1 && push!(parts, (", ", false))
            push!(parts, (c, miss[k]))
        end
        push!(parts, (tail, false))
        _putline(io, parts)
        println(io)
    end
    nothing
end

glimpse(x) = glimpse(stdout, x)
