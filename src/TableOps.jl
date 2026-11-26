"""
    TableOps

Fast, tidyverse-style table verbs for any Tables.jl table.
"""
module TableOps

import Tables

export Table, as_table, nrow, ncol, glimpse

include("errors.jl")
include("table.jl")
include("show.jl")

end
