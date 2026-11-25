using Test
using TableOps
import Aqua

@testset "TableOps" begin
    include("test_errors.jl")

    @testset "Aqua quality checks" begin
        Aqua.test_all(TableOps; ambiguities=false)
        Aqua.test_ambiguities(TableOps)
    end
end
