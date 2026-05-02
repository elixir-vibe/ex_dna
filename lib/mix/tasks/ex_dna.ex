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
    * `--literal-mode` — `keep` (Type-I only) or `abstract` (also Type-II). Default: `keep`
    * `--normalize-pipes` — treat `x |> f()` the same as `f(x)`. Default: false
    * `--exclude-macro` — macro name to skip during analysis (repeatable).
      Common: `schema`, `pipe_through`, `plug`
    * `--ignore-attribute` — additional attribute name to ignore (repeatable).
      Documentation/type attributes (`moduledoc`, `doc`, `type`, `spec`, etc.)
      are ignored by default. Use this for project-specific noise.
    * `--ignore` — glob pattern to exclude (repeatable)
    * `--format` — output format: `console` (default), `json`, `html`, or `sarif`
    * `--max-clones` — maximum allowed clones. Exits with code 1 only when
      exceeded. Useful for gradual adoption in brownfield projects.

  Exits with code 1 if clones are found (or exceed `--max-clones`).
  """

  use Mix.Task

  alias ExDNA.CLI.Options

  @impl Mix.Task
  def run(argv) do
    {opts, paths, _} =
      OptionParser.parse(argv,
        strict: [
          min_mass: :integer,
          min_occurrences: :integer,
          min_similarity: :float,
          literal_mode: :string,
          normalize_pipes: :boolean,
          exclude_macro: :keep,
          ignore_attribute: :keep,
          ignore: :keep,
          format: :string,
          max_clones: :integer
        ],
        aliases: [m: :min_mass, o: :min_occurrences, s: :min_similarity, i: :ignore, f: :format]
      )

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
    reporters = reporters_for(Keyword.get(opts, :format, "console"))

    literal_mode =
      case Keyword.get(opts, :literal_mode, "keep") do
        "abstract" -> :abstract
        _ -> :keep
      end

    excluded_macros =
      case Keyword.get_values(opts, :exclude_macro) do
        [] -> nil
        macros -> Enum.map(macros, &String.to_atom/1)
      end

    extra_ignored =
      opts
      |> Keyword.get_values(:ignore_attribute)
      |> Enum.map(&String.to_atom/1)

    ignored_attributes =
      if extra_ignored != [] do
        ExDNA.Config.default(:ignored_attributes) ++ extra_ignored
      else
        nil
      end

    ignored_paths = Options.optional_values(opts, :ignore)

    [
      paths: if(paths != [], do: paths, else: ["lib/"]),
      reporters: reporters,
      literal_mode: literal_mode,
      normalize_pipes: Keyword.get(opts, :normalize_pipes, false)
    ]
    |> Options.maybe_put(:ignore, ignored_paths)
    |> Options.maybe_put(:min_mass, Keyword.get(opts, :min_mass))
    |> Options.maybe_put(:min_occurrences, Keyword.get(opts, :min_occurrences))
    |> Options.maybe_put(:min_similarity, Keyword.get(opts, :min_similarity))
    |> Options.maybe_put(:excluded_macros, excluded_macros)
    |> Options.maybe_put(:ignored_attributes, ignored_attributes)
  end

  defp reporters_for("json"), do: [ExDNA.Reporter.JSON]
  defp reporters_for("html"), do: [ExDNA.Reporter.HTML]
  defp reporters_for("sarif"), do: [ExDNA.Reporter.SARIF]
  defp reporters_for(_), do: [ExDNA.Reporter.Console]
end
