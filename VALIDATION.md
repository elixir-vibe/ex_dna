# Real-world validation

This file records spot checks for clone quality and performance after the 1.5.2
correctness work. Measurements are local, warm-VM runs on 2026-06-11 and should
be treated as sanity checks rather than stable benchmarks.

## Configurations

- **default**: `min_mass: 30`
- **broad**: `min_mass: 30, literal_mode: :abstract, min_similarity: 0.85, normalize_pipes: true`

## Initial before/after sanity set

| Project | Config | Files | Clones | Type I | Type II | Type III | Time |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| ex_slop | default | 45 | 2 | 2 | 0 | 0 | 63ms |
| ex_slop | broad | 45 | 21 | 0 | 7 | 14 | 147ms |
| libcluster | default | 13 | 6 | 6 | 0 | 0 | 21ms |
| libcluster | broad | 13 | 15 | 6 | 0 | 9 | 61ms |
| postgrex | default | 70 | 12 | 8 | 4 | 0 | 139ms |
| postgrex | broad | 70 | 49 | 7 | 8 | 34 | 279ms |
| ecto | default | 56 | 9 | 8 | 1 | 0 | 359ms |
| ecto | broad | 56 | 33 | 8 | 4 | 21 | 2913ms |
| phoenix | default | 74 | 7 | 7 | 0 | 0 | 271ms |
| phoenix | broad | 74 | 19 | 7 | 4 | 8 | 647ms |
| livebook | default | 72 | 4 | 4 | 0 | 0 | 112ms |
| livebook | broad | 72 | 5 | 4 | 0 | 1 | 192ms |

## Broader public-project scan

Broad config only.

| Project | Files | Clones | Type I | Type II | Type III | Time | Top clone |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| ecto_sqlite3 | 5 | 1 | 0 | 0 | 1 | 144ms | type_iii:60:2 |
| postgrex | 70 | 49 | 7 | 8 | 34 | 363ms | type_iii:155:2 |
| ecto | 56 | 33 | 8 | 4 | 21 | 3196ms | type_i:126:2 |
| phoenix | 74 | 19 | 7 | 4 | 8 | 1886ms | type_iii:109:2 |
| live_view | 54 | 22 | 0 | 2 | 20 | 1331ms | type_iii:137:2 |
| livebook | 72 | 5 | 4 | 0 | 1 | 221ms | type_iii:95:3 |
| libcluster | 13 | 15 | 6 | 0 | 9 | 54ms | type_iii:189:2 |
| ex_slop | 45 | 21 | 0 | 7 | 14 | 119ms | type_iii:312:2 |
| ex_ast | 37 | 8 | 2 | 0 | 6 | 237ms | type_iii:121:2 |
| json_codec | 4 | 0 | 0 | 0 | 0 | 48ms | - |
| req_llm | 138 | 127 | 40 | 13 | 74 | 2504ms | type_ii:227:2 |
| jido_signal | 66 | 17 | 4 | 2 | 11 | 1042ms | type_iii:160:3 |
| fsst | 6 | 2 | 0 | 0 | 2 | 23ms | type_iii:79:2 |
| varint | 3 | 2 | 0 | 0 | 2 | 5ms | type_iii:71:2 |
| libgraph | 16 | 8 | 0 | 3 | 5 | 58ms | type_iii:129:2 |
| live_vue | 12 | 0 | 0 | 0 | 0 | 58ms | - |
| phoenix_iconify | 8 | 0 | 0 | 0 | 0 | 39ms | - |
| vibe_kit | 5 | 0 | 0 | 0 | 0 | 6ms | - |

## Manual triage notes

I hand-inspected the top broad-mode findings for the initial set and the
higher-count projects from the broader scan. This was not a full audit of every
reported clone, but it did cover the largest/most-visible findings.

Findings that looked actionable rather than random:

- **Postgrex** — extension modules such as `Box`/`LineSegment` and
  `Lquery`/`Ltree` share encode/decode scaffolding.
- **Libcluster** — strategy modules share GenServer lifecycle and polling/load
  structure.
- **Livebook** — runtime implementations share the same connection/evaluation
  callbacks.
- **Phoenix / LiveView** — channel broadcast variants, JS command helpers, and
  HEEx tokenizer/compiler branches are structurally similar API families.
- **ex_slop** — paired checks such as `filter_nil`/`reject_nil` intentionally
  mirror one another.
- **req_llm** — high clone count is concentrated in provider implementations
  and OpenAI-compatible adapter paths; this is a real duplication hotspot, but
  likely needs project-specific suppression/extraction decisions.
- **jido_signal** — repeated error modules and formatting branches are real
  repeated structure.
- **libgraph / ex_ast** — top findings are nearby API variants and traversal /
  relation helpers.

Validation uncovered and fixed two reporting-noise issues:

- Grouped Type-III clones could include duplicate same-file/same-line fragments
  from overlapping fuzzy candidates. Grouped fuzzy clone locations are now
  unique by file and line.
- Type-III `source_snippets` were blank, and grouped snippets could expose the
  internal `__ex_dna_grouped_def__` wrapper. Fuzzy clones now carry human-readable
  snippets with grouped definitions unwrapped.

Known caveat:

- Livebook emits charlist deprecation warnings while parsing under Elixir 1.20;
  those warnings come from the scanned project, not ExDNA.
