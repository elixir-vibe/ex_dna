# Changelog

## Unreleased

### New

- **Guard-aware normalization** — in `:abstract` mode, guard type-check
  functions (`is_binary`, `is_atom`, `is_integer`, …) are replaced with a
  placeholder so that functions differing only in guard predicates are
  detected as clones.
- **MinHash-accelerated fuzzy detection** — large posting lists (>50
  entries) now use MinHash signatures for O(k) approximate Jaccard instead
  of O(|A|+|B|) exact set operations. Removes the hard posting-list cap,
  improving recall for large monorepos without sacrificing precision.
  Plausible (465 files) full I/II/III detection ≈ 9% faster.
- **Configurable fuzzy detection tuning** — previously hardcoded constants
  are now available as config options and CLI flags:
  - `max_window_size` (`--max-window-size`, default: 4) — max consecutive
    sibling functions combined into a single fingerprint for cross-module
    clone detection. Raise to catch clones spanning more adjacent functions.
  - `mass_tolerance` (`--mass-tolerance`, default: 0.3) — max relative size
    difference for Type-III comparison. Raise toward 0.5 to catch clones
    between thin wrappers and fat implementations.

## 1.4.3

### Fixed

- **Config-file ignore patterns in Mix tasks** — `mix ex_dna` and
  `mix ex_dna.explain` now preserve `:ignore` from `.ex_dna.exs` unless
  `--ignore` is explicitly provided on the CLI. (#9)

## 1.4.2

### Fixed

- **Crash in extraction suggestions with differing callees** — Near-miss clones
  that differ in local or remote function names are still reported, but ExDNA no
  longer tries to generate an invalid extracted-function suggestion for them.
  This avoids `Code.Formatter`/`Macro.to_string` crashes on Elixir 1.18. (#8)

## 1.4.1

### Fixed

- **Mix aliases stop when clones are found** — `mix ex_dna` now raises a Mix
  error instead of deferring exit status until VM shutdown, so aliases halt at
  the ExDNA step. (#6)
- **Credo plugin registration and scope** — Plugin params are forwarded to the
  registered check, the plugin preserves Credo's default checks, and the Credo
  integration defaults to the same `lib/` scope as `mix ex_dna`. (#7)

## 1.4.0

### New

- **Module attribute duplicate detection** — Custom module attributes like
  `@extensions`, `@timeout`, or `@fields` are now fingerprinted and reported
  when they appear with the same value in multiple modules. Previously all
  `@` nodes were blanket-excluded.
- **`ignored_attributes` config** — Fine-grained control over which attribute
  names to skip. Defaults cover documentation and type-system attributes
  (`moduledoc`, `doc`, `type`, `spec`, `impl`, `behaviour`, etc. — 26 total).
  Custom attributes are fingerprinted automatically.
- **`--ignore-attribute` CLI flag** — Add project-specific attribute names to
  the ignore list (repeatable, additive to defaults).

### Changed

- **`excluded_macros` default is now `[]`** — Module attributes are no longer
  excluded via `excluded_macros: [:@]`. Instead, the new `ignored_attributes`
  list handles attribute filtering with per-name granularity. Projects that
  explicitly set `excluded_macros: [:@, ...]` in `.ex_dna.exs` can remove `:@`.

## 1.3.1

### Fixed

- **Credo plugin mode** — `ExDNA.Credo` now works as both a Credo plugin
  (`plugins: [{ExDNA.Credo, []}]`) and a standalone check. When used as a
  plugin, it automatically registers itself and disables the built-in
  `DuplicatedCode`. (#4)
- **Credo module not found** — Changed `credo` dependency from `only: [:dev, :test]`
  to `optional: true`, ensuring proper compilation order in consumer projects.
  Previously `ExDNA.Credo` could fail to compile when `credo` was compiled
  after `ex_dna`. (#4)
- **False positives on `use`/`import` blocks** — `excluded_macros` now applies
  to sibling window fingerprinting. Previously, adjacent `use`/`import`
  statements were combined into synthetic fragments and flagged as duplicates
  even when those macros were excluded. (#5)

## 1.3.0

### New

- **SARIF output** — `mix ex_dna --format sarif` generates a report compatible
  with GitHub Code Scanning, VS Code SARIF Viewer, and other standard tools.
- **Clone budget for CI** — `mix ex_dna --max-clones 10` exits with code 1
  only when the count exceeds the budget. Useful for gradual adoption in
  brownfield projects.
- **Near-miss detection scales to large codebases** — Type-III detection
  reworked with an inverted index on structural sub-hashes. Previously choked
  on 200+ file projects; now handles 500+ files in seconds.
- **Sibling window detection** — Catches duplicated groups of adjacent
  `def`/`defp` that were previously invisible because they didn't share a
  common AST parent. For example, three consecutive functions copied between
  controllers are now detected even if the surrounding module code differs.
- **Delegation pattern detection** — `def fetch(id), do: fetch(id, [])` +
  `def fetch(id, opts)` are grouped as one unit. Duplicated wrapper+body
  pairs across modules are now caught.
- **Struct/map field order doesn't matter** — `%User{name: x, age: y}` and
  `%User{age: y, name: x}` match in Type-II mode.

### Fixed

- **Crash on `%{acc | field: value}` syntax** in abstract mode.
- **Crash on `__MODULE__.function()` calls** during analysis.
- **Crash when passing a list of paths** — `ExDNA.analyze(["lib/", "test/"])`
  now works as documented.
- **`--max-clones` output was printing literal text** instead of actual numbers.
- **Suggestions for clones with 3+ occurrences** showed wrong call sites for
  the 3rd+ occurrence. Now each occurrence gets its own anti-unification.
- **Cache wasn't invalidated** when changing `min_mass`, `literal_mode`, or
  other detection options. Stale results were served silently.
- **`_` and `__MODULE__` were renamed** during variable normalization, causing
  false positives in Type-II detection.
- **HTML report links were dead** (`href="#"`). Now clickable `file://` URIs
  that open in your editor.
- **Behaviour suggestions fired for private functions.** `@callback` only
  makes sense for `def`, not `defp`.
- **Same-file clone diagnostics in LSP** were missing cross-references to
  other locations within the same file.
- **`files_analyzed` stat** counted files that failed to parse. Now only
  counts successfully analyzed files.
- **Glob patterns** with `?`, character classes, and edge cases now work
  correctly.

### Improved

- **Compiler runs full detection** — The incremental compiler now finds
  Type-I, II, and III clones (previously only Type-I).
- **Detection timing is accurate** — `detection_time_ms` in stats reflects
  actual detection time, not wall clock including report generation.
- **JSON output includes behaviour suggestions** — Previously only console
  and HTML reports showed them.
- **Config validation** — Invalid options like `min_mass: -1` or
  `literal_mode: :foo` now raise immediately with a clear message.
- **HTML report uses EEx templates** — Easier to customize.
- **Zero dialyzer warnings** — All previously suppressed errors resolved.

### Performance

Benchmarked on real-world open-source projects with full Type-I/II/III
detection (`min_mass: 30, literal_mode: :abstract, min_similarity: 0.85`):

| Project | Files | Clones | Time |
|---------|-------|--------|------|
| Phoenix | 74 | 15 | 0.3s |
| Ecto | 56 | 20 | 0.5s |
| Oban | 64 | 21 | 0.1s |
| Livebook | 264 | 64 | 2.4s |
| Plausible | 465 | 83 | 3.8s |
| Ash | 554 | 524 | 9.8s |

## 1.2.2

- Skip `__block__` nodes in fingerprinting

## 1.2.1

- Harden Credo duplicate issue reporting

## 1.2.0

- Detect duplicated multi-clause functions

## 1.1.0

- Credo integration via `ExDNA.Credo` check
- `Detector.run/2` accepts pre-parsed ASTs

## 1.0.0

- Initial release
- Type-I/II/III clone detection
- Refactoring suggestions
- Cross-file grouping
- `@no_clone` annotation
- Incremental compiler
- LSP server
- Console, JSON, HTML reporters
