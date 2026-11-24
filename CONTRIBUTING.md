# Contributing to TableOps.jl

Thanks for your interest in improving TableOps. Bug reports, documentation fixes
and new features are all welcome.

By participating you agree to abide by the [Code of Conduct](CODE_OF_CONDUCT.md).

## Getting started

```julia
julia> ]                        # enter Pkg mode
pkg> dev /path/to/TableOps.jl
pkg> activate /path/to/TableOps.jl
pkg> test                       # runs the full suite
```

Building the docs locally:

```bash
julia --project=docs docs/make.jl   # output in docs/build/
```

The docs build is warning-free and `checkdocs = :exports` is enabled, so a new
export without a docstring entry in `docs/src/index.md` fails the build.

## Opening an issue

For a bug, please include:

- the TableOps version and `versioninfo()`,
- a minimal reproducing script with a small table written inline,
- what you expected and what happened.

## Pull requests

1. Open an issue first for anything larger than a fix, so the design can be
   discussed before you spend time on it.
2. Branch from `main`.
3. Add tests. A change in behaviour needs a test that would have caught the old
   behaviour.
4. Every exported name needs a docstring **with an example**.
5. Run `Pkg.test()` and the docs build before pushing.

CI runs the tests on Julia 1.10 (oldest supported) and the current release,
plus Aqua.jl quality checks.

## Original work only

TableOps is written from scratch. Do not copy, translate or closely model code
from any other package (dplyr, tidyr, pandas, DataFrames.jl, DataFramesMeta.jl,
TidierData.jl, Polars or others), and do not read their source while working on
TableOps. Using the same verb names is fine; the implementation must be our own.

## Design principles

These are load-bearing; the full design is in
[docs/src/design.md](docs/src/design.md).

- **Correct first.** No silently wrong result: missing values are never dropped
  or invented without the user asking, joins do not multiply rows unless
  declared, and there are no silent type conversions.
- **A good user experience.** One name per operation, the same in the function,
  pipe and macro forms. Safe defaults.
- **Actionable errors, no warnings.** Every check throws an `ArgumentError`
  stating what was wrong, the offending value and the fix.
- **Fast.** Untyped column storage with type-stable inner functions behind
  function barriers; single-pass group reductions; no per-row `NamedTuple`s.
  Check new inner loops with `@inferred` and benchmark them in `bench/`.
- **Light.** Tables.jl is the only dependency. Do not add another.
- **Tables.jl everywhere.** Any Tables.jl table goes in; every result is a
  Tables.jl table.
- **Dispatch, not mode strings.** Extend by adding methods, never by
  `if kind == "x"`; keyword options only choose among documented behaviours.
- **Immutable verbs.** No verb modifies its input; unchanged columns are shared.
- **Julia 1.10** is the oldest supported version.

## Tests

- One `test/test_<topic>.jl` per source file, included from `test/runtests.jl`.
- Expected outputs are small tables written by hand.
- Cover the normal case, edge cases (no rows, no columns, one row, `missing`,
  `NaN`, all-`missing` columns, Unicode names, wrong types) and every
  `ArgumentError` with `@test_throws` and its message.
- Random inputs use StableRNGs.

## Style

Match the surrounding code: 4-space indent, ~92 column limit, lowercase
function names, `snake_case` for internals and `CamelCase` for types. Comments
explain *why*, not *what*.
