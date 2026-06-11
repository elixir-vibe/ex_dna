# ExDNA 🧬

Code duplication detector for Elixir, inspired by
[jscpd](https://github.com/kucherenko/jscpd) but built on Elixir's native AST
instead of token matching.

Because ExDNA understands code structure — not just text —
`fn(a, b) -> a + b end` and `fn(x, y) -> x + y end` are recognized as the
same code. It also tells you *how* to fix each clone: extract a function, a
macro, or a behaviour callback.

## Features

- **Three clone types** — exact copies (I), renamed variables / changed
  literals (II), and near-miss clones via structural similarity (III)
- **Multi-clause awareness** — consecutive `def`/`defp` clauses with the same
  name/arity are analyzed as a single unit, catching duplicated pattern-matching
  functions that individual clauses are too small to flag
- **Delegation pattern detection** — `def foo(x), do: foo(x, [])` followed by
  `def foo(x, opts)` are grouped as one unit, catching duplicated wrapper+body
  pairs across modules
- **Sibling window detection** — adjacent functions copied between modules are
  caught even when the surrounding code differs
- **Refactoring suggestions** — extract function, extract macro, extract
  behaviour with `@callback`
- **Smart naming** — suggestions are named after the dominant struct, call,
  or pattern (`build_changeset`, `contact_step`) instead of
  `extracted_function`
- **Pipe normalization** — `x |> f()` and `f(x)` match as the same code
- **Field order normalization** — `%User{name: x, age: y}` and
  `%User{age: y, name: x}` match in Type-II mode
- **Guard normalization** — `when is_binary(x)` and `when is_atom(x)` match
  in Type-II mode (covers Kernel guards, `defguard`, library guards)
- **Boolean operator normalization** — `&&`/`||`/`!` match `and`/`or`/`not`
- **Sigil expansion** — `~w(foo bar)a` matches `[:foo, :bar]`
- **Cross-file grouping** — `actions/ ↔ tools/ (6 clones, 298 nodes)`
  instead of listing each pair
- **Credo-style suppression comments** — suppress known/intentional duplicates
- **Incremental `Mix.Task.Compiler`** — reuses cached fingerprints for unchanged files
- **LSP server** — pushes clone diagnostics to your editor alongside
  [Expert](https://github.com/elixir-lang/expert) or ElixirLS
- **Credo integration** — drop-in replacement for `DuplicatedCode`, reuses
  Credo's parsed ASTs
- **CI-ready** — exits with code 1 when clones are found, or use
  `--max-clones` for a clone budget
- **Four output formats** — Credo-style console, JSON, self-contained HTML,
  and [SARIF](https://sarifweb.azurewebsites.net/) for GitHub Code Scanning
- **Fast** — parallel file parsing, Plausible (465 files) in ~1 second,
  Ash (554 files) in ~6 seconds with full Type-I/II/III detection

## Installation

```elixir
def deps do
  [{:ex_dna, "~> 1.5", only: [:dev, :test], runtime: false}]
end
```

## Usage

```bash
mix ex_dna                              # scan lib/
mix ex_dna lib/accounts lib/admin       # specific paths
mix ex_dna --literal-mode abstract      # enable literal abstraction for Type-II
mix ex_dna --min-similarity 0.85        # enable Type-III (near-miss)
mix ex_dna --min-fuzzy-mass 80          # require larger Type-III candidates
mix ex_dna --min-mass 50                # fewer, larger clones
mix ex_dna --max-clones 10              # fail only above budget
mix ex_dna --format json                # machine-readable
mix ex_dna --format html                # browsable report
mix ex_dna --format sarif               # GitHub Code Scanning
```

Deep-dive into a specific clone:

```bash
mix ex_dna.explain 3
mix ex_dna.explain 3 lib/accounts --min-mass 20
```

Shows the full anti-unification breakdown — common structure, divergence
points, and the suggested extraction with call sites. Pass the same paths and
detection flags you used for `mix ex_dna` to keep clone numbering aligned.

### Typical workflows

```bash
mix ex_dna --min-mass 40
```

Start with exact and renamed-variable clones, then opt into broader matching as
needed:

```bash
mix ex_dna --literal-mode abstract      # include changed literals (Type II)
mix ex_dna --min-similarity 0.85       # include near-miss clones (Type III)
mix ex_dna --normalize-pipes           # compare pipe chains and nested calls
```

For noisy brownfield projects, raise `--min-mass` or `--min-fuzzy-mass`, and use
`--max-clones` as a clone budget while paying down duplication.

### Programmatic API

```elixir
report = ExDNA.analyze("lib/")
report = ExDNA.analyze(["lib/", "test/"])
report = ExDNA.analyze(paths: ["lib/"], min_mass: 20, literal_mode: :abstract)

report.clones   #=> [%ExDNA.Detection.Clone{}, ...]
report.stats    #=> %{files_analyzed: 42, total_clones: 3, ...}
```

## Configuration

Options are layered: **defaults → `.ex_dna.exs` → CLI flags**.

Create `.ex_dna.exs` in your project root:

```elixir
%{
  min_mass: 25,
  min_occurrences: 3,
  ignore: ["lib/my_app_web/templates/**"],
  excluded_macros: [:schema, :pipe_through, :plug],
  normalize_pipes: true
}
```

| Option | CLI flag | Default | Description |
|--------|----------|---------|-------------|
| `min_mass` | `--min-mass` | `30` | Minimum AST nodes for a fragment |
| `min_occurrences` | `--min-occurrences` | `2` | Minimum number of code occurrences to label a clone |
| `min_similarity` | `--min-similarity` | `1.0` | Threshold for Type-III (set < 1.0 to enable) |
| `min_fuzzy_mass` | `--min-fuzzy-mass` | `min_mass * 2` | Minimum AST nodes for Type-III candidates |
| `literal_mode` | `--literal-mode` | `keep` | `keep` = exact + renamed-variable clones, `abstract` = also changed-literal clones |
| `normalize_pipes` | `--normalize-pipes` | `false` | Treat `x \|> f()` same as `f(x)` |
| `excluded_macros` | `--exclude-macro` | `[]` | Macro calls to skip entirely |
| `ignored_attributes` | `--ignore-attribute` | *(see below)* | Module attribute names to skip |
| `max_module_forms` | `--max-module-forms` | `200` | Max top-level forms eligible for sibling-window detection |
| `parse_timeout` | — | `5000` | Max ms per file (kills hung parses) |
| `ignore` | `--ignore` | `[]` | Glob patterns to exclude |
| — | `--max-clones` | — | Clone budget (exit 1 only above this) |
| — | `--format` | `console` | `console`, `json`, `html`, or `sarif` |
| `output_file` | `--output` | format default | Output path for HTML/SARIF reports |

**Default ignored attributes:** all of Elixir's
[reserved attributes](https://hexdocs.pm/elixir/Module.html#reserved_attributes/0)
(`moduledoc`, `doc`, `spec`, `type`, `impl`, `behaviour`, `derive`, etc.).

Custom module attributes like `@extensions`, `@timeout`, or `@fields` **are**
fingerprinted and will be reported as duplicates when they appear with the
same value in multiple modules.

## Suppressing clones

Use Credo-style comments when a duplicate is intentional:

```elixir
defmodule MyApp.Validator do
  # ex_dna:disable-for-next-line
  def validate(params) do
    # intentional duplication, won't be flagged
  end
end
```

Supported comments:

```elixir
# ex_dna:disable-for-this-file
# ex_dna:disable-for-next-line
# ex_dna:disable-for-previous-line
# ex_dna:disable-for-lines:3
```

## max_clones / min_occurrences

* `min_occurrences` → only report clone groups appearing in 3+ locations
* `max_clones` → return non-zero exit if more than 10 reportable clone groups remain

Note that `max_clones` applies after report filters like `min_occurrences` so
clones that were not reported due to `min_occurrences` are not counted towards the `max_clones` budget.

## Incremental detection

Add ExDNA as a compiler for automatic detection on `mix compile`:

```elixir
def project do
  [compilers: Mix.compilers() ++ [:ex_dna]]
end
```

Only changed files are re-analyzed. Cache is stored in `.ex_dna_cache` (add to
`.gitignore`).

## Editor integration

ExDNA ships an LSP server that pushes warnings inline on every save. It runs
alongside your primary Elixir LSP.

```bash
mix ex_dna.lsp
```

### Neovim

```lua
vim.lsp.config('ex_dna', {
  cmd = { 'mix', 'ex_dna.lsp' },
  root_markers = { 'mix.exs' },
  filetypes = { 'elixir' },
})
```

## Credo integration

ExDNA ships a Credo check that replaces the built-in `DuplicatedCode` with
full Type-I/II/III detection and refactoring suggestions. It reuses Credo's
already-parsed ASTs — no double parsing.

Use as a Credo plugin (recommended) — automatically registers the check and
disables the built-in `DuplicatedCode`:

```elixir
# .credo.exs
%{
  configs: [
    %{
      name: "default",
      plugins: [{ExDNA.Credo, []}]
    }
  ]
}
```

Or add directly to the `:enabled` checks list:

```elixir
{ExDNA.Credo, []}
```

And disable the built-in check:

```elixir
{Credo.Check.Design.DuplicatedCode, false}
```

All ExDNA options are available as check/plugin params. By default the Credo check uses the same path scope as `mix ex_dna` (`lib/`); pass `paths: ["lib/", "test/"]` if you want Credo to include test files too.

```elixir
{ExDNA.Credo, [
  paths: ["lib/", "test/"],
  min_mass: 40,
  literal_mode: :abstract,
  excluded_macros: [:schema, :pipe_through],
  normalize_pipes: true,
  min_similarity: 0.85
]}
```

## How it works

1. **Parse** — `Code.string_to_quoted/2` on every `.ex`/`.exs` file (parallel,
   with per-file timeout)
2. **Normalize** — strip line/column metadata → rename variables to positional
   placeholders (`$0`, `$1`) → optionally abstract literals → optionally
   flatten pipes → sort struct/map fields
3. **Fingerprint** — walk every subtree above `min_mass` nodes, hash with
   BLAKE2b; also generate sliding windows over module-level sibling sequences
   and compute structural sub-hashes for fuzzy candidate pruning
4. **Detect** — group by hash (Type I/II); use inverted index on sub-hashes +
   Jaccard similarity + tree edit distance for Type III
5. **Filter** — prune nested clones, keep the largest match per location
6. **Suggest** — anti-unify each clone pair to compute the common structure,
   generate extract-function/macro/behaviour suggestions

## Part of Elixir Vibe

ExDNA finds duplicated Elixir code by structure and computes the canonical extraction for each clone family.

It is one building block of a larger stack — tools that make AI-generated
software checkable: structural search, dependence analysis, duplication and
slop detection, session replay, and ecosystem-wide code search. See the
[Elixir Vibe](https://github.com/elixir-vibe) organization for the rest, and
[Building Blocks for the Future Web](https://github.com/elixir-vibe/building-blocks)
for the thesis, architecture, and roadmap that tie them together.

## License

[MIT](LICENSE)
