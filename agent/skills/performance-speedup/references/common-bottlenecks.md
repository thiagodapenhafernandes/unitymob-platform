# Common Bottlenecks

This is a reminder list, not a default diagnosis. Use it only after evidence points at a class of slowdown.

## Algorithmic and structural
- N+1 database access
- nested loops over large collections
- repeated sorting
- repeated scans over the same data
- expensive work inside tight loops
- recomputing derived data instead of reusing it

## CPU-bound
- Python loops over dataframe rows
- repeated parsing
- regex-heavy processing on large text volumes
- unvectorized numeric transforms
- redundant JSON encoding or decoding

## Memory and allocation
- copying large dataframes or arrays unnecessarily
- building huge intermediate lists
- converting the same structure repeatedly
- exploding nested data too early

## I/O
- tiny repeated file reads
- repeated object-store fetches
- full-table scans written to disk before filtering
- synchronous writes in a hot path

## Database
- missing indexes
- wrong join order
- filtering after materialization
- pulling too much data into application memory
- too many round trips instead of one shaped query

## Network
- one request per item
- no connection reuse
- oversized payloads
- serial remote calls that could be batched

## Serialization and parsing
- repeated JSON, CSV, or parquet decode and re-encode
- wide row objects when only a few fields are needed
- schema inference repeated on every run

## Concurrency and contention
- lock bottlenecks
- work queued behind one shared resource
- thread pools or async workers used on CPU-bound code with no gain
- excessive synchronization

## Logging overhead
- debug logging inside tight loops
- expensive string formatting even when log level hides output
- logging large payloads repeatedly

## Startup and initialization
- repeated imports in worker tasks
- model or config reload per request
- reconnecting on every operation

## Interpretation reminder

The same symptom can come from different causes.

Example:
- "Slow request" might be database latency, serialization, or logging.
- "Slow dataframe pipeline" might be bad asymptotics, materialization, or too many conversions.

Always connect the bottleneck to evidence before choosing a fix.
