"""
    TableOps

Fast, tidyverse-style table verbs for any Tables.jl table.
"""
module TableOps

import Tables

export Table, as_table, nrow, ncol, glimpse
export AbstractSelector, resolve, everything, of_type, except

include("errors.jl")
include("table.jl")
include("show.jl")
include("selectors.jl")

end
