# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

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
