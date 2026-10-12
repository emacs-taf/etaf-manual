# Testing and Validation

This chapter describes how correctness is established in this ecosystem: which scenarios exist, what they may touch, how they run and what counts as evidence. These are the project's rules rather than package interfaces — they add no definition entries — but they are the reason the public behavior described by the rest of the book can be trusted, and they apply unchanged to an application or an extension built on the packages.

## Only public interfaces are tested

<!-- index: public test; acceptance inventory -->

A maintained test exercises observable inputs, outputs, errors, rollback and lifecycle through the interfaces the package entry declares. It does not test a private helper, an internal data structure, source text, call counts or a retired behavior; fixtures and helpers obey the same rule, and indirection, reflection or fault injection do not grant private access. When a scenario seems to need a private symbol, the right response is to move the fact behind a public interface or to test the observable behavior instead — never to promote the symbol to public API just to keep the test.

Every package inventories its maintained Lisp correctness scenarios in `tests/acceptance.json`, one entry per scenario with an observable purpose. The inventory is the contract of what the package claims to verify: `make test` runs exactly this public suite, and `make check` runs it together with the structural gate, byte compilation, a fresh entry binding and source signature validation. There is no separate internal suite, because an internal test would assert the implementation rather than the behavior a consumer sees.

## Headless assertions

<!-- index: ERT; serialized run; bounded failure -->

Scenarios are ERT tests. The workspace runner `scripts/run-acceptance.py` serializes runs of one checkout behind an advisory lock: a concurrent run is refused with exit status 75, or waits for up to `--wait SECONDS`. That is what makes repeated local runs and background jobs safe over the same build outputs.

A failing ERT test tends to print its condition, and a framework condition can be large or cyclic. The runner replaces the pretty-printer with a plain print bounded by `--print-length` (default 6), `--print-level` (default 3) and a hard `--max-condition-bytes` cap (default 8192), so a failure report stays readable. Two habits keep individual assertions out of trouble. Bind the result of a call that returns a large live object — a Runtime, a buffer, a tree — to a local and assert on the local, because ERT captures evaluated arguments and a large object inside a `should` form makes every failure report huge. And when printing framework content, take text with `buffer-substring-no-properties` and bind `print-circle` with print limits; a live Runtime or backtrace can carry cyclic closures and text properties that `%S` would expand forever. Any Lisp file written for Emacs to load, including a temporary probe, starts with `;;; -*- lexical-binding: t; -*-`.

## Validation in a real GUI

<!-- index: GUI validation; viewport class -->

Headless assertions prove behavior, not appearance or latency. A change that is visible or interactive is validated in a real graphical Emacs session: the affected example or application is opened as its users open it, the four viewport classes — wide, ordinary, compact and short — are inspected, and a resize during interaction is exercised, because a layout that looks right in one screenshot can break at another width or height. Batch runs cannot certify either rendering or input latency: redisplay and input scheduling participate only in a GUI. The workspace manual keeps the recipe for validating an isolated checkout inside the full user init, including how to start or reuse a server and verify the frame and the loaded code.

The performance scenarios of the automated tooling are part of this validation, not a substitute for it. `scripts/performance.py` runs a registered scenario in batch mode for operation and CPU cost, or in GUI mode for real rendering and input timing; `gate` is the quick per-change check inside a GUI server, and `run`, `compare` and `summarize` are for diagnosis and evidence. A scenario's data flow, visible rendering and interaction are still read by a person before a feature is declared complete.

## Performance gates

<!-- index: performance gate; baseline; quiet tree -->

Performance is validated with the same seriousness as correctness. Establish a baseline before the change with `make verify-baseline`, then compare repeatable runs with `make verify BASELINE=…`; the report carries correctness results, latency samples and a regression comparison, and a final performance claim uses three independent sample sets. Screen only the representative scenarios a change affects while developing, and reserve the full matrix for acceptance. Measure on a quiet tree: any source change during a measurement marks the whole run unverified, so validation runs after the edits are committed. A failed, missing or incomparable gate stays unverified — including a pre-existing failure — because an absent or stale number is not a pass. [Performance Engineering](performance-engineering.md) describes the recorder and the measurement rules in full.

## A diagnostic is a defect

<!-- index: diagnostic; suppression -->

When the framework reports a warning while a test or an example runs — a component validation, a renderer warning, a byte-compilation or loader error — that report is the finding, not noise. It is read, traced to its owning layer and fixed there. It is never silenced with `ignore-errors`, a wider `condition-case`, a suppressed warning or an excluded test. Suppression is justified only when the diagnostic itself is wrong, and then the fix belongs where the diagnostic is raised. In the same spirit, a check is never weakened, an exclusion never added and a test never skipped to make a failure green; when a check has become obsolete, it is updated to the current contract while its behavioral coverage is kept.

## The manual is gated too

<!-- index: book gate; translation check -->

The book's own gate holds the documentation to the same standard. `make -C etaf-manual book-check` verifies the chapter structure, definition-entry signatures against the providers' Commentaries, coverage of documented packages and vocabularies, links, the public-symbol rule in prose, line discipline and the alignment of the two languages; the runnable-example acceptance mounts every `:run` example in every language, so an example that fails to evaluate or mount fails the gate. When a public interface changes, the affected chapters are updated in both languages in the same delivery, which is what keeps the manual a description of the current code rather than a snapshot of an earlier one.

## How evidence is handled

<!-- index: evidence; unverified -->

Measurement produces raw evidence, and raw evidence stays out of version control; the compact result is inspected before any specific failure log is opened. A run whose checkout changed during the measurement is marked unverified regardless of its numbers, a run with missing or stale comparison data is not treated as a pass, and a claim of improvement is repeated before it is believed. The same discipline applies to correctness: a scenario that was not run, or ran against the wrong code, has established nothing.
