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

  Accepts a list of `{filename, ast}` or `{filename, ast, source}` tuples
  (e.g. from Credo's ETS cache) and skips parsing entirely.
  """
  @spec run(Config.t(), [{String.t(), Macro.t()} | {String.t(), Macro.t(), String.t()}]) ::
          {[Clone.t()], non_neg_integer()}
  def run(%Config{} = config, file_ast_pairs) when is_list(file_ast_pairs) do
    {run_detection(config, file_ast_pairs),
     Enum.count(file_ast_pairs, fn
       {_, ast} -> ast != nil
       {_, ast, _} -> ast != nil
     end)}
  end

  @doc false
  @spec run_from_fragments(Config.t(), [map()], [map()], [
          {String.t(), Macro.t()} | {String.t(), Macro.t(), String.t()}
        ]) :: [Clone.t()]
  def run_from_fragments(%Config{} = config, type_i_fragments, type_ii_fragments, file_ast_pairs)
      when is_list(type_i_fragments) and is_list(type_ii_fragments) and is_list(file_ast_pairs) do
    detect_from_fragments(config, type_i_fragments, type_ii_fragments, file_ast_pairs)
  end

  defp run_detection(config, file_ast_pairs) do
    type_i_config = fingerprint_config(config, literal_mode: :keep, normalize_variables: false)
    type_i_fragments = fingerprint_pairs(file_ast_pairs, type_i_config)

    type_ii_config =
      fingerprint_config(config,
        literal_mode: config.literal_mode,
        normalize_variables: true
      )

    type_ii_fragments = fingerprint_pairs(file_ast_pairs, type_ii_config)

    detect_from_fragments(config, type_i_fragments, type_ii_fragments, file_ast_pairs)
  end

  defp detect_from_fragments(config, type_i_fragments, type_ii_fragments, file_ast_pairs) do
    type_i_clones = Pipeline.find_clones(type_i_fragments, :type_i)

    type_ii_clones =
      type_ii_fragments
      |> Pipeline.find_clones(:type_ii)
      |> reject_already_found(type_i_clones)

    exact_clones =
      (type_i_clones ++ type_ii_clones)
      |> Filter.prune_nested()

    type_iii_clones = find_fuzzy_clones(type_i_fragments, exact_clones, config)

    (exact_clones ++ type_iii_clones)
    |> Enum.filter(&(length(&1.fragments) >= config.min_occurrences))
    |> Enum.map(&Pipeline.attach_suggestion/1)
    |> BehaviourSuggestion.analyze(ast_map(file_ast_pairs))
    |> Enum.sort_by(& &1.mass, :desc)
  end

  defp parse_file(file, config) do
    with {:ok, source} <- File.read(file),
         {:ok, ast} <- Pipeline.parse_with_timeout(source, file, config.parse_timeout) do
      [{file, ast, source}]
    else
      _ -> []
    end
  end

  defp fingerprint_pairs(pairs, config) do
    pairs
    |> Task.async_stream(
      fn
        {file, ast} -> Pipeline.fingerprint_ast(ast, file, config)
        {file, ast, source} -> Pipeline.fingerprint_ast(ast, file, config, source)
      end,
      max_concurrency: System.schedulers_online(),
      ordered: false
    )
    |> Enum.flat_map(fn {:ok, frags} -> frags end)
  end

  defp ast_map(file_ast_pairs) do
    Map.new(file_ast_pairs, fn
      {file, ast} -> {file, ast}
      {file, ast, _source} -> {file, ast}
    end)
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

    normalizer_opts = [
      literal_mode: config.literal_mode,
      normalize_pipes: config.normalize_pipes,
      normalize_variables: true
    ]

    fragments
    |> Enum.filter(fn f -> f.mass >= min_fuzzy_mass end)
    |> Fuzzy.detect(config.min_similarity, exact_hashes,
      mass_tolerance: config.mass_tolerance,
      normalizer_opts: normalizer_opts
    )
    |> Enum.reject(fn clone ->
      Enum.any?(clone.fragments, fn f -> MapSet.member?(exact_locations, {f.file, f.line}) end)
    end)
  end

  defp reject_already_found(type_ii, type_i) do
    type_i_locations = MapSet.new(type_i, &clone_location_signature/1)

    Enum.reject(type_ii, fn clone ->
      MapSet.member?(type_i_locations, clone_location_signature(clone))
    end)
  end

  defp clone_location_signature(clone) do
    clone.fragments
    |> Enum.map(&{&1.file, &1.line, &1.mass})
    |> Enum.sort()
  end

  defp fingerprint_config(config, overrides) do
    config
    |> Map.from_struct()
    |> Map.merge(Map.new(overrides))
  end
end
