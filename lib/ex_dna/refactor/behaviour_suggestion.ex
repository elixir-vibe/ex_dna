defmodule ExDNA.Refactor.BehaviourSuggestion do
  @moduledoc """
  Detects clone groups where the same function is implemented identically
  across multiple modules, suggesting a behaviour extraction.

  A behaviour is suggested when 2+ clones have fragments from different
  modules, and each fragment is a `def` with the same function name and arity.
  """

  alias ExDNA.Detection.Clone

  @type t :: %__MODULE__{
          callback_name: atom(),
          callback_arity: non_neg_integer(),
          modules: [String.t()]
        }

  defstruct [:callback_name, :callback_arity, modules: []]

  @doc """
  Analyze a list of clones and attach behaviour suggestions where appropriate.

  Accepts an optional map of `%{file_path => ast}` to resolve module names
  without re-reading files from disk.
  """
  @spec analyze([Clone.t()], %{String.t() => Macro.t()}) :: [Clone.t()]
  def analyze(clones, file_asts \\ %{}) do
    Enum.map(clones, fn clone ->
      case suggest(clone, file_asts) do
        nil -> clone
        suggestion -> %{clone | behaviour_suggestion: suggestion}
      end
    end)
  end

  @doc """
  Generate a behaviour suggestion for a single clone, or nil.
  """
  @spec suggest(Clone.t(), %{String.t() => Macro.t()}) :: t() | nil
  def suggest(clone, file_asts \\ %{})

  def suggest(%Clone{fragments: []}, _file_asts), do: nil
  def suggest(%Clone{fragments: [_]}, _file_asts), do: nil

  def suggest(%Clone{fragments: frags}, file_asts) do
    with true <- all_defs?(frags),
         {name, arity} <- shared_name_arity(frags),
         [_, _ | _] = modules <- distinct_modules(frags, file_asts) do
      %__MODULE__{
        callback_name: name,
        callback_arity: arity,
        modules: modules
      }
    else
      _ -> nil
    end
  end

  defp all_defs?(frags) do
    Enum.all?(frags, fn frag ->
      match?({:def, _, _}, frag.ast)
    end)
  end

  defp shared_name_arity(frags) do
    name_arities =
      frags
      |> Enum.map(&extract_name_arity/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    case name_arities do
      [{name, arity}] -> {name, arity}
      _ -> nil
    end
  end

  defp extract_name_arity(%{ast: {kind, _, [{name, _, args} | _]}})
       when kind in [:def, :defp] and is_atom(name) do
    arity = if is_list(args), do: length(args), else: 0
    {name, arity}
  end

  defp extract_name_arity(_), do: nil

  defp distinct_modules(frags, file_asts) do
    frags
    |> Enum.map(fn frag -> module_for_fragment(frag.file, frag.line, file_asts) end)
    |> Enum.uniq()
  end

  defp module_for_fragment(file, line, file_asts) do
    ast =
      case Map.fetch(file_asts, file) do
        {:ok, ast} -> ast
        :error -> read_and_parse(file)
      end

    case ast do
      nil -> fallback_module_name(file)
      ast -> find_enclosing_module(ast, line) || fallback_module_name(file)
    end
  end

  defp read_and_parse(file) do
    with {:ok, source} <- File.read(file),
         {:ok, ast} <- Code.string_to_quoted(source, line: 1, columns: true, file: file) do
      ast
    else
      _ -> nil
    end
  end

  @doc false
  @spec find_enclosing_module(Macro.t(), pos_integer()) :: String.t() | nil
  def find_enclosing_module(ast, target_line) do
    ast
    |> collect_module_ranges([], [])
    |> Enum.filter(fn {_name, start_line, end_line} ->
      target_line >= start_line and target_line <= end_line
    end)
    |> Enum.max_by(fn {_name, start_line, _end_line} -> start_line end, fn -> nil end)
    |> case do
      {name, _, _} -> name
      nil -> nil
    end
  end

  defp collect_module_ranges(
         {:defmodule, meta, [{:__aliases__, _, parts} | rest]},
         parent_parts,
         acc
       ) do
    start_line = Keyword.get(meta, :line, 0)
    full_parts = parent_parts ++ parts
    name = Enum.map_join(full_parts, ".", &Atom.to_string/1)

    end_line = max_line_in(rest, start_line)

    acc = [{name, start_line, end_line} | acc]

    body = extract_body(rest)
    collect_children(body, full_parts, acc)
  end

  defp collect_module_ranges({_form, _meta, args}, parent, acc) when is_list(args) do
    collect_children(args, parent, acc)
  end

  defp collect_module_ranges(list, parent, acc) when is_list(list) do
    collect_children(list, parent, acc)
  end

  defp collect_module_ranges(_leaf, _parent, acc), do: acc

  defp collect_children(children, parent, acc) when is_list(children) do
    Enum.reduce(children, acc, fn child, a -> collect_module_ranges(child, parent, a) end)
  end

  defp collect_children(child, parent, acc), do: collect_module_ranges(child, parent, acc)

  defp extract_body([[do: {:__block__, _, body}]]), do: body
  defp extract_body([[do: body]]), do: [body]
  defp extract_body(_), do: []

  defp max_line_in(node, default) do
    {_, max} = do_max_line(node, default)
    max
  end

  defp do_max_line({_form, meta, args}, max) when is_list(args) do
    line = Keyword.get(meta, :line, 0)
    max = max(line, max)
    Enum.reduce(args, {nil, max}, fn child, {_, m} -> do_max_line(child, m) end)
  end

  defp do_max_line({_form, meta, ctx}, max) when is_atom(ctx) do
    line = Keyword.get(meta, :line, 0)
    {nil, max(line, max)}
  end

  defp do_max_line({left, right}, max) do
    {_, max} = do_max_line(left, max)
    do_max_line(right, max)
  end

  defp do_max_line(list, max) when is_list(list) do
    Enum.reduce(list, {nil, max}, fn item, {_, m} -> do_max_line(item, m) end)
  end

  defp do_max_line(_leaf, max), do: {nil, max}

  defp fallback_module_name(path) do
    path
    |> Path.basename(".ex")
    |> Macro.camelize()
  end
end
