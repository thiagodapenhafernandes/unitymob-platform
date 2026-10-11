---
name: performance-speedup
description: >
  Audit and speed up a slow module, code path, query, batch job, pipeline, or request handler.
  Trigger when the user asks to speed up or optimize performance, reports that something is slow,
  shares logs, traces, timings, or profiles showing high latency or low throughput, or when the current coding task
  clearly depends on fixing a runtime bottleneck.
  Diagnose before changing code: identify the hot path, classify the bottleneck
  (algorithmic, CPU, I/O, database, network, memory, serialization, contention, logging, or redundant work),
  propose ranked optimizations, apply the highest-confidence improvements, and remeasure.
  Use profiling, query plans, logs, benchmarks, and suitable tools such as vectorization, batching, caching,
  indexing, concurrency, DuckDB, or Polars when justified by evidence.
  Do not use for generic bug fixing, correctness-only debugging, build or install speed, infra provisioning,
  or vague optimize requests with no performance signal.
---

# Performance Speedup

## Purpose

Turn a vague "it is slow" signal into an evidence-based performance improvement workflow:
- find the real bottleneck
- avoid guessing
- rank optimizations by expected impact, cost, and risk
- implement the strongest changes first
- remeasure after changes

This is a runtime and performance skill, not a generic debugging skill.

## Use when

Use this skill when:
- the user says a module, handler, job, query, or pipeline is slow
- logs or traces show large runtime, latency spikes, throughput collapse, or obvious stalls
- profiling data exists or should be added
- the task is to speed up code rather than only make it correct
- a refactor is blocked by uncertainty about where time is being spent

Typical trigger phrases:
- "ускорь это"
- "что-то медленно работает"
- "этот модуль слишком долгий"
- "посмотри логи, тут очень долго"
- "optimize performance"
- "speed this up"
- "find the bottleneck"
- "why is this handler taking 2.8s"
- "сделай аудит производительности"

## Do not use when

Do not use this skill for:
- ordinary bug fixing where the issue is correctness, not speed
- generic refactoring with no performance signal
- build speed, install speed, or CI speed unless the task is explicitly about those
- infra provisioning or hardware sizing
- "clean up code" tasks without bottleneck evidence
- premature micro-optimization of cold code paths

## Inputs

Expected inputs:
- the slow module, code path, query, handler, or pipeline
- logs, traces, timings, or a code location
- any reproduction command, benchmark, or failing workload

Optional inputs:
- profiler output
- flamegraph, trace, or query plan
- dependency or runtime version info
- sample data shape, batch size, or request volume

## Outputs

Always produce:
1. bottleneck summary
2. evidence used
3. bottleneck classification
4. ranked optimization opportunities
5. changes applied, if any
6. before/after measurement, or the exact measurement gap if no benchmark was possible
7. residual risks or unknowns

## Constraints

- Start with evidence, not optimization folklore.
- Do not select tools before locating the hot path.
- Preserve correctness, ordering semantics, and acceptable memory bounds.
- Prefer the smallest high-confidence change that plausibly removes the dominant bottleneck.
- Use a bounded subagent for heavy log, trace, or profile reading when that reduces main-thread noise.
- If measurement is missing, the first useful output is a measurement plan, not a speculative rewrite.

## Procedure

1. Start with evidence, not guesses.
   First inspect the strongest available signals:
   - logs
   - traces
   - profiler output
   - query plans
   - timings already present in code
   - reproduction commands

2. If evidence is weak, add minimal measurement.
   Introduce the smallest instrumentation needed to localize the slowdown:
   - timing around suspicious stages
   - a lightweight benchmark
   - a profiler run
   - a database `EXPLAIN` or `ANALYZE` when relevant

3. Localize the hot path.
   Identify where time is actually going:
   - one function
   - one loop
   - one query
   - one serialization step
   - repeated network round trips
   - file I/O
   - object allocation or copying
   - lock contention
   - redundant recomputation
   - logging overhead

4. Classify the bottleneck before proposing tools.
   Classify into one or more of:
   - algorithmic or asymptotic
   - CPU-bound compute
   - memory, allocation, or copy pressure
   - disk or object-store I/O
   - database or query planning or indexing
   - network latency or too many round trips
   - serialization, parsing, or encoding
   - concurrency, locking, or synchronization
   - startup, import, or initialization
   - redundant work, no caching, or no batching
   - excessive logging or tracing overhead

