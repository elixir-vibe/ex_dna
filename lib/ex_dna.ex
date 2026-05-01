defmodule ExDNA do
  @moduledoc """
  Code duplication detector for Elixir, powered by native AST analysis.

  ExDNA understands code structure, not just text. It normalizes variable names,
  abstracts literals, and compares AST subtrees — so renamed copies and
  near-miss clones are caught too. Each clone comes with a concrete refactoring
  suggestion.

  ## Quick start

      report = ExDNA.analyze("lib/")
      report.clones   #=> [%ExDNA.Detection.Clone{}, ...]
      report.stats    #=> %{files_analyzed: 42, total_clones: 3, ...}

  ## Clone types

  - **Type I** — exact copies (modulo whitespace/comments)
  - **Type II** — renamed variables and/or changed literals
  - **Type III** — near-miss clones (similar structure ± edits)

  ## Configuration

  Pass options to `analyze/1` or configure in `.ex_dna.exs`:

      %{
        min_mass: 30,
        min_occurrences: 3,
        min_similarity: 0.85,
        paths: ["lib/"],
        ignore: ["lib/my_app_web/templates/**"]
      }

  See the README for the full option reference.
  """

  alias ExDNA.{Config, Detection, Report}

  @type path_or_paths :: String.t() | [String.t()]

  @doc """
  Analyze files for code duplication.

  Accepts a path string, a list of path strings, or a keyword list of options.

  ## Options

    * `:paths` — list of file/directory paths to scan (default: `["lib/"]`)
    * `:min_mass` — minimum AST node count for a fragment to be considered (default: `#{Config.default(:min_mass)}`)
    * `:min_occurrences` - minimum number of code occurrences to label a clone (default: `#{Config.default(:min_occurrences)}`)
    * `:min_similarity` — similarity threshold 0.0–1.0 (default: `#{Config.default(:min_similarity)}`)
    * `:ignore` — list of glob patterns to exclude
    * `:reporters` — list of reporter modules (default: `[ExDNA.Reporter.Console]`)

  ## Examples

      ExDNA.analyze("lib/")
      ExDNA.analyze(["lib/", "test/"])
      ExDNA.analyze(paths: ["lib/", "test/"], min_mass: 20)
  """
  @spec analyze(path_or_paths() | keyword()) :: Report.t()
  def analyze(path_or_opts \\ [])

  def analyze(path) when is_binary(path), do: analyze(paths: [path])

  def analyze(paths) when is_list(paths) do
    if Keyword.keyword?(paths) do
      do_analyze(paths)
    else
      do_analyze(paths: paths)
    end
  end

  defp do_analyze(opts) do
    config = Config.new(opts)

    {elapsed_us, {clones, files_analyzed}} = :timer.tc(fn -> Detection.Detector.run(config) end)

    Report.new(clones, config,
      detection_time_ms: div(elapsed_us, 1000),
      files_analyzed: files_analyzed
    )
  end
end
