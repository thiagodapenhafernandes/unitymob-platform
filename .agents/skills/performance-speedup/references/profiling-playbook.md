# Profiling Playbook

Use this reference only after the skill has already triggered. It is not the routing layer.

## Goal

Reduce speculative optimization. First localize the hot path, then choose the smallest measurement that can prove or disprove a suspected bottleneck.

## Measurement ladder

Prefer the lightest tool that can answer the current question.

1. Existing timings
- Application logs with stage timings
- Existing benchmark scripts
- Query timing output

2. Minimal local instrumentation
- Add timing around one suspicious stage
- Add counters for repeated calls
- Print row counts, batch sizes, or payload sizes

3. Focused profiler
- Function-level profiler for one workload
- Query plan for one SQL path
- Trace around one request or batch job

4. Heavier diagnostics
- Flamegraph
- Allocation profiler
- Lock-contention or thread diagnostics
- End-to-end benchmark matrix

## Typical workflow

1. Confirm one reproducible workload.
2. Measure wall-clock time.
3. Split the path into major stages.
4. Measure each stage.
5. Zoom into the dominant stage only.
6. Re-measure after each substantial change.

## Profiling by bottleneck class

### CPU-bound
- Function profiler
- Line profiler if a tiny number of functions dominate
- Flamegraph if call structure matters

### Dataframe or tabular workloads
- Time per stage: load, filter, join, group, write
- Row counts before and after expensive transforms
- Check for Python loops over rows
- Check for repeated conversions between dataframe formats

### Database
- Query timing
- `EXPLAIN`
- `EXPLAIN ANALYZE`
- index usage
- repeated query count

### Network
- request count
- payload size
- latency per remote call
- evidence of N+1 or chatty request patterns

### Memory or allocation pressure
- object copying
- repeated serialization
- dataframe duplication
- materialization of intermediates

## Common mistakes

- Measuring too many things at once
- Profiling before reproducing the slow path
- Optimizing a cold path because it looks ugly
- Replacing an algorithm before proving it is dominant
- Confusing one-off startup cost with steady-state runtime

## Good measurement notes

Always capture:
- workload analyzed
- command or request used
- relevant input size
- environment caveats
- before time
- after time
- confidence in the measurement
