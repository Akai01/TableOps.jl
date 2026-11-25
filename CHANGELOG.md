# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `Table`: a table type that keeps the column vectors of any Tables.jl table
  (row tables are converted to columns), or builds one from keyword columns.
- Column access with `t.col`, `names`, `copy`, `isequal`, `==` and the Tables.jl
  interface for `Table`.
- `as_table`, `nrow` and `ncol`.
- Package skeleton: module, test suite with Aqua.jl, documentation with the
  design, CI on Julia 1.10 and the latest release.
