defmodule ExDNA.Detection.Pipeline do
  @moduledoc false

  alias ExDNA.AST.{Annotator, ClauseGrouper, Fingerprint}
  alias ExDNA.Config
  alias ExDNA.Detection.Clone
  alias ExDNA.Refactor.Suggestion

  @spec collect_files(Config.t()) :: [String.t()]
  def collect_files(%Config{paths: paths, ignore: ignore_patterns}) do
    ignored_files =
      ignore_patterns
      |> Enum.flat_map(&Path.wildcard/1)
      |> Enum.map(&Path.expand/1)
      |> MapSet.new()

    paths
    |> Enum.flat_map(&expand_path/1)
    |> Enum.map(&Path.expand/1)
    |> Enum.reject(&MapSet.member?(ignored_files, &1))
    |> Enum.uniq()
    |> Enum.sort()
  end

  @spec parse_and_fingerprint(String.t(), Config.t()) :: [Fingerprint.fragment()]
  def parse_and_fingerprint(file, config) do
    with {:ok, source} <- File.read(file),
         {:ok, ast} <- parse_with_timeout(source, file, config.parse_timeout) do
      fingerprint_ast(ast, file, config, source)
    else
      _ -> []
    end
  end

  @doc """
  Fingerprint a pre-parsed AST for the given file path.

  Use this when the AST is already available (e.g. from Credo's ETS cache)
  to avoid re-parsing.
  """
  @spec fingerprint_ast(Macro.t(), String.t(), Config.t()) :: [Fingerprint.fragment()]
  def fingerprint_ast(ast, file, config) do
    source = if File.regular?(file), do: File.read!(file), else: ""
    fingerprint_ast(ast, file, config, source)
  end

  @spec fingerprint_ast(Macro.t(), String.t(), Config.t(), String.t()) :: [Fingerprint.fragment()]
  def fingerprint_ast(ast, file, config, source) do
    ignored_lines = Annotator.suppressed_lines(source)

    if ignored_lines == :all do
      []
    else
      ast =
        ast
        |> Annotator.strip_suppressed(ignored_lines)
        |> ClauseGrouper.group()

      Fingerprint.fragments(ast, file, config.min_mass,
        literal_mode: config.literal_mode,
        normalize_pipes: config.normalize_pipes,
        excluded_macros: config.excluded_macros,
        ignored_attributes: config.ignored_attributes,
        max_window_size: config.max_window_size
      )
    end
  end

  @spec find_clones([Fingerprint.fragment()], Clone.clone_type()) :: [Clone.t()]
  def find_clones(fragments, type) do
    fragments
    |> Enum.group_by(& &1.hash)
    |> Enum.filter(fn {_hash, group} -> length(group) >= 2 end)
    |> Enum.map(fn {_hash, group} -> Clone.from_fragments(group, type) end)
  end

  @spec attach_suggestion(Clone.t()) :: Clone.t()
  def attach_suggestion(clone) do
    case Suggestion.suggest(clone) do
      nil -> clone
      suggestion -> %{clone | suggestion: suggestion}
    end
  end

  defp expand_path(path) do
    cond do
      File.dir?(path) ->
        Path.wildcard(Path.join(path, "**/*.{ex,exs}"))

      String.contains?(path, "*") ->
        Path.wildcard(path)

      File.regular?(path) ->
        [path]

      true ->
        []
    end
  end

  @doc false
  @spec parse_with_timeout(String.t(), String.t(), pos_integer()) ::
          {:ok, Macro.t()} | :error
  def parse_with_timeout(source, file, timeout) do
    task =
      Task.async(fn ->
        Code.string_to_quoted(source, line: 1, columns: true, file: file)
      end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, {:ok, ast}} -> {:ok, ast}
      _ -> :error
    end
  end
end
