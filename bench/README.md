# Benchmarks

A separate environment, so the benchmark tools and the packages compared against
never become dependencies of TableOps.

```bash
julia --project=bench -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
julia --project=bench bench/run.jl
```

`bench/run.jl` (added in the performance phase) builds synthetic tables from
10³ to 10⁷ rows and measures load time, first-call time, run time and
allocations for TableOps and DataFrames.jl. Results go to `bench/results.md`.
