# Parallelism via the `targets` package

Read this when a simulation is large enough to warrant parallel execution.

In this skill, parallelism is provided **only** by the `targets` package —
**never** by `controller$run(n_workers > 1)`, which is forbidden. Each
replicate runs single-threaded; a `targets` + `crew` pipeline runs many
single-threaded jobs in parallel, and you also get result caching and a
reproducible scenario grid.

How you split the work into targets is **your choice** — optimize for
readability and QC, not for a fixed template. Do **not** force every
scenario through one unified function: heterogeneous scenarios are usually
clearer as separate functions / separate targets. `targets` parallelizes
whatever targets you define.

## What `targets` needs from you

- A `crew` controller sets the worker count. Use half the physical cores —
  it leaves headroom for the OS/UI and biases the load onto performance
  cores (efficiency cores are the slow stragglers):

  ```r
  workers <- max(1L, parallelly::availableCores(logical = FALSE) %/% 2L)
  tar_option_set(
    packages   = c("TrialSimulator", "survival"),
    controller = crew::crew_controller_local(workers = workers)
  )
  ```
  Override `workers` only if the user asks.

- Each function that runs on a worker **must be self-contained** — every
  input through its signature, no script-level globals or closures (crew
  workers do not share the script environment). Anything otherwise built
  once at script level and captured by a closure — e.g. a NORTA
  `simdesign_norta` object — must be built **inside** the worker function.

- Inside that function: `controller$run(n = <replicates for this job>)` runs
  single-threaded (the default `n_workers = 1`; do not set it). Return
  **`controller$get_output()`** — it holds every replicate (incl. the
  `seed` column). Do **not** return `trial$get_output()`; that is only the
  *last* replicate.

- Do **not** set `seed` in `trial()`. A fresh seed is drawn per replicate
  automatically and recorded in the output, so any row can be reproduced
  later from its `seed`.

## Mapping scenarios

Pick whatever structure is clearest:

- For a regular scenario × replicate grid, `tarchetypes::tar_map_rep()` is
  convenient — `values` is a data frame of scenarios whose columns are
  spliced into `command` as arguments, and `batches` is the parallel unit.
- For a handful of distinct or structurally different scenarios, separate
  `tar_target()`s (one per scenario or scenario family) are often easier to
  read and QC than a single grid.

Either way, batch the replicates: run a **chunk per job**
(`controller$run(n = chunk)`) rather than one replicate per job. Chunking
avoids ~18% per-replicate rebuild/setup overhead, and the gain saturates by
~10 replicates per job, so any reasonable split captures it.

## Rules

- **Never** `controller$run(n_workers > 1)` — parallelism is via `targets`
  only.
- Worker functions must be self-contained (no script-level globals or
  closures).
- Return `controller$get_output()`, not `trial$get_output()`.
- No `seed` in `trial()`; recover a replicate from the `seed` column.
