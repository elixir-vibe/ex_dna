defmodule ExDNA.Cache do
  @moduledoc """
  Persistent cache for complete clone-analysis results.

  A lightweight source-digest map validates the cached clone groups without
  relying on filesystem timestamp resolution. When any source or output-shaping
  configuration changes, callers rerun normal analysis and replace the result.
  """

  @cache_version 5

  @type state :: %{
          digests: %{String.t() => binary() | nil},
          clones: [ExDNA.Detection.Clone.t()] | nil
        }

  @doc """
  Default cache file path relative to the project root.
  """
  @spec default_path :: String.t()
  def default_path, do: ".ex_dna_cache"

  @doc """
  Read cached source digests and clone groups.

  Returns an empty state if the file is missing, corrupt, configured for a
  different analysis, or written by an incompatible cache version.
  """
  @spec read(String.t(), binary()) :: state()
  def read(path \\ default_path(), config_hash \\ <<>>) do
    with {:ok, binary} <- File.read(path),
         {:ok, {@cache_version, ^config_hash, digests, clones}} <- safe_binary_to_term(binary) do
      %{digests: digests, clones: clones}
    else
      _error -> %{digests: %{}, clones: nil}
    end
  end

  @doc """
  Write source digests and complete clone groups to the cache.
  """
  @spec write(state(), String.t(), binary()) :: :ok | {:error, term()}
  def write(state, path \\ default_path(), config_hash \\ <<>>) do
    binary =
      :erlang.term_to_binary(
        {@cache_version, config_hash, state.digests, state.clones},
        [:compressed]
      )

    File.write(path, binary)
  end

  @doc """
  Compute a fingerprint of configuration fields that affect analysis output.
  """
  @spec config_hash(ExDNA.Config.t()) :: binary()
  def config_hash(config) do
    {config.min_mass, config.min_occurrences, config.min_similarity, config.literal_mode,
     config.normalize_pipes, config.excluded_macros, config.ignored_attributes,
     config.max_window_size, config.max_module_forms, config.mass_tolerance,
     config.min_fuzzy_mass, config.parse_timeout}
    |> :erlang.term_to_binary()
    |> then(&:erlang.md5/1)
  end

  @doc """
  Compute SHA-256 source digests for a file list.
  """
  @spec source_digests([String.t()]) :: %{String.t() => binary() | nil}
  def source_digests(files), do: Map.new(files, &{&1, file_digest(&1)})

  @doc """
  Get a SHA-256 digest of a source file, or `nil` when it cannot be read.
  """
  @spec file_digest(String.t()) :: binary() | nil
  def file_digest(file) do
    case File.read(file) do
      {:ok, source} -> :crypto.hash(:sha256, source)
      {:error, _reason} -> nil
    end
  end

  defp safe_binary_to_term(binary) do
    {:ok, :erlang.binary_to_term(binary)}
  rescue
    ArgumentError -> :error
  end
end
