# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `slice_min` and `slice_max`: the `n` smallest or largest rows with
  `with_ties`; `missing` is never selected, and in a column with `missing`
  asking for more rows than there are known values is an error.
- `slice`, `slice_head` and `slice_tail`: rows by number (out of range is an
  error that shows the valid range), the first or the last `n` rows.
- `distinct`: the first row of each distinct key, in order; `missing` is one
  value, `NaN` equals `NaN` and `-0.0` equals `0.0`.
- `arrange` and `desc`: a stable sort by several keys; `missing` last in
  both directions, `NaN` after `Inf`, `-0.0` and `0.0` tie.
- `where`: keeps the rows where every condition is `true` (`false` and
  `missing` are dropped); a condition that is not `Bool` or `missing` is an
  error. `where` accepts a function of the table as a condition; an empty
  column name in a specification is an error.
- `mutate` for ungrouped tables: columns from `name = :col`, `:col => f`,
  `[:a, :b] => f`, `name = value` and `name = t -> …`. A tuple, `NamedTuple`,
  matrix, set, dictionary, table, generator, `skipmissing`, `keys`, `values` or
  other `Base.Iterators` iterator, given as a value or returned by a function,
  is an error, not a constant, and so is `nothing` (use `missing`). A column
  that mixes element types is an error.
- `select` (with renaming), `rename`, `relocate` and `pull`, each in table-first
  and pipe form.
- `each` for elementwise column specifications.
- Column pickers: `everything`, `of_type`, `except`, name predicates,
  `AbstractSelector` and `resolve`.
- `Table`: a table type that keeps the column vectors of any Tables.jl table
  (row tables are converted to columns), or builds one from keyword columns.
  Rows with different column names are an error, not a silent drop.
- Column access with `t.col`, `names`, `copy`, `isequal`, `==` and the Tables.jl
  interface for `Table`.
- `as_table`, `nrow` and `ncol`.
- Table printing (size, column names and types, first and last rows) and
  `glimpse` (one line per column).
- Package skeleton: module, test suite with Aqua.jl, documentation with the
  design, CI on Julia 1.10 and the latest release.
