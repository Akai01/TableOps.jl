"""
    TableOps

Fast, tidyverse- and SQL-style table verbs for any Tables.jl table.
"""
module TableOps

import Tables

export Table, as_table, nrow, ncol, glimpse
export AbstractSelector, resolve, everything, of_type, except
export each
export select, rename, relocate, pull, mutate
export where, arrange, desc, distinct
export slice, slice_head, slice_tail, slice_min, slice_max

include("errors.jl")
include("table.jl")
include("show.jl")
include("selectors.jl")
include("specs.jl")
include("columns.jl")
include("rows.jl")

end
