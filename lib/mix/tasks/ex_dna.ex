defmodule Mix.Tasks.ExDna do
  @shortdoc "Detect code duplication in your Elixir project"
  @moduledoc """
  Scans your project for duplicated code blocks using AST analysis.

      $ mix ex_dna
      $ mix ex_dna lib/my_app/accounts
      $ mix ex_dna --min-mass 20 --literal-mode abstract
      $ mix ex_dna --min-similarity 0.85

  ## Command-line options

    * `--min-mass` — minimum AST node count (default: 30)
    * `--min-occurrences` — minimum number of code occurrences to report a clone (default: 2)
    * `--min-similarity` — similarity threshold 0.0–1.0 (default: 1.0).
      Values below 1.0 enable Type-III near-miss detection.
    * `--max-window-size` — max consecutive sibling functions combined into
      a single fingerprint (default: 4). Raise to catch larger cross-module clones.
    * `--mass-tolerance` — max relative size difference for Type-III comparison,
      0.0–1.0 (default: 0.3). Raise to compare fragments of more different sizes.
    * `--min-fuzzy-mass` — minimum AST node count for Type-III candidates
      (default: `min_mass * 2`).
    * `--max-module-forms` — max top-level module forms eligible for sibling
      window detection (default: 200).
    * `--literal-mode` — `keep` (Type-I only) or `abstract` (also Type-II). Default: `keep`
    * `--normalize-pipes` — treat `x |> f()` the same as `f(x)`. Default: false
    * `--exclude-macro` — macro name to skip during analysis (repeatable).
      Common: `schema`, `pipe_through`, `plug`
    * `--ignore-attribute` — additional attribute name to ignore (repeatable).
      Documentation/type attributes (`moduledoc`, `doc`, `type`, `spec`, etc.)
      are ignored by default. Use this for project-specific noise.
    * `--ignore` — glob pattern to exclude (repeatable)
    * `--format` — output format: `console` (default), `json`, `html`, or `sarif`
    * `--output` — output file for `html` or `sarif` reports
    * `--max-clones` — maximum allowed clones. Exits with code 1 only when
      exceeded. Useful for gradual adoption in brownfield projects.

  Exits with code 1 if clones are found (or exceed `--max-clones`).
  """

  use Mix.Task

  alias ExDNA.CLI.Options

  @impl Mix.Task
  def run(argv) do
    {opts, paths, invalid} =
      OptionParser.parse(argv,
        strict: [
          min_mass: :integer,
          min_occurrences: :integer,
          min_similarity: :float,
          max_window_size: :integer,
          max_module_forms: :integer,
          mass_tolerance: :float,
          min_fuzzy_mass: :integer,
          literal_mode: :string,
          normalize_pipes: :boolean,
          exclude_macro: :keep,
          ignore_attribute: :keep,
          ignore: :keep,
          format: :string,
          output: :string,
          max_clones: :integer
        ],
        aliases: [m: :min_mass, o: :min_occurrences, s: :min_similarity, i: :ignore, f: :format]
      )

    Options.validate_parse!(invalid)

    config_opts = build_config(opts, paths)
    report = ExDNA.analyze(config_opts)
    detection_ms = report.stats.detection_time_ms

    unless Keyword.get(opts, :format) in ["json", "sarif"] do
      IO.puts("  Detection time:     #{detection_ms}ms\n")
    end

    max_clones = Keyword.get(opts, :max_clones)
    total = report.stats.total_clones

    if max_clones && Keyword.get(opts, :format) not in ["json", "sarif"] do
      IO.puts("  Clone budget:       #{total}/#{max_clones}\n")
    end

    should_fail =
      if max_clones do
        total > max_clones
      else
        total > 0
      end

    if should_fail do
      Mix.raise(failure_message(total, max_clones))
    end
  end

  defp failure_message(total, nil), do: "ExDNA found #{total} clone(s)"

  defp failure_message(total, max_clones) do
    "ExDNA found #{total} clone(s), exceeding the configured budget of #{max_clones}"
  end

  defp build_config(opts, paths) do
    reporters =
      if Keyword.has_key?(opts, :format) do
        reporters_for(Keyword.fetch!(opts, :format))
      end

    ignored_paths = Options.optional_values(opts, :ignore)

    []
    |> Options.maybe_put(:paths, if(paths != [], do: paths))
    |> Options.maybe_put(:reporters, reporters)
    |> Options.maybe_put(:literal_mode, Options.literal_mode(opts))
    |> Options.maybe_put(:normalize_pipes, Options.explicit_value(opts, :normalize_pipes))
    |> Options.maybe_put(:ignore, ignored_paths)
    |> Options.maybe_put(:min_mass, Keyword.get(opts, :min_mass))
    |> Options.maybe_put(:min_occurrences, Keyword.get(opts, :min_occurrences))
    |> Options.maybe_put(:min_similarity, Keyword.get(opts, :min_similarity))
    |> Options.maybe_put(:max_window_size, Keyword.get(opts, :max_window_size))
    |> Options.maybe_put(:max_module_forms, Keyword.get(opts, :max_module_forms))
    |> Options.maybe_put(:mass_tolerance, Keyword.get(opts, :mass_tolerance))
    |> Options.maybe_put(:min_fuzzy_mass, Keyword.get(opts, :min_fuzzy_mass))
    |> Options.maybe_put(:excluded_macros, Options.excluded_macros(opts))
    |> Options.maybe_put(:ignored_attributes, Options.ignored_attributes(opts))
    |> Options.maybe_put(:output_file, Keyword.get(opts, :output))
  end

  defp reporters_for("console"), do: [ExDNA.Reporter.Console]
  defp reporters_for("json"), do: [ExDNA.Reporter.JSON]
  defp reporters_for("html"), do: [ExDNA.Reporter.HTML]
  defp reporters_for("sarif"), do: [ExDNA.Reporter.SARIF]

  defp reporters_for(format) do
    Mix.raise("Invalid format #{inspect(format)}. Expected one of: console, json, html, sarif")
  end
end