5. Build a ranked optimization plan.
   For each candidate speedup, estimate:
   - why it should help
   - expected impact
   - implementation cost
   - correctness risk
   - whether it needs benchmarking first

6. Prioritize high-confidence, high-leverage fixes.
   Prefer in this order when supported by evidence:
   - remove unnecessary work
   - fix bad asymptotics or data structures
   - reduce round trips or passes over data
   - push computation closer to the data
   - batch operations
   - add caching only when reuse exists
   - use vectorized, columnar, or query-engine paths for tabular workloads
   - improve query plans and indexing
   - reduce allocations, copies, or serialization
   - introduce concurrency only when the bottleneck actually benefits from it
   - apply micro-optimizations last

7. Use tools as options, not dogma.
   Tools are suggestions, not defaults:
   - DuckDB, Polars, or Arrow for large local tabular transformations or pushdown-style processing
   - query plans and indexes for database bottlenecks
   - vectorization for numeric or dataframe-heavy loops
   - batching and connection reuse for chatty network or DB traffic
   - memoization or caching for repeated pure work
   - worker pools or async concurrency for latency hiding where appropriate
   Do not force a tool if the evidence points elsewhere.

8. Keep correctness constraints explicit.
   Every speedup must preserve:
   - outputs
   - ordering semantics, if important
   - numerical stability, if relevant
   - transactional or concurrency guarantees
   - acceptable memory bounds for the target environment

9. Re-measure after changes.
   Compare before and after with the narrowest reliable measurement available.
   If measurement cannot be reproduced, state that clearly.

10. Stop at the right point.
   If the remaining gains require architectural redesign, say so explicitly instead of silently over-refactoring.

## Decision rules

### Evidence rule

Never choose an optimization path only because it is fashionable or fast in general.
Always tie it to observed evidence.

### Algorithm-first rule

If the slowdown is dominated by asymptotics, redundant passes, N+1 behavior, or repeated work,
prefer structural fixes over micro-tuning.

### Tool-selection rule

DuckDB, Polars, caching, vectorization, concurrency, or specialized engines are options.
Use them only when the workload shape actually matches them.

### Measurement rule

If there is no trustworthy measurement yet, the first output should be a measurement plan or instrumentation step,
not a speculative rewrite.

### Risk rule

Prefer the smallest change that can plausibly remove the dominant bottleneck.
Do not trade large correctness or maintainability risk for minor speedups.

## Subagent use

Prefer the custom subagent `perf-auditor` when performance investigation would otherwise bloat the main thread.

Typical good uses:
- one concrete slow module
- one request handler
- one batch job
- one SQL path
- one pipeline stage
- one suspicious hot path after a refactor

The subagent is not limited to reading large logs or traces. It can also:
- inspect the relevant code path
- synthesize incomplete timing evidence
- classify the bottleneck
- propose the next measurement step when evidence is still weak
- return a compact ranked speedup memo

The main thread should then:
- decide what to implement
- apply the changes
- remeasure
- summarize the result

## Definition of done

- The dominant bottleneck is identified from evidence or the exact missing measurement is named.
- Optimization candidates are ranked rather than listed randomly.
- At least one high-confidence improvement path is selected or explicitly deferred with reason.
- Before/after measurement exists, or the absence of measurement is called out precisely.
- Remaining risks and unknowns are explicit.

## Final response format

Return a compact summary with:
- Bottleneck
- Evidence
- Bottleneck type
- Ranked speedups
- Changes applied
- Before/after measurement
- Remaining risks or next steps

## Positive examples

Use this skill for:
- "ускорь этот handler"
- "этот batch job идёт 18 минут, разберись"
- "смотри логи, тут всё тормозит"
- "find the bottleneck in this pipeline"
- "optimize this pandas-heavy path"
- "эта SQL-часть слишком медленная"
- "this module is slow after the refactor"

## Negative examples

Do not use this skill for:
- "исправь баг в парсере"
- "сделай код чище"
- "почему тесты падают"
- "ускорь npm install"
- "сделай rebase"
- "напиши PR description"
