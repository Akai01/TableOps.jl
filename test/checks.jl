using Test, TableOps

msg(f) = try f(); nothing catch e e isa ArgumentError ? e.msg : rethrow() end

function same_table(a, b)
    na, nb = getfield(a, :names), getfield(b, :names)
    na == nb || return false
    ca, cb = getfield(a, :columns), getfield(b, :columns)
    for i in eachindex(ca)
        eltype(ca[i]) === eltype(cb[i]) && isequal(ca[i], cb[i]) || return false
    end
    return true
end

function snapshot(t)
    t = Table(t)
    cols = collect(AbstractVector, getfield(t, :columns))
    return (copy(getfield(t, :names)), cols, map(copy, cols), copy(getfield(t, :lookup)))
end

function unchanged(t, snap)
    t = Table(t)
    names, cols, vals, lookup = snap
    getfield(t, :names) == names || return false
    getfield(t, :lookup) == lookup || return false
    cur = getfield(t, :columns)
    length(cur) == length(cols) || return false
    return all(i -> cur[i] === cols[i] && isequal(cur[i], vals[i]), eachindex(cols))
end

is_concrete_eltype(T::Type) = T === Missing || isconcretetype(nonmissingtype(T))

function check_forms_agree(verb, t, args...; kw...)
    y = verb(t, args...; kw...)
    @test same_table(y, verb(args...; kw...)(t))
    return y
end

function check_input_unchanged(f, t)
    t = Table(t)
    snap = snapshot(t)
    y = f(t)
    @test unchanged(t, snap)
    return y
end

function check_concrete_eltypes(t)
    t = Table(t)
    bad = [n for (n, c) in zip(getfield(t, :names), getfield(t, :columns))
           if !is_concrete_eltype(eltype(c))]
    @test bad == Symbol[]
end
