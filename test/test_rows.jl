using Test, TableOps, StableRNGs
isdefined(@__MODULE__, :same_table) || include("checks.jl")
rn(x) = getfield(x, :names)
rc(x) = getfield(x, :columns)
rint(rng, n, hi) = [Base.rand(rng, 1:hi) for _ in 1:n]

@testset "_gather and _take" begin
    cols = (Int => [10, 20, 30], Float64 => [1.5, NaN, 3.5],
            String => ["a", "b", "c"],
            Union{Missing,Float64} => Union{Missing,Float64}[1.0, missing, 3.0])
    for (T, c) in cols
        @test @inferred(TableOps._gather(c, [3, 1, 1])) isa Vector{T}
        @test @inferred(TableOps._gather(c, 2:3)) isa Vector{T}
        @test isequal(TableOps._gather(c, [3, 1, 1]), c[[3, 1, 1]])
        @test isequal(TableOps._gather(c, 2:3), c[2:3])
        @test TableOps._gather(c, Int[]) isa Vector{T}
        @test isempty(TableOps._gather(c, Int[]))
        @test TableOps._gather(c, [1]) !== c
    end
    @test TableOps._gather(view([1, 2, 3], 1:3), [2]) isa Vector{Int}
    @test TableOps._gather(1:3, [3, 2]) == [3, 2]
    @test TableOps._gather([10, 20, 30], Base.IdentityUnitRange(2:3)) == [20, 30]
    @test TableOps._gather(BitVector([true, false]), [2, 1]) isa Vector{Bool}
    @test TableOps._gather(Union{Missing,Int}[1, 2], [2]) isa Vector{Union{Missing,Int}}
    @test TableOps._gather([missing, missing], [1]) isa Vector{Missing}
    @test_throws BoundsError TableOps._gather([1, 2], [3])
    @test_throws BoundsError TableOps._gather([1, 2], [0])

    t = Table(; a = [1, 2, 3], b = ["x", "y", "z"])
    r = TableOps._take(t, [3, 1])
    @test same_table(r, Table(; a = [3, 1], b = ["z", "x"]))
    @test rc(r)[1] !== rc(t)[1]
    @test rc(r)[2] !== rc(t)[2]
    @test rn(r) !== rn(t)
    @test getfield(r, :lookup) !== getfield(t, :lookup)
    @test same_table(TableOps._take(t, 1:3), t)
    @test rc(TableOps._take(t, 1:3))[1] !== rc(t)[1]
    @test same_table(TableOps._take(t, Int[]), Table(; a = Int[], b = String[]))
    @test nrow(TableOps._take(Table(), Int[])) == 0
    @test ncol(TableOps._take(Table(), Int[])) == 0
    @test @inferred(TableOps._take(t, [1])) isa Table
    u = Table(; var"unit price" = [1.0, 2.0], 名前 = ["x", "y"])
    @test rn(TableOps._take(u, [2])) == [Symbol("unit price"), :名前]
    check_input_unchanged(x -> TableOps._take(x, [2, 2]), t)
    w = Table(; a = [1], m = [missing], f = [1.5, 2.5][1:1])
    check_concrete_eltypes(TableOps._take(w, [1]))
end
