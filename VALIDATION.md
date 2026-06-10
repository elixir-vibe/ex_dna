# Real-world validation

This file records spot checks for clone quality and performance after the 1.5.2
correctness work. Measurements are local, warm-VM runs on 2026-06-11 and should
be treated as sanity checks rather than stable benchmarks.

## Configurations

- **default**: `min_mass: 30`
- **broad**: `min_mass: 30, literal_mode: :abstract, min_similarity: 0.85, normalize_pipes: true`

## Results

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

## Observations

- Default mode remains low-noise on the sampled projects.
- Broad Type-III mode surfaces expected families such as Postgrex extension
  modules, Libcluster strategies, Livebook runtime implementations, and Phoenix
  channel/socket variants.
- Validation uncovered and fixed duplicate same-location entries inside grouped
  Type-III clones; grouped fuzzy clone locations are now unique by file and line.
- Livebook emits charlist deprecation warnings while parsing under Elixir 1.20;
  those warnings come from the scanned project, not ExDNA.
