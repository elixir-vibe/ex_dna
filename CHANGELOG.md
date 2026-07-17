# Changelog

## 1.5.4

### Changed

- Lowered the declared minimum Elixir version from 1.19 to 1.18.

## 1.5.3

### Fixed

- **Nested pipe-chain noise** — nested pipe subtrees are now pruned using true
  AST line ranges, so one duplicated pipe-heavy function reports as one clone
  instead of several overlapping clones.
- **Clone type labeling** — Type-I detection now preserves variable names and
  literals, while Type-II handles renamed-variable clones and, in `:abstract`
  literal mode, changed-literal clones.
- **Incremental compiler cache** — cached fingerprints are now reused directly
  for unchanged files, cache invalidation covers all fingerprint-affecting
  options, and cache reads no longer fail in fresh BEAM VMs due to safe atom
  deserialization.
- **Type-III similarity normalization** — fuzzy clone scoring now respects the
  configured normalizer options, including pipe normalization.
- **Type-III grouping** — near-miss clone pairs are now grouped into connected
  clone sets, so 3+ related occurrences can satisfy `min_occurrences`.
- **Type-III snippets** — fuzzy clones now include source snippets and unwrap
  internal grouped-definition markers before reporting.
- **Mix task config precedence** — absent CLI defaults no longer overwrite
  values from `.ex_dna.exs`, and `mix ex_dna.explain` now accepts paths plus
  the same detection-shaping flags as `mix ex_dna`.
- **Large-module sibling windows** — the module-body cutoff is now configurable
  via `max_module_forms` / `--max-module-forms` and defaults to 200 forms.
- **LSH banding** — large Type-III candidate postings now use the existing LSH
  banding implementation instead of pairwise MinHash compatibility checks.
- **Report output paths** — HTML and SARIF output files can now be configured
  with `output_file` / `--output`.
- **CLI validation** — unknown options and invalid `--format` / `--literal-mode`
  values now fail with clear Mix errors.

## 1.5.2

### Changed

- **Suppression comments** — replaced the `@no_clone` module attribute with
  Credo-style comments (`# ex_dna:disable-for-next-line`, file,
  previous-line, and range variants), avoiding Elixir's unused attribute
  warning during compilation. (#11)

### Fixed

- **Credo integration suppression** — suppression comments now work when ExDNA
  runs through Credo's cached ASTs by carrying source text alongside the AST.
- **CI alias isolation** — `mix ci` now runs Credo, tests, Dialyzer, and ExDNA
  in separate Mix invocations to avoid application lifecycle conflicts.

### Tooling

- Updated development dependencies and enabled ExSlop's recommended plugin
  setup plus strict Credo checks.

## 1.5.1

### Fixed

- **Crash in extraction suggestions with differing alias components** —
  anti-unification now treats aliases as atomic AST nodes, preventing invalid
  `__aliases__` shapes such as `Pricing.{arg}.lookup(...)` from reaching
  `Code.Formatter`. (#8)

## 1.5.0

### New

- **Guard-aware normalization** — in `:abstract` mode, all calls inside
  `when` guard clauses are abstracted so that functions differing only in
  guard predicates are detected as clones. Covers Kernel guards, Erlang
  BIFs, `defguard` macros, and library guards like `Integer.is_even/1`.
- **Boolean operator canonicalization** — `&&`/`||`/`!` are rewritten to
  `and`/`or`/`not` so stylistic choice between short-circuit and keyword
  operators doesn’t prevent clone matching.
- **Sigil `~w` expansion** — `~w(foo bar)a` is expanded to `[:foo, :bar]`
  so sigil word-lists match their literal equivalents.
- **MinHash-accelerated fuzzy detection** — large posting lists (>50
  entries) now use MinHash signatures for O(k) approximate Jaccard instead
  of O(|A|+|B|) exact set operations. Removes the hard posting-list cap,
  improving recall for large monorepos without sacrificing precision.
- **HTML report syntax highlighting via Makeup** — proper Elixir
  tokenization with dark/light theme support, replacing the regex-based
  highlighter.
- **Configurable detection tuning** — previously hardcoded constants are
  now available as config options and CLI flags:
  - `max_window_size` (`--max-window-size`, default: 4) — max consecutive
    sibling functions combined into a single fingerprint for cross-module
    clone detection.
  - `mass_tolerance` (`--mass-tolerance`, default: 0.3) — max relative size
    difference for Type-III comparison.

### Changed

- **`ignored_attributes` default** — derived from
  `Module.reserved_attributes/0` instead of a hardcoded list. Picks up
  5 previously missing attributes and stays current with future Elixir
  versions automatically.

### Performance

- **Fused normalizer** — metadata stripping, boolean canonicalization, sigil
  expansion, pipe normalization, and variable renaming run in a single AST
  walk instead of 4 separate traversals. Ash (572 files) ~14% faster.

Benchmarked on real-world projects with full Type-I/II/III detection
(`literal_mode: :abstract, min_similarity: 0.85, normalize_pipes: true`):

| Project | Files | Clones | Time |
|---------|-------|--------|------|
| Broadway | 22 | 1 | 45ms |
| Nx | 42 | 12 | 674ms |
| Nerves | 50 | 2 | 172ms |
| Ecto | 56 | 19 | 525ms |
| Commanded | 63 | 8 | 147ms |
| Oban | 66 | 16 | 193ms |
| Phoenix | 74 | 14 | 607ms |
| Elixir stdlib | 105 | 84 | 1.6s |
| Surface | 109 | 31 | 513ms |
| Absinthe | 263 | 63 | 590ms |
| Livebook | 265 | 62 | 2.1s |
| Plausible | 465 | 80 | 2.4s |
| Ash | 572 | 535 | 5.8s |

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
