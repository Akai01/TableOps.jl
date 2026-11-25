function _fmt_value(value)
    s = value isa Type ? string(value) : repr(value; context = :limit => true)
    length(s) > 60 ? first(s, 59) * "…" : s
end

function _argerror(verb::Symbol, what::String, value, fix::String)
    throw(ArgumentError("$verb: $what. Got $(_fmt_value(value)). $fix"))
end

function _levenshtein(a::Vector{Char}, b::Vector{Char})::Int
    prev = collect(0:length(b))
    cur = similar(prev)
    for i in eachindex(a)
        cur[1] = i
        for j in eachindex(b)
            cost = a[i] == b[j] ? 0 : 1
            cur[j + 1] = min(prev[j + 1] + 1, cur[j] + 1, prev[j] + cost)
        end
        prev, cur = cur, prev
    end
    prev[end]
end

function _suggest(name::Symbol, names::Vector{Symbol})::Union{Symbol,Nothing}
    a = collect(lowercase(String(name)))
    n = length(a)
    limit = n <= 2 ? 0 : n <= 5 ? 1 : 2
    found = nothing
    for c in names
        _levenshtein(a, collect(lowercase(String(c)))) <= limit || continue
        found === nothing || return nothing
        found = c
    end
    found
end
