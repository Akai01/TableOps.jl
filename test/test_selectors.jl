using Test, TableOps
isdefined(@__MODULE__, :same_table) || include("checks.jl")

struct LastName <: AbstractSelector end
struct Unannotated <: AbstractSelector end
struct NoMethod <: AbstractSelector end
struct Fixed <: AbstractSelector; v::Vector{Symbol} end
TableOps.resolve(::Unannotated, t) = [:a]
TableOps.resolve(s::Fixed, t::Table) = s.v
struct SameNames <: AbstractSelector end
TableOps.resolve(::SameNames, t::Table) = getfield(t, :names)
TableOps.resolve(::LastName, t::Table) = [last(names(t))]

mk(nm) = Table(; (n => [1] for n in nm)...)                  # one row, Int columns

@testset "exports do not clash with Base" begin
    for n in names(TableOps)
        @test !Base.isexported(Base, n)
    end
end

@testset "resolve" begin
    r = resolve
    nm = [:revenue, :region, :cost, :q1, :q5, :Q2]
    t = mk(nm)
    @test r(:cost, t) == [:cost]
    @test r("cost", t) == [:cost]
    @test r([:cost, "region", :cost], t) == [:cost, :region]     # once, first place
    @test r(Symbol[], t) == Symbol[]
    @test r(startswith("re"), t) == [:revenue, :region]
    @test r(endswith("t"), t) == [:cost]
    @test r(contains("ven"), t) == [:revenue]
    @test r(contains(r"^q[1-4]$"), t) == [:q1]
    @test r(n -> length(n) == 2, t) == [:q1, :q5, :Q2]
    @test r(startswith("zz"), t) == Symbol[]                     # empty, no error
    @test r(everything(), t) == nm
    @test r(everything(), t) !== getfield(t, :names)             # a copy
    @test r(except(:cost, "q1"), t) == [:revenue, :region, :q5, :Q2]
    @test r(except(startswith("q"), :cost), t) == [:revenue, :region, :Q2]
    @test r(except(), t) == nm
    @test r(except(except(:cost)), t) == [:cost]
    @test r(except(everything()), t) == Symbol[]
    @test r(LastName(), t) == [:Q2]
    @test r(except(LastName()), t) == nm[1:end-1]
    @test @inferred(r(startswith("re"), t)) == [:revenue, :region]
    @test @inferred(r(everything(), t)) == nm
    @test @inferred(r(of_type(Real), t)) == nm
    @test @inferred(r(except(:cost), t)) == [:revenue, :region, :q1, :q5, :Q2]
    @test @inferred(r(:cost, t)) == [:cost]
    u = mk([Symbol("unit price"), :名前])
    @test r(Symbol("unit price"), u) == [Symbol("unit price")]
    @test r("名前", u) == [:名前]
    @test r(everything(), Table()) == Symbol[]                   # no columns

    typed = Table(; i = [1], f = [1.5], s = ["x"], m = [missing],
                    uf = Union{Missing,Float64}[1.0], any = Any[1], b = Bool[true])
    all7 = [:i, :f, :s, :m, :uf, :any, :b]
    @test r(of_type(Real), typed) == [:i, :f, :uf, :b]
    @test r(of_type(Integer), typed) == [:i, :b]                 # Bool <: Integer
    @test r(of_type(Int), typed) == [:i]
    @test r(of_type(AbstractString), typed) == [:s]
    @test r(of_type(Missing), typed) == [:m]                     # all-missing column
    @test r(of_type(Any), typed) == all7
    @test r(except(of_type(Real)), typed) == [:s, :m, :any]
    @test r([:i, "s"], typed) == [:i, :s]
    @test r(of_type(Real), Table()) == Symbol[]
    @test r(of_type(Real), Table(; a = Int[], s = String[])) == [:a]   # no rows
    @test of_type(Int) isa AbstractSelector && everything() isa AbstractSelector

    @test msg(() -> r(:zz, t)) ==
        "resolve: column not found. Got :zz. " *
        "Available columns: :revenue, :region, :cost, :q1, :q5, :Q2."
    @test msg(() -> r(:revenu, t)) ==
        "resolve: column not found. Got :revenu. Did you mean :revenue?"
    @test msg(() -> r("zz", t)) ==
        "resolve: column not found. Got :zz. " *
        "Available columns: :revenue, :region, :cost, :q1, :q5, :Q2."
    @test msg(() -> r(except(:zz), t)) == msg(() -> r(:zz, t))
    @test msg(() -> r(:a, Table())) ==
        "resolve: column not found. Got :a. The table has no columns."
    @test msg(() -> r([:a, 1], mk([:a]))) ==
        "resolve: a vector of columns holds only names. Got 1. " *
        "Put Symbols or Strings in the vector; give a predicate or picker as " *
        "its own argument."
    @test startswith(msg(() -> r([startswith("a")], mk([:a]))),
        "resolve: a vector of columns holds only names. Got ")
    @test msg(() -> r(n -> missing, mk([:a]))) ==
        "resolve: a column predicate must return true or false. " *
        "Got \"a\" gave missing. " *
        "Return a Bool, for example startswith(\"rev\") or n -> length(n) > 3."
    @test msg(() -> r(n -> 1, mk([:a]))) ==
        "resolve: a column predicate must return true or false. " *
        "Got \"a\" gave 1. " *
        "Return a Bool, for example startswith(\"rev\") or n -> length(n) > 3."
    @test msg(() -> r(n -> "x"^100, mk([:a]))) ==
        "resolve: a column predicate must return true or false. " *
        "Got \"a\" gave \"" * "x"^58 * "…. " *
        "Return a Bool, for example startswith(\"rev\") or n -> length(n) > 3."
    @test msg(() -> of_type(1)) ==
        "of_type: needs a type. Got 1. Write of_type(Int) or of_type(Real)."
    @test msg(() -> TableOps._resolve(:select, 5, t)) ==
        "select: not a column picker. Got 5. " *
        "Use a name, a vector of names, a predicate such as startswith(\"a\") " *
        "or contains(r\"^q\"), everything(), of_type(T) or except(...)."
    @test msg(() -> TableOps._resolve(:select, r"^q", t)) ==          # Regex alone
        "select: not a column picker. Got r\"^q\". Use a name, a vector of names, " *
        "a predicate such as startswith(\"a\") or contains(r\"^q\"), " *
        "everything(), of_type(T) or except(...)."
    @test msg(() -> TableOps._resolve(:select, except(:zz), t)) ==     # verb reaches except
        "select: column not found. Got :zz. " *
        "Available columns: :revenue, :region, :cost, :q1, :q5, :Q2."
    @test msg(() -> r(5, t)) ==
        "resolve: not a column picker. Got 5. " *
        "Use a name, a vector of names, a predicate such as startswith(\"a\") " *
        "or contains(r\"^q\"), everything(), of_type(T) or except(...)."
    @test_throws MethodError r(:a, [:a, :b])                     # names alone: no method
