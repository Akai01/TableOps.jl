using Test, TableOps
isdefined(@__MODULE__, :same_table) || include("checks.jl")

@testset "checks" begin
    a, b = Table(; x = Int[]), Table(; x = Float64[])
    @test isequal(a, b)                              # Base semantics (Phase 1 note)
    @test !same_table(a, b)                          # element types are compared
    @test same_table(a, copy(a))
    @test !same_table(Table(; x = [1], y = [2]), Table(; y = [2], x = [1]))
    @test !same_table(Table(; x = [1]), Table(; x = [2]))
    @test !same_table(Table(; x = [1]), Table(; x = [1.0]))      # == but not same type
    @test same_table(Table(; x = [missing, 1.0]), Table(; x = [missing, 1.0]))
    @test same_table(Table(; x = [NaN]), Table(; x = [NaN]))
    @test same_table(Table(), Table())
    @test !same_table(Table(; x = [1]), Table(; x = [1], y = [2]))

    t = Table(; x = [1, 2], y = ["a", "b"])
    s = snapshot(t)
    @test unchanged(t, s)
    getfield(t, :columns)[1][1] = 9                  # in place
    @test !unchanged(t, s)
    t2 = Table(; x = [1, 2]); s2 = snapshot(t2)
    getfield(t2, :columns)[1] = [1, 2]               # replaced by an equal vector
    @test !unchanged(t2, s2)
    t3 = Table(; x = [1]); s3 = snapshot(t3); push!(getfield(t3, :names), :z)
    @test !unchanged(t3, s3)

    for T in (Int, String, Union{Missing,Int}, Missing, Vector{Int}, Float64)
        @test is_concrete_eltype(T)
    end
    for T in (Any, Real, Union{Int,String}, Union{Missing,Real}, Number)
        @test !is_concrete_eltype(T)
    end
    # a stand-in verb with both forms
    fake(t, c) = TableOps._newtable([c], AbstractVector[[1, 2]])
    fake(c) = t -> fake(t, c)
    @test same_table(check_forms_agree(fake, t, :q), Table(; q = [1, 2]))
    @test check_input_unchanged(x -> x, t) === t
    rows = [(a = 1, b = 2), (a = 3, b = 4)]      # Table(rows) makes new columns
    @test check_input_unchanged(x -> x, rows) isa Table
    check_concrete_eltypes(t)
end
