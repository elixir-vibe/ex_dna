defmodule ExDNA.Detection.Detector do
  @moduledoc """
  Orchestrates the clone detection pipeline.

  1. Collect files matching the configured paths/globs.
  2. Parse each file into an AST.
  3. Extract fingerprinted fragments from every AST.
  4. Group fragments by hash — groups of 2+ are clones.
  5. Filter out nested/overlapping clones.
  """

  alias ExDNA.Config
  alias ExDNA.Detection.{Clone, Filter, Fuzzy, Pipeline}
  alias ExDNA.Refactor.BehaviourSuggestion

  @doc """
  Run detection for the given config. Returns a list of `Clone` structs.
  """
  @spec run(Config.t()) :: {[Clone.t()], non_neg_integer()}
  def run(%Config{} = config) do
    files = Pipeline.collect_files(config)

    pairs =
      files
      |> Task.async_stream(
        fn file -> parse_file(file, config) end,
        max_concurrency: System.schedulers_online(),
        ordered: false
      )
      |> Enum.flat_map(fn {:ok, result} -> result end)

    {run_detection(config, pairs), length(pairs)}
  end

  @doc """
  Run detection on pre-parsed ASTs.

  Accepts a list of `{filename, ast}` tuples (e.g. from Credo's ETS cache)
  and skips file I/O and parsing entirely.
  """
  @spec run(Config.t(), [{String.t(), Macro.t()}]) :: {[Clone.t()], non_neg_integer()}
  def run(%Config{} = config, file_ast_pairs) when is_list(file_ast_pairs) do
    {run_detection(config, file_ast_pairs),
     Enum.count(file_ast_pairs, fn {_, ast} -> ast != nil end)}
  end

  defp run_detection(config, file_ast_pairs) do
    fragments = fingerprint_pairs(file_ast_pairs, config)

    type_i_clones = Pipeline.find_clones(fragments, :type_i)

    type_ii_clones =
      if config.min_similarity < 1.0 or config.literal_mode == :abstract do
        abstract_config = %{config | literal_mode: :abstract}
        fragments_ii = fingerprint_pairs(file_ast_pairs, abstract_config)

        Pipeline.find_clones(fragments_ii, :type_ii)
        |> reject_already_found(type_i_clones)
      else
        []
      end

    exact_clones =
      (type_i_clones ++ type_ii_clones)
      |> Filter.prune_nested()

    type_iii_clones = find_fuzzy_clones(fragments, exact_clones, config)

    (exact_clones ++ type_iii_clones)
    |> Enum.filter(&(length(&1.fragments) >= config.min_occurrences))
    |> Enum.map(&Pipeline.attach_suggestion/1)
    |> BehaviourSuggestion.analyze(Map.new(file_ast_pairs))
    |> Enum.sort_by(& &1.mass, :desc)
  end

  defp parse_file(file, config) do
    with {:ok, source} <- File.read(file),
         {:ok, ast} <- Pipeline.parse_with_timeout(source, file, config.parse_timeout) do
      [{file, ast}]
    else
      _ -> []
    end
  end

  defp fingerprint_pairs(pairs, config) do
    pairs
    |> Task.async_stream(
      fn {file, ast} -> Pipeline.fingerprint_ast(ast, file, config) end,
      max_concurrency: System.schedulers_online(),
      ordered: false
    )
    |> Enum.flat_map(fn {:ok, frags} -> frags end)
  end

  defp find_fuzzy_clones(_fragments, _exact_clones, %Config{min_similarity: s}) when s >= 1.0,
    do: []

  defp find_fuzzy_clones(fragments, exact_clones, config) do
    exact_locations =
      exact_clones
      |> Enum.flat_map(fn c -> Enum.map(c.fragments, &{&1.file, &1.line}) end)
      |> MapSet.new()

    exact_hashes = MapSet.new(exact_clones, & &1.hash)

    min_fuzzy_mass = config.min_mass * 2

    fragments
    |> Enum.filter(fn f -> f.mass >= min_fuzzy_mass end)
    |> Fuzzy.detect(config.min_similarity, exact_hashes)
    |> Enum.reject(fn clone ->
      Enum.any?(clone.fragments, fn f -> MapSet.member?(exact_locations, {f.file, f.line}) end)
    end)
  end

  defp reject_already_found(type_ii, type_i) do
    type_i_hashes = MapSet.new(type_i, & &1.hash)
    Enum.reject(type_ii, fn clone -> MapSet.member?(type_i_hashes, clone.hash) end)
  end
end
