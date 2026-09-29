defmodule ExDNA.Detection.CachedDetector do
  @moduledoc """
  Adds complete-result caching to clone detection.

  Unchanged runs return the previously detected clone groups without rerunning
  detection. When any source changes, normal full detection refreshes the result;
  this avoids a large fragment cache whose serialization cost exceeded the work
  it saved.
  """

  alias ExDNA.{Cache, Config}
  alias ExDNA.Detection.{Detector, Pipeline}

  @type status :: :ok | :noop
  @type result :: {status(), [ExDNA.Detection.Clone.t()], non_neg_integer()}

  @doc """
  Run cached detection for `config`.

  Pass `:force` to refresh detection even when every source digest is current,
  and `:cache_path` to override the configured cache location.
  """
  @spec run(Config.t(), keyword()) :: result()
  def run(%Config{} = config, opts \\ []) do
    files = Pipeline.collect_files(config)

    run_cached(config, opts, Cache.source_digests(files), length(files), fn ->
      Detector.run(config)
    end)
  end

  @doc """
  Run cached detection on pre-parsed ASTs, as accepted by `Detector.run/2`.

  Digests come from the supplied source text (or the file on disk for
  `{file, ast}` pairs) keyed by the file's expanded path, so a filesystem run
  and an in-memory run over the same sources validate the same cache entry.
  """
  @spec run_on_pairs(
          Config.t(),
          [{String.t(), Macro.t()} | {String.t(), Macro.t(), String.t()}],
          keyword()
        ) :: result()
  def run_on_pairs(%Config{} = config, file_ast_pairs, opts \\ [])
      when is_list(file_ast_pairs) do
    run_cached(
      config,
      opts,
      pair_digests(file_ast_pairs),
      Detector.count_parsed(file_ast_pairs),
      fn ->
        Detector.run(config, file_ast_pairs)
      end
    )
  end

  defp run_cached(config, opts, current_digests, files_count, detect) do
    cache_path = Keyword.get(opts, :cache_path, config.cache_path)
    force? = Keyword.get(opts, :force, false)
    config_hash = Cache.config_hash(config)
    cached = Cache.read(cache_path, config_hash)

    if not force? and cached.clones != nil and cached.digests == current_digests do
      {:noop, cached.clones, files_count}
    else
      {clones, files_analyzed} = detect.()
      Cache.write(%{digests: current_digests, clones: clones}, cache_path, config_hash)
      {:ok, clones, files_analyzed}
    end
  end

  defp pair_digests(file_ast_pairs) do
    Map.new(file_ast_pairs, fn
      {file, _ast, source} -> {Path.expand(file), Cache.source_digest(source)}
      {file, _ast} -> {Path.expand(file), Cache.file_digest(file)}
    end)
  end
end