end

@testset "catch-all resolve" begin
    t = mk([:a, :b])
    @test resolve(Unannotated(), t) == [:a]
    @test TableOps._resolve(:select, Unannotated(), t) == [:a]
    want = "resolve: a selector needs a resolve method. Got NoMethod. " *
        "Define TableOps.resolve(::NoMethod, t::Table) returning the picked names."
    @test msg(() -> resolve(NoMethod(), t)) == want
    @test msg(() -> TableOps._resolve(:select, NoMethod(), t)) == want
    @test_throws MethodError resolve(NoMethod(), [:a])
    @test Test.detect_ambiguities(TableOps) == []
end

@testset "user selector names are checked" begin
    t = mk([:a, :b])
    bad = "select: column not found. Got :zz. Available columns: :a, :b."
    @test msg(() -> TableOps._resolve(:select, Fixed([:zz, :a]), t)) == bad
    @test msg(() -> TableOps._resolve(:select, except(Fixed([:zz, :a])), t)) == bad
    @test TableOps._resolve(:select, Fixed([:b, :a, :b]), t) == [:b, :a]
end

@testset "_pickall order" begin
    t = mk([:revenue, :region, :cost, :q1, :q5, :Q2])
    @test TableOps._pickall(:select, (:q1, everything(), :cost), t) ==
        [:q1, :revenue, :region, :cost, :q5, :Q2]
end

@testset "user selector result is copied" begin
    t = mk([:a, :b])
    got = TableOps._resolve(:select, SameNames(), t)
    @test got == [:a, :b]
    @test got !== getfield(t, :names)
end

@testset "_position and _notfound" begin
    @test TableOps._position(Table(; a = [1]), :a, :select) == 1
    @test TableOps._position(Table(; a = [1], b = [2]), :b, :select) == 2
    @test msg(() -> TableOps._position(Table(; a = [1]), :b, :select)) ==
        "select: column not found. Got :b. Available columns: :a."
    @test msg(() -> TableOps._notfound(:select, :revenu, [:a, :revenue])) ==
        "select: column not found. Got :revenu. Did you mean :revenue?"
end
