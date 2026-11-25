"""
    TableOps

Fast, tidyverse-style table verbs for any Tables.jl table.
"""
module TableOps

import Tables

export Table

include("errors.jl")
include("table.jl")

end
