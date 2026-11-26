# TableOps.jl

Fast, tidyverse- and SQL-style table verbs for any
[Tables.jl](https://github.com/JuliaData/Tables.jl) table, in pure Julia with Tables.jl as the only dependency.

!!! warning "In development"
    TableOps is being built; the planned API is in the [Design](design.md) page.

```@docs
TableOps
Table
as_table
nrow
ncol
glimpse
```

## Column pickers

```@docs
AbstractSelector
resolve
everything
of_type
except
```

## Column specifications

```@docs
each
```

## Column verbs

```@docs
select
TableOps.rename
relocate
pull
mutate
```

## Row verbs

```@docs
TableOps.where
arrange
desc
distinct
slice
slice_head
slice_tail
```
