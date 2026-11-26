using Test, TableOps

@testset "errors" begin
    err = try TableOps._argerror(:select, "column not found", :revenu,
                                 "Did you mean :revenue?") catch e e end
    @test err isa ArgumentError
    @test err.msg == "select: column not found. Got :revenu. Did you mean :revenue?"
    err = try TableOps._argerror(:Table, "input is not a table", Int64, "Fix.")
          catch e e end
    @test err.msg == "Table: input is not a table. Got Int64. Fix."
    long = try TableOps._argerror(:v, "w", repeat("x", 200), "f") catch e e end
    @test length(long.msg) < 100 && occursin("…", long.msg)

    lev = TableOps._levenshtein
    @test lev(collect("kitten"), collect("sitting")) == 3
    @test lev(Char[], collect("abc")) == 3
    @test lev(collect("é名"), collect("e名")) == 1

    s = TableOps._suggest
    @test s(:revenu, [:revenue, :region]) === :revenue
    @test s(:Revenue, [:revenue, :region]) === :revenue      # case only
    @test s(:re, [:rev, :reg]) === nothing                   # length 2: case only
    @test s(:revx, [:rev1, :rev2]) === nothing               # two candidates
    @test s(:a, [:b]) === nothing                            # too short to guess
    @test s(:A, [:a]) === :a
    @test s(:zzz, Symbol[]) === nothing
    @test s(:Ärger, [:ärger, :b]) === :ärger                 # Unicode, case only
    @test s(Symbol(""), [:a]) === nothing                    # empty name
    @test (@inferred Union{Symbol,Nothing} TableOps._suggest(:abc, [:abd])) === :abd
    @test s(Symbol("unit prise"), [Symbol("unit price")]) === Symbol("unit price")
    @test @inferred(lev(collect("ab"), collect("ba"))) == 2

    @testset "boundaries" begin
        s = TableOps._suggest
        @test TableOps._levenshtein(collect("reveneu"), collect("revenue")) == 2
        @test s(:reveneu, [:revenue, :region]) === :revenue
        @test TableOps._levenshtein(collect("abcdef"), collect("abcxyz")) == 3
        @test s(:abcdef, [:abcxyz]) === nothing
        @test s(:abcd, [:abxy]) === nothing
        @test s(:revenue, [:Revenue, :revenuf]) === nothing

        got(v) = TableOps._argerror(:v, "w", v, "f")
        msg(v) = try got(v) catch e e.msg end
        @test msg(repeat("x", 58)) == "v: w. Got \"" * repeat("x", 58) * "\". f"
        @test msg(repeat("x", 59)) == "v: w. Got \"" * repeat("x", 58) * "…. f"
        m = msg(collect(1:1000))
        @test endswith(m, "…. f") && length(m) < 100
        @test msg(Text("a has 3 rows, b has 2")) == "v: w. Got a has 3 rows, b has 2. f"
        @test msg(Text(repeat("y", 100))) == "v: w. Got " * repeat("y", 100) * ". f"
    end
end
