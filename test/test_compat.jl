import Tables, CSV, Arrow, DataFrames

@testset "compat" begin
    t = Table(; id = [1, 2, 3], name = ["a", "b", "c"], x = [1.5, missing, 3.0])

    @test isequal(Table(Tables.columntable(t)), t)
    @test isequal(Table(Tables.rowtable(t)), t)
    eltypes(x) = Type[eltype(col) for col in getfield(x, :columns)]
    want = Type[Int, String, Union{Missing,Float64}]
    @test eltypes(Table(Tables.columntable(t))) == want
    @test eltypes(Table(Tables.rowtable(t))) == want

    c = Table(CSV.File(IOBuffer("id,name\n1,a\n2,b\n")))
    @test names(c) == [:id, :name] && c.id == [1, 2] && c.name == ["a", "b"]
    b = IOBuffer(); CSV.write(b, t)
    tc = Table(CSV.File(IOBuffer(take!(b))))
    @test isequal(tc, t)                       # CSV strings are its own vector type
    @test eltype(tc.id) == Int && eltype(tc.x) == Union{Missing,Float64}
    @test eltype(tc.name) <: AbstractString

    a = IOBuffer(); Arrow.write(a, t); seekstart(a)
    ta = Table(Arrow.Table(a))
    @test isequal(ta.x, t.x) && ta.name == t.name

    df = DataFrames.DataFrame(t)
    @test isequal(Table(df), t)
    @test eltypes(Table(df)) == want
    @test getfield(Table(df), :columns)[1] === df.id
    @test isequal(DataFrames.DataFrame(Table(df)), df)

    @testset "zero rows" begin
        z = Table(; a = Int[], b = String[], c = Union{Missing,Float64}[])
        zd = Table(DataFrames.DataFrame(z))
        @test names(zd) == [:a, :b, :c] && nrow(zd) == 0
        @test eltype(zd.a) == Int && eltype(zd.b) == String
        @test eltype(zd.c) == Union{Missing,Float64}
        @test isequal(zd, z)

        io = IOBuffer(); Arrow.write(io, z); seekstart(io)
        za = Table(Arrow.Table(io))
        @test names(za) == [:a, :b, :c] && nrow(za) == 0
        @test eltype(za.a) == Int && eltype(za.b) == String
        @test eltype(za.c) == Union{Missing,Float64}
    end

    @testset "Unicode and spaced names" begin
        u = Table(; var"unit price" = [1.5, 2.5], 名前 = ["a", "b"])
        ud = DataFrames.DataFrame(u)
        @test DataFrames.names(ud) == ["unit price", "名前"]
        @test isequal(Table(ud), u)

        io = IOBuffer(); Arrow.write(io, u); seekstart(io)
        ua = Table(Arrow.Table(io))
        @test names(ua) == [Symbol("unit price"), :名前]
        @test ua.var"unit price" == [1.5, 2.5] && ua.名前 == ["a", "b"]
    end

    @testset "all-missing column" begin
        m = Table(; k = [1, 2], v = Union{Missing,Int}[missing, missing])
        md = DataFrames.DataFrame(m)
        @test eltype(md.v) == Union{Missing,Int}
        mb = Table(md)
        @test isequal(mb, m)
        @test eltype(mb.v) == Union{Missing,Int} && all(ismissing, mb.v)
    end

    @testset "copycols = false shares vectors" begin
        d = DataFrames.DataFrame(t; copycols = false)
        @test d.id === t.id && d.name === t.name && d.x === t.x
    end

    @testset "columntable keeps missing eltype" begin
        ct = Tables.columntable(t)
        @test eltype(ct.x) == Union{Missing,Float64}
        @test ct.x === t.x
        @test isequal(ct.x, [1.5, missing, 3.0])
    end
end
