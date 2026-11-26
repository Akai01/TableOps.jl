using Test
using TableOps
import Aqua

@testset "TableOps" begin
    include("test_errors.jl")
    include("test_table.jl")
    include("test_show.jl")
    include("test_compat.jl")

    @testset "Aqua quality checks" begin
        Aqua.test_all(TableOps; ambiguities=false)
        Aqua.test_ambiguities(TableOps)
    end
end
