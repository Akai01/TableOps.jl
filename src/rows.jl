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
