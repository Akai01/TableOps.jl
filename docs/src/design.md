# Design

This page is the design of TableOps.jl: what it does, how each verb behaves and
why. It is the reference for contributors. Where a rule rests on published work,
the [References](#References) section lists the source; rules with no such
support are marked *(own choice)*.

## Goals

TableOps brings tidyverse- and SQL-style data manipulation to Julia: easy to read, fast,
and correct. Six principles decide every design question, in this order when
they conflict:

1. **Scientifically, statistically and methodologically correct.** No result is
   silently wrong. Missing values are never dropped or invented without the user
   asking.
2. **A good user experience.** One clear name per operation, safe defaults,
   errors that say what went wrong and how to fix it.
3. **Fast.** Quick to load, quick on the first call, quick on large tables.
4. **Light.** Pure Julia; Tables.jl is the only dependency.
5. **Compatible.** Any Tables.jl table goes in; every result is a Tables.jl
   table, so CSV.jl, Arrow.jl, DataFrames.jl and the rest work with it.
6. **Julia 1.10 and later.**

The names follow the tidyverse and SQL. The implementation is original: no code
is read from, translated from or modelled on another package.

## A first example

```julia
using TableOps

dt = (store = ["A", "A", "B"], date = [1, 2, 1], revenue = [10.0, 20.0, 5.0])

# Macro form: bare column names.
@select(dt, store, date, revenue) |> @group_by(store) |>
    @summarize(store_revenue = sum(revenue))

# Function form: the same result.
select(dt, :store, :date, :revenue) |> group_by(:store) |>
    summarize(store_revenue = :revenue => sum)
```

## Scope

Version 0.1 contains everything below.

| Area | Functions |
|---|---|
| Table | `Table`, `as_table`, `glimpse`, `nrow`, `ncol`, `names`, `copy`, printing |
| Columns | `select`, `rename`, `relocate`, `mutate`, `pull` |
| Column pickers | any name predicate (`startswith("x")`, `endswith`, `contains` with a string or a `Regex`, a function), `everything()`, `of_type(T)`, `except(cols...)` |
| Rows | `where`, `arrange`, `desc`, `distinct`, `slice`, `slice_head`, `slice_tail`, `slice_min`, `slice_max`, `slice_sample` |
| Groups | `GroupedTable`, `group_by`, `ungroup`, `summarize` (alias `summarise`), `tally`, `across` |
| Helpers | `n_distinct`, `lag`, `lead`, `row_number`, `min_rank`, `dense_rank`, `percent_rank`, `cume_dist`, `ntile`, `between`, `case_when`, `each` (and `n()` inside macros) |
| Windows | `rolling_sum`, `rolling_mean`, `rolling_min`, `rolling_max`, `rolling_var`, `rolling_std`, `rolling` |
| Joins | `inner_join`, `left_join`, `right_join`, `full_join`, `semi_join`, `anti_join`, `cross_join` |
| Combine | `bind_rows`, `bind_cols`, `union`, `intersect`, `setdiff` |
| Reshape | `pivot_longer`, `pivot_wider`, `separate`, `unite` |
| Missing values | `drop_missing`, `replace_missing`, `fill_missing`, `complete` |
| Nesting | `nest`, `unnest` |
| Panels | `PanelTable`, `panel_id`, `panel_time`, `nseries`, `series_ids`, `has_gaps`, `fill_gaps` |
| Macros | one per verb: `@select`, `@where`, `@mutate`, `@summarize`, … |
| Extension | `AbstractSelector`, `resolve`, `window_function`, `grouped_reduce` |

Out of scope: reading and writing files (CSV.jl, Arrow.jl and others already
produce Tables.jl tables), plotting, and SQL strings.

Julia already has `ifelse`, `coalesce`, `cumsum`, `accumulate`, `skipmissing`,
`startswith`, `endswith` and `contains`; TableOps uses them and does not add its
own versions.

The extension functions are exported because Julia 1.10 has no `public`
keyword.

### Statistics

`mean`, `median`, `var`, `std` and `quantile` live in the Statistics standard
library. TableOps does not depend on it: a package extension (`[weakdeps]`
Statistics) adds the single-pass `grouped_reduce` methods for `mean`, `var` and
`std` when the user loads Statistics. Without it, any function still works
through the generic per-group path.

### SQL to TableOps

| SQL | TableOps |
|---|---|
| `SELECT a, b` | `select` |
| `WHERE` | `where` |
| `GROUP BY` | `group_by` |
| `SUM()`, `AVG()`, `COUNT(*)` | `summarize`, `tally` |
| `HAVING` | `where` after `summarize` |
| `ORDER BY` | `arrange` |
| `SELECT DISTINCT` | `distinct` |
| `LIMIT` | `slice_head` |
| `INNER/LEFT/RIGHT/FULL JOIN` | `inner_join`, `left_join`, `right_join`, `full_join` |
| `CROSS JOIN` | `cross_join` |
| `WHERE x IN (SELECT …)` | `semi_join` |
| `WHERE x NOT IN (SELECT …)` | `anti_join` |
| `UNION ALL` / `UNION` | `bind_rows` / `union` |
| `INTERSECT` / `EXCEPT` | `intersect` / `setdiff` |
| `CASE WHEN` | `case_when` |
| `COALESCE` | `coalesce.` |
| window `LAG`, `LEAD`, `ROW_NUMBER`, `RANK` | `lag`, `lead`, `row_number`, `min_rank` |

## Core types

### `Table`

An immutable table that stores its columns without type parameters:

- `names::Vector{Symbol}`
- `columns::Vector{AbstractVector}`
- a `Dict{Symbol,Int}` from name to position

All columns have the same length and all names are unique; the constructor
checks both. The storage is deliberately untyped so that a verb that changes the
set of columns does not trigger new compilation (see [Performance](#Performance)).

- `Table(x)` accepts any Tables.jl table (column or row access) and keeps the
  source's column vectors as they are, without copying.
- `Table(; a = [1, 2], b = ["x", "y"])` builds a table from keyword columns.
- `t.revenue` returns a column, whatever the column is called (internal code
  uses `getfield`, so a column named `names` or `columns` is fine).
  `names(t)` returns a `Vector{Symbol}` *(own choice, as Tables.jl)*;
  `nrow(t)` and `ncol(t)` give the size.
- `copy(t)` copies every column, so changing a column of the copy leaves `t`
  unchanged. The copy is shallow: mutable values inside cells (a vector in a
  cell, say) are shared.
- `Table` implements the Tables.jl column interface (`Tables.istable`,
  `Tables.columnaccess`, `Tables.columns`, `Tables.getcolumn`,
  `Tables.columnnames`, `Tables.schema`).
- Printing shows the size, each column's name and element type, and the first
  and last rows, cut to the display size. `glimpse(t)` shows one line per
  column.

Columns a verb creates are plain `Vector`s with a specific element type, never
`Vector{Any}`; a column that holds `missing` is `Vector{Union{Missing,T}}`.

### `GroupedTable`

A `Table` (or a `PanelTable`) plus its group columns and a group index computed
once by `group_by`:

- the group number of every row,
- the rows ordered by group,
- the first row of each group in that order,
- the number of groups.

`summarize`, `mutate`, `where`, the `slice_*` verbs and the window helpers reuse
this index; none recomputes it. `ungroup` returns the parent table.

### `PanelTable`

A table of several time series: a `Table` plus its `id` columns (zero or more;
zero means a single series) and one `time` column. See [Panels](#Panels).

## The three forms of every verb

1. **Table first:** `select(dt, :store, :date)`. `dt` may be any Tables.jl
   table; anything other than a TableOps type is wrapped with `Table(dt)`.
2. **Pipe:** `select(:store, :date)` returns a function of a table, so
   `dt |> select(:store) |> group_by(:store)` works.
3. **Macro:** `@select(dt, store, date)` or `dt |> @select(store, date)`.

The table-first and pipe forms are told apart by dispatch on the first argument:
a TableOps type, or any `x` with `Tables.istable(x)`, is the table. A join or
`bind_rows` with a single table argument is the pipe form:
`x |> left_join(y; by = :id)`.

Exception: the set operations `union`, `intersect` and `setdiff` extend Julia's
own functions for TableOps tables and have no pipe form, because `union(x)`
already has a meaning in Julia.

The macros only rewrite their arguments into the function form; they add no
behaviour of their own.

### Column specifications in the function form

A function always receives **whole columns**:

| Spec | Meaning |
|---|---|
| `:revenue` | the column |
| `:revenue => sum` | `sum(revenue)` |
| `[:revenue, :cost] => (r, c) -> r .- c` | a function of several columns |
| `name = spec` | the result is called `name` (in `mutate`, `summarize`) |
| `name = :other` | a copy of column `other` under a new name |
| `name = vector` | a new column, if its length is the row count (`mutate`) |
| `name = value` | any other value is a constant, repeated for every row (`mutate`) |
| `name = t -> …` | a function of the (group's) sub-table |

`each(f)` applies `f` element by element, for short elementwise specs:
`where(t, :revenue => each(>(100)))`, `mutate(t, r = :revenue => each(round))`
*(own choice)*.

Column names may be `Symbol`s or `String`s in pickers and on the left of a
`=>`. On the right of `name =`, only a `Symbol` names a column: a `String` there
is a constant (`mutate(t, region = "EU")`). A vector whose length is neither 1
nor the row count is an error. A tuple, `NamedTuple`, matrix, set,
dictionary, table, generator, `skipmissing`, `keys`, `values` or other
`Base.Iterators` iterator (`zip`, `enumerate`, …), given as a value or
returned by a function, is an error rather than a constant, so a forgotten
`collect` is never repeated silently: write `name = [x]` to put one in every
row. `nothing`, given as a value or returned by a function, or a column holding
only `nothing`, is an error too (often a forgotten `return`); an absent value
is `missing`.

### Column pickers

Wherever columns are chosen (`select`, `across`, `relocate`, `pivot_longer`,
`drop_missing`, …):

- a name or a vector of names;
- a predicate on the column name, such as Julia's `startswith("rev")`,
  `endswith("_x")`, `contains("sales")`, `contains(r"^q[1-4]$")`, or any
  function `String -> Bool`;
- `everything()`; `of_type(T)` (columns whose element type, ignoring `missing`,
  is a subtype of `T`); `except(cols...)` (all columns but these). A column of
  element type `Missing` is picked only when `Missing <: T`; an empty column of
  element type `Union{}` is picked by every `of_type` *(own choice)*.

`select` keeps the order in which columns are picked; a column picked twice
appears once, at its first position. `select(t, new = :old)` renames while
selecting.

### Signatures

The table-first form of each verb; the pipe form drops `t`.

```julia
select(t, cols...; new = :old, …)        rename(t; new = :old, …)
relocate(t, cols...; before = nothing, after = nothing)   # default: to the front
pull(t, col)                             mutate(t, specs...; name = spec, …)
where(t, specs...)                       # several conditions are combined with AND
arrange(t, keys...; by_group = false)    desc(col)
distinct(t, cols...; keep_all = false)
slice(t, rows)                           slice_head(t; n)    slice_tail(t; n)
slice_min(t, col; n = 1, with_ties = true)   slice_max(t, col; n = 1, with_ties = true)
slice_sample(t; n, rng, replace = false)
group_by(t, cols...; sort = true)        ungroup(gt)
summarize(t, specs...; name = spec, …)   tally(t, cols...; name = :n)
across(cols, fns; names = "{col}_{fn}")  # fns: a function, a vector or a NamedTuple
lag(x, k = 1; default = missing)         lead(x, k = 1; default = missing)
row_number(x)   min_rank(x)   dense_rank(x)   percent_rank(x)   cume_dist(x)
ntile(x, k)     between(x, lo, hi)       n_distinct(xs...)
case_when(cond => value, …; default = missing)   each(f)
rolling_mean(x, k; partial = false)      rolling(f, x, k; partial = false)
inner_join(x, y; by, relationship = nothing, match_missing = false, suffix = ("_x", "_y"))
cross_join(x, y; suffix = ("_x", "_y"))
bind_rows(ts...; id = nothing)           bind_cols(ts...)
```

`slice_min` / `slice_max` with `with_ties = true` keep every row tied with the
`n`-th value. `bind_rows(…; id = :source)` adds a column naming the source table
(its position, or the keyword name when tables are given as `name = t`).

## Macros

| You write | It becomes |
|---|---|
| `revenue` | the column `revenue` if the table has one, otherwise the variable `revenue` |
| `$threshold` | always the variable `threshold` |
| `:revenue` | always the column `revenue` |
| arithmetic and comparison operators: `+ - * / ^ % ÷ == != ≠ < <= ≤ > >= ≥`, `!`, unary `-` | elementwise: `.+`, `.==`, `.<`, `.!`, … |
| `a && b`, `a \|\| b` | `a .& b`, `a .\| b` (three-valued with `missing`) |
| `a < b < c` | `(a .< b) .& (b .< c)` |
| `c ? a : b` | `ifelse.(c, a, b)` |
| `x in s`, `x ∈ s` | `in.(x, Ref(s))`: membership of each element in `s` |
| `===`, `!==` | unchanged (identity, not elementwise) |
| `sum(revenue)`, `myfun(x)` | unchanged: the function gets whole columns |
| `log.(revenue)` | unchanged: elementwise because the user wrote the dot |
| `n()` | the number of rows in the current group (macros only; `n` is not exported, so users keep `n` as a variable name; the function form writes `t -> nrow(t)`) |
| `var"unit price"` | the column named `unit price` |
| `-store` (in a picker) | `except(:store)` |
| `desc(revenue)` | `desc(:revenue)` |

- Operators are elementwise; functions are not. A function that is not
  elementwise by construction gets the dot from the user: `log.(revenue)`. This
  is Julia's own rule, so a mistake is an error, never a silently wrong result.
- Whether a bare name is a column or a variable is decided when the code runs:
  the macro cannot know the table's columns when the code is written. A column
  wins over a variable of the same name; `$x` forces the variable.
- Names bound inside the expression are not rewritten: lambda arguments
  (`x -> x + 1`), comprehension and generator variables, `let` bindings, and
  keyword names in calls (`round.(x; digits = 2)`).
- In `@select(dt, store)` the first argument is the table if it is a bare name
  of a defined variable (`@isdefined`) that holds a table when the code runs;
  otherwise every argument is a column and the macro returns the pipe form.
  Corner case: if a variable holding a table has the same name as a column the
  user means, writing `:name` forces the column.
- `where (x)` with a space before the parenthesis is a Julia parse error; the
  docs always write `where(x)`.

## Behaviour

### Missing values

- **Calculations propagate `missing`.** `sum([1, missing])` is `missing`. To
  skip missing values the user says so: `sum(skipmissing(revenue))`. Dropping
  them silently would be a hidden assumption about why they are missing.
- **`where` keeps only rows where the condition is `true`.** `false` and
  `missing` rows are dropped, as SQL `WHERE` does. A condition that is not `Bool`
  or `missing` is an error. Note for the docs: `!(x == 1)` also drops rows where
  `x` is `missing`.
- **Grouping:** all `missing` keys form one group, listed last. `distinct` and
  `tally` treat `missing` the same way, so the verbs agree *(own choice)*.
- **Joins:** `missing` keys never match (as SQL `NULL`); `match_missing = true`
  makes them match. `NaN` keys are ordinary values and match each other.
- **Key equality** (grouping, `distinct`, joins, set operations) is Julia's
  `isequal`, except that `-0.0` and `0.0` are the same key, as they are the same
  number *(own choice)*.
- **Pivots:** `pivot_wider` writes `missing` for absent combinations
  (`values_fill =` sets another value); `pivot_longer` keeps missing values
  (`drop_missing = true` removes them). Implicit missing values become
  explicit, never silently lost.

### Order

Every verb has a documented, deterministic output order.

- `arrange` is a stable sort. `missing` sorts last, also with `desc`
  *(own choice)*. `NaN` follows Julia's `isless` (after `+Inf`).
- `arrange` on a grouped table sorts the whole table and ignores the groups
  unless `by_group = true` *(own choice)*.
- Groups are sorted by key; `group_by(…; sort = false)` keeps the order of first
  appearance.
- `distinct` keeps the first occurrence of each row, in the original order.
  `distinct(t, :a, :b)` returns those columns; `keep_all = true` keeps the rest.
- Joins keep the left table's row order; for each left row, matches come in the
  right table's order. Unmatched right rows (`right_join`, `full_join`) follow,
  in the right table's order.

### Lengths and types

- In `mutate`, a result of length 1 is repeated for every row; any other length
  that is not the table's (or group's) row count is an error showing both
  lengths *(own choice)*.
- A `mutate` result with an abstract element type is narrowed to the one
  concrete type it holds (plus `missing`); a mix of types is an error, stricter
  than the combine rule below, which is for combining columns. An empty result
  with no concrete type becomes a `Vector{Missing}` *(own choice)*.
- In `summarize`, each result must be a single value per group; otherwise the
  error suggests `mutate`. `summarize` returns an ungrouped `Table` (a
  `PanelTable` for panels, see below), with the group columns first
  *(own choice)*.
- `summarize` on a table with no rows and no groups calls each function on the
  empty columns and returns one row; with groups it returns no rows. If a
  function fails on empty input (such as `maximum`), the error names the column
  and the group and suggests `init =`.
- No silent type conversions. Combining columns (`bind_rows`, `pivot_longer`,
  joins, `case_when`, `replace_missing`) follows one rule *(own choice)*:
  - integers combine to the wider integer type;
  - integers and floats combine to a float of at least `Float64`
    (`Int64` with `Float32` gives `Float64`, not `Float32`);
  - `Bool` does not combine with numbers;
  - any other mix (a `String` with an `Int`, say) is an error naming the column
    and both types.

### Names

- Duplicate column names are an error.
- In joins, non-key columns that exist on both sides get the suffixes
  `suffix = ("_x", "_y")` *(own choice)*.
- `bind_cols` with a duplicate name is an error.
- `rename(t, new = :old)`; `var"new name" = :old` for names with spaces.

### Joins

- `by` is required: `by = :id`, `by = [:a, :b]`, or `by = [:a => :b]` when the
  key has a different name on the right. Without it the error lists the columns
  the two tables share *(own choice: no silent natural join)*.
- **Many-to-many joins must be declared.** By default a join where a key value
  is duplicated on both sides is an error showing one such key, because it
  multiplies rows, a common source of silently wrong results. Declare
  `relationship = :many_to_many` to allow it. `:one_to_one`, `:one_to_many` and
  `:many_to_one` are checked against the data when given; the first word is the
  left table (`:one_to_many`: left keys unique, right keys may repeat).
- Output columns: the left table's columns, then the right table's non-key
  columns. Key columns appear once, under the left names. `semi_join` and
  `anti_join` return the left columns only.

### Memory

Verbs never modify their input. Unchanged columns are shared with the input
rather than copied (`select` copies nothing; `mutate` creates only the new
columns). Consequence, documented: changing a source vector in place afterwards
also changes the table; `copy(t)` gives a table whose columns are independent of
the source (a shallow copy; see Core types).

### Randomness

`slice_sample(t; n, rng)` requires `rng`, so every sample can be reproduced
*(own choice; also avoids a dependency on Random)*.

## Panels

```julia
p = PanelTable(dt; id = :store, time = :date)     # id may be [:store, :region]
p |> @mutate(prev = lag(sales), avg7 = rolling_mean(sales, 7))
p |> group_by(:region) |> summarize(sales = sum(sales))   # new panel, id = :region
```

- **Construction** checks that each (id, time) pair is unique (an error shows
  the first duplicate), that `time` has no `missing`, and sorts rows by id, then
  time. Gaps are allowed; they are never filled automatically.
- **Gaps** are explicit: `has_gaps(p; step)` and `fill_gaps(p; step, fill)`.
  `step` is given by the user (`Day(1)`, `Month(1)`, `1`). The regular grid of a
  series is `t0 + k * step` for `k = 0, 1, …` (not repeated `+`, which would
  drift on month ends); only `+`, `*` with an integer and `isless` are used, so
  `Dates` is not a dependency.
- **An ungrouped panel behaves as grouped by its id.** Every `mutate` and
  `where` spec runs per series, in time order: `lag`, `cumsum`, rolling windows
  and any function a user writes see one series at a time and never cross
  series. To compute across series, the user groups explicitly or calls
  `as_table` first.
- **`group_by` on a panel** is always allowed and keeps the panel. Specs then
  run per group. When the groups mix several series (for example grouping by
  `:region` when the id is `:store`), a window helper (`window_function(f)` is
  true) is an error: lags must not cross series, so the message suggests
  grouping by the id or summarizing to the new level first. A user function that
  is not marked as a window function cannot be detected; the docs say so and
  recommend the window helpers.
- **`summarize` on a panel** summarizes per group *and per time point*. The
  result is a new `PanelTable` whose id is the group columns (no groups: a single
  series). For one row per series over the whole period, the user writes
  `as_table(p) |> group_by(:store) |> summarize(…)`.
- **The general rule:** a verb returns a `PanelTable` when its result still has
  the id and time columns unchanged and every (id, time) pair is still unique.
  Verbs that can duplicate rows (`slice_sample(…; replace = true)`, joins,
  `bind_rows`) check uniqueness again and raise an error naming the duplicate
  and the fix.
- **Errors at the verb that would break the panel**, naming the fix
  (`as_table(p)` first): `select` or `distinct` without the id or time columns, a
  `mutate`, `separate` or `unite` that overwrites or removes them, and
  `arrange`. `rename` (also `select(new = :id)`) of an id or time column updates
  the panel.
- **Verbs that keep the panel:** `where`, `mutate`, `relocate`, `slice_*`,
  `distinct`, `select`, `bind_cols`, `separate`, `unite`, `drop_missing`,
  `replace_missing`, `fill_missing`, `inner_join`, `left_join`, `semi_join`,
  `anti_join`, `bind_rows` of panels with the same id and time, and `fill_gaps`.
- **Verbs that return a plain `Table`:** `right_join`, `full_join`,
  `cross_join`, the set operations, `pivot_longer`, `pivot_wider`, `complete`
  (use `fill_gaps` for time), `tally`, `nest`, `unnest`, `as_table`.
- **No warnings.** Every problem is an error at the point where it happens;
  correct code runs without noise.

`panel_id(p)` and `panel_time(p)` are the public accessors other packages (such
as MachineLearningForecast.jl or Durbyn.jl, through a package extension) can use
later.

## Reshaping, missing values, nesting

- `pivot_longer(t, cols; names_to = :name, values_to = :value, drop_missing = false)`.
- `pivot_wider(t; names_from, values_from, id_cols = everything else, values_fill = missing, values_fn = nothing)`.
  A duplicated (id, name) pair is an error showing it, unless `values_fn` (for
  example `sum`) says how to combine.
- `separate(t, col; into, delim, remove = true)`: a value with the wrong number of
  pieces is an error showing the row, unless `too_few = :missing` or
  `too_many = :merge` / `:drop` is given.
- `unite(t, new, cols...; sep = "_", remove = true, skip_missing = false)`: with a
  `missing` piece the result is `missing` unless `skip_missing = true`.
- `drop_missing(t, cols...)` (all columns if none given),
  `replace_missing(t; col = value, …)`,
  `fill_missing(t, cols...; direction = :down)` (`:up`, `:downup`, `:updown`),
  per group or per series.
- `complete(t, cols...; fill = (;))` adds every combination of the distinct
  values of `cols` that is absent, with `missing` (or `fill`) elsewhere.
- `nest(gt; name = :data)` turns each group into one row with a `Table` column;
  `unnest(t, :data)` reverses it.

## Windows

`rolling_mean(x, k)` and the others are trailing windows: the value at row `i`
uses rows `i-k+1` to `i`. The first `k-1` values are `missing` unless
`partial = true`. `rolling(f, x, k)` applies any function to each window. Sums,
means, minima and maxima run in O(n) (running sums, a monotonic queue); variance
and standard deviation use a numerically stable update and are tested against
direct computation. For forecasting features, combine with `lag` so that the
window ends before the current row.

## Errors

Every check throws an `ArgumentError` that states:

1. what was wrong, in which verb,
2. the offending value,
3. the valid options or the fix, kept separate from the explanation.

"Did you mean `revenue`?" is added only when exactly one column name is a close
match (small edit distance); a guessed fix that is wrong misleads more than no
fix. TableOps never prints warnings.

## Performance

### Targets

Measured on a 2-core machine, for the common verbs; a release must meet them.

| What | Target |
|---|---|
| `using TableOps` | under 0.5 s |
| first call of a typical chain | under 1 s |
| one verb on up to 1 million rows, compiled | under 100 ms |
| against DataFrames.jl on the same task | not slower |

Delays above about 100 ms are noticeable, and an added 500 ms per operation
measurably reduces how much people explore their data.

### How

- **Function barriers.** The table is untyped; every inner loop is a separate
  function that receives concrete column types and is type-stable (checked with
  `@inferred` in the tests).
- **Key encoding.** Each key column is encoded once into integer codes (a hash
  map in general, a direct lookup for small integer ranges). Several keys
  combine into one integer when the product of their cardinalities fits,
  otherwise into a hashed tuple of codes. A counting pass then orders the rows by
  group in O(n); only the distinct keys are sorted.
- **Single-pass reductions.** `sum`, `length` (and `n()`), `minimum`,
  `maximum`, `first`, `last` and `n_distinct` run in one pass over the rows into
  per-group results; with Statistics loaded, so do `mean`, `var` and `std`
  (Welford's method, through the extension). Any other function runs on a view
  of each group. A new fast path is one method of `grouped_reduce`.
- **Gather once.** `where`, `slice_*` and joins build a row index first, then
  copy each column once; no verb iterates rows as `NamedTuple`s.
- **Joins** are hash joins on the encoded keys, built on the smaller table.
- **Sorting** uses Julia's stable `sortperm`; several keys are encoded first.
- **Threads** are used only when Julia has more than one and the input is large.
  Results are identical for every thread count: chunk sizes are fixed and
  partial results combine in a fixed order.
- **Load time.** Tables.jl only; plain `precompile` statements for the common
  column types (`Int`, `Float64`, `String`, `Bool` and their `missing` unions);
  no method definitions that invalidate other code.

### Benchmarks

`bench/` has its own environment (BenchmarkTools, DataFrames, CSV, Arrow), so
none of these become package dependencies. Synthetic tables from 10³ to 10⁷
rows; load time, first-call time, run time and allocations; results in
`bench/results.md`, rerun before each release and after every change aimed at
speed.

## Extending TableOps

Extension is by adding methods, never by branching on a mode string; keyword
options only choose among the documented behaviours of a verb.

- **New column picker:** a subtype of `AbstractSelector` with a
  `resolve(selector, t)` method that returns the picked names; it may look at
  the names and the column types of the table `t`.
- **New window helper:** a function of a whole column, registered the way `lag`
  is so that it runs per group and per series.
- **New fast reduction:** a `grouped_reduce(::typeof(f), column, groups)` method;
  `summarize(:x => f)` then uses it.
- **New table types** from other packages: methods for `Table`, `GroupedTable` or
  `PanelTable`, or any Tables.jl table, which already works as input.

## Testing

- `Test.jl`, one `test_<topic>.jl` per source file (plus `test_compat.jl`
  and the shared `checks.jl`), all included from
  `test/runtests.jl` inside one `@testset`, then Aqua.jl. Random inputs use
  StableRNGs.
- Expected outputs are small tables written by hand in the tests. No other
  software is run to produce them.
- Every verb: the normal case; edge cases (no rows, no columns, one row,
  `missing`, `NaN`, a column that is all `missing`, Unicode names and names with
  spaces, wrong input types); every `ArgumentError` with `@test_throws` and its
  message.
- Shared checks for every verb: function, pipe and macro forms agree; ungrouped,
  grouped and panel behaviour as specified; the input is unchanged; result
  columns have concrete element types; inner functions pass `@inferred`.
- Fast paths are checked on random tables against a deliberately simple
  reference written in the test (a loop and a `Dict`); the same comparison checks
  that one and several threads give identical results.
- Compatibility: input from and output to `NamedTuple` tables, row tables, CSV,
  Arrow and DataFrames (test-only dependencies).
- The full suite on Julia 1.10 and the latest release, and the docs build
  (doctests and `checkdocs = :exports`), before every commit.

## References

Used to verify the decisions above.

- Wickham, H. (2014). Tidy data. *Journal of Statistical Software* 59(10).
  doi:10.18637/jss.v059.i10
- Wickham, H. (2011). The split-apply-combine strategy for data analysis.
  *Journal of Statistical Software* 40(1). doi:10.18637/jss.v040.i01
- Petersohn, D. et al. (2020). Towards scalable dataframe systems. *PVLDB*
  13(12). doi:10.14778/3407790.3407807
- Wang, E., Cook, D. & Hyndman, R. J. (2020). A new tidy data structure to
  support exploration and modeling of temporal data. *JCGS* 29(3).
  doi:10.1080/10618600.2019.1695624
- Rubin, D. B. (1976). Inference and missing data. *Biometrika* 63(3).
  doi:10.1093/biomet/63.3.581
- Libkin, L. (2016). SQL's three-valued logic and certain answers. *ACM TODS*
  41(1). doi:10.1145/2877206
- Libkin, L. & Peterfreund, L. (2023). SQL nulls and two-valued logic. *PODS*.
  doi:10.1145/3584372.3588661
- Toussaint, E., Guagliardo, P., Libkin, L. & Sequeda, J. (2022). Troubles with
  nulls, views from the users. *PVLDB* 15(11). doi:10.14778/3551793.3551818
- Brass, S. & Goldberg, C. (2006). Semantic errors in SQL queries: a quite
  complete list. *J. Systems and Software* 79(5). doi:10.1016/j.jss.2005.06.028
- IEEE Std 754-2019, IEEE Standard for Floating-Point Arithmetic.
  doi:10.1109/IEEESTD.2019.8766229
- Galappaththi, A., Nadi, S. & Treude, C. (2024). An empirical study of API
  misuses of data-centric libraries. *ESEM*. doi:10.1145/3674805.3686685
- Piccioni, M., Furia, C. A. & Meyer, B. (2013). An empirical study of API
  usability. *ESEM*. doi:10.1109/ESEM.2013.14
- Barik, T., Ford, D., Murphy-Hill, E. & Parnin, C. (2018). How should compilers
  explain problems to developers? *ESEC/FSE*. doi:10.1145/3236024.3236040
- Marceau, G., Fisler, K. & Krishnamurthi, S. (2011). Mind your language: on
  novices' interactions with error messages. *Onward!*
  doi:10.1145/2048237.2048241
- Anderson, B. B. et al. (2015). How polymorphic warnings reduce habituation in
  the brain. *CHI*. doi:10.1145/2702123.2702322
- Johnson, E. J. & Goldstein, D. (2003). Do defaults save lives? *Science*
  302(5649). doi:10.1126/science.1091721
- Card, S. K., Robertson, G. G. & Mackinlay, J. D. (1991). The information
  visualizer, an information workspace. *CHI*. doi:10.1145/108844.108874
- Liu, Z. & Heer, J. (2014). The effects of interactive latency on exploratory
  visual analysis. *IEEE TVCG* 20(12). doi:10.1109/TVCG.2014.2346452
