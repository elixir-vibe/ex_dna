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
    cache_path = Keyword.get(opts, :cache_path, config.cache_path)
    force? = Keyword.get(opts, :force, false)
    config_hash = Cache.config_hash(config)
    files = Pipeline.collect_files(config)
    current_digests = Cache.source_digests(files)
    cached = Cache.read(cache_path, config_hash)

    if not force? and cached.clones != nil and cached.digests == current_digests do
      {:noop, cached.clones, length(files)}
    else
      {clones, files_analyzed} = Detector.run(config)
      Cache.write(%{digests: current_digests, clones: clones}, cache_path, config_hash)
      {:ok, clones, files_analyzed}
    end
  end
end
