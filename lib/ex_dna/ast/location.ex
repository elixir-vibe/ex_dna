defmodule ExDNA.AST.Location do
  @moduledoc false

  @type line_range :: {pos_integer() | nil, pos_integer() | nil}

  @doc """
  Return the minimum and maximum source line found in an AST fragment.
  """
  @spec line_range(Macro.t()) :: line_range()
  def line_range(ast) do
    do_line_range(ast, {nil, nil})
  end

  @doc """
  Return the first source line in an AST fragment, or `fallback` if none exists.
  """
  @spec start_line(Macro.t(), non_neg_integer()) :: non_neg_integer()
  def start_line(ast, fallback \\ 0) do
    case line_range(ast) do
      {line, _} when is_integer(line) -> line
      _ -> fallback
    end
  end

  defp do_line_range({_form, meta, args}, acc) when is_list(meta) and is_list(args) do
    acc
    |> update_range(Keyword.get(meta, :line))
    |> then(fn range -> Enum.reduce(args, range, &do_line_range/2) end)
  end

  defp do_line_range({_form, meta, context}, acc) when is_list(meta) and is_atom(context) do
    update_range(acc, Keyword.get(meta, :line))
  end

  defp do_line_range({left, right}, acc) do
    acc = do_line_range(left, acc)
    do_line_range(right, acc)
  end

  defp do_line_range(list, acc) when is_list(list) do
    Enum.reduce(list, acc, &do_line_range/2)
  end

  defp do_line_range(_leaf, acc), do: acc

  defp update_range(range, nil), do: range
  defp update_range({nil, nil}, line) when is_integer(line), do: {line, line}

  defp update_range({min_line, max_line}, line) when is_integer(line) do
    {min(line, min_line), max(line, max_line)}
  end
end
