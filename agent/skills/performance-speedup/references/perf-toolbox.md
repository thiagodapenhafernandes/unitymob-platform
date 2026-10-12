# Performance Toolbox

These are candidate tools and techniques. They are not defaults.

Use them only when the workload shape supports them.

## General principles

- Remove work before making work faster.
- Reduce passes over the same data.
- Move filters and projection earlier.
- Keep data in the cheapest useful representation.
- Re-measure after every material change.

## Python and general profiling

- `cProfile`: broad function-level profiling
- `py-spy`: low-overhead sampling profiler
- `scalene`: CPU, memory, and Python/native split
- `line_profiler`: fine-grained line timing for a few hot functions
- `time.perf_counter()`: minimal local timing
- `pytest-benchmark`: repeatable microbenchmarks when needed

## Data workloads

### Vectorization
Use when:
- loops operate row-by-row over numeric or dataframe data
- operations can be expressed as column transforms

Avoid when:
- business logic is highly branching and tiny datasets dominate

### Polars
Useful when:
- columnar workloads are large
- lazy execution and pushdown can cut work
- current pandas path is bottlenecked by Python-level row handling

### DuckDB
Useful when:
- local tabular joins, aggregations, filtering, or parquet scans dominate runtime
- you want SQL pushdown over local files
- current code materializes too much data too early

### Arrow
Useful when:
- copy reduction between data systems matters
- zero-copy or columnar interchange can remove conversion overhead

## Database

- `EXPLAIN`
- `EXPLAIN ANALYZE`
- covering indexes
- partial indexes
- join reordering
- batch queries instead of one request per item
- pagination or bounded scans

## Caching

Use when:
- repeated pure work has real reuse
- cache invalidation boundary is clear

Avoid when:
- every input is effectively unique
- correctness risk or staleness cost is high

## Batching

Use when:
- network or DB round trips dominate
- one operation per row or entity is visible

Examples:
- bulk inserts
- batched remote fetches
- grouped writes

## Concurrency

Use when:
- latency is dominated by wait time
- independent remote calls or I/O operations can overlap

Avoid when:
- the workload is mostly one CPU-bound Python loop
- contention or synchronization already dominates

## Logging cleanup

Check for:
- logs inside tight loops
- repeated formatting of large payloads
- trace-level output in production-like workloads

## Tool-choice reminders

- DuckDB is strong for local analytical SQL over files and large tabular transforms.
- Polars is strong for columnar dataframe pipelines and lazy optimization.
- Query engines do not fix a network bottleneck.
- Concurrency does not fix bad asymptotics.
- Caching does not fix one-off batch jobs with no reuse.
