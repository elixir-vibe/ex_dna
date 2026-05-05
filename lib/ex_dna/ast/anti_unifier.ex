defmodule ExDNA.AST.AntiUnifier do
  @moduledoc """
  Computes the *anti-unification* (most specific generalization) of two ASTs.

  Given two AST fragments, anti-unification finds the largest common structure
  and replaces every position where the trees diverge with a *hole* — a
  generated variable. The result is the pattern that, when the holes are filled
  with the right values, reconstructs either original.

  This directly produces the shape of a function that could replace both
  fragments: the common structure becomes the body, and the holes become
  parameters.

  ## Example

      iex> a = quote do: Enum.map(list, fn x -> x * 2 end)
      iex> b = quote do: Enum.map(items, fn y -> y * 3 end)
      iex> {pattern, holes} = ExDNA.AST.AntiUnifier.anti_unify(a, b)
      iex> length(holes)
      3

  Each hole is `%{var: atom, values: [left_ast, right_ast]}`.
  """

  @type hole :: %{var: atom(), values: [Macro.t()]}
  @type result :: {Macro.t(), [hole()]}

  @doc """
  Compute the anti-unification of two AST fragments.

  Returns `{generalized_ast, holes}` where holes are the positions that differ.
  """
  @spec anti_unify(Macro.t(), Macro.t()) :: result()
  def anti_unify(ast_a, ast_b) do
    {generalized, {_index, holes}} = do_anti_unify(ast_a, ast_b, {0, []})
    {generalized, Enum.reverse(holes)}
  end

  defp do_anti_unify(same, same, state), do: {same, state}

  # Variable nodes: {name, meta, context} where context is an atom.
  # If only the name differs, replace the whole variable with a hole.
  defp do_anti_unify({name_a, _meta_a, ctx_a}, {name_b, _meta_b, ctx_b}, state)
       when is_atom(name_a) and is_atom(name_b) and is_atom(ctx_a) and is_atom(ctx_b) and
              name_a != name_b do
    make_hole({name_a, [], ctx_a}, {name_b, [], ctx_b}, state)
  end

  defp do_anti_unify({:__aliases__, meta_a, parts}, {:__aliases__, meta_b, parts}, state) do
    {{:__aliases__, merge_meta(meta_a, meta_b), parts}, state}
  end

  defp do_anti_unify(
         {:__aliases__, _meta_a, _parts_a} = alias_a,
         {:__aliases__, _meta_b, _parts_b} = alias_b,
         state
       ) do
    make_hole(alias_a, alias_b, state)
  end

  # Call nodes: {form, meta, args} where args is a list
  defp do_anti_unify({form_a, meta_a, args_a}, {form_b, meta_b, args_b}, state)
       when is_list(args_a) and is_list(args_b) do
    if length(args_a) == length(args_b) do
      {form, state} = do_anti_unify(form_a, form_b, state)
      meta = merge_meta(meta_a, meta_b)
      {args, state} = anti_unify_list(args_a, args_b, state)
      {{form, meta, args}, state}
    else
      make_hole({form_a, meta_a, args_a}, {form_b, meta_b, args_b}, state)
    end
  end

  defp do_anti_unify({la, ra}, {lb, rb}, state) do
    {left, state} = do_anti_unify(la, lb, state)
    {right, state} = do_anti_unify(ra, rb, state)
    {{left, right}, state}
  end

  defp do_anti_unify(list_a, list_b, state)
       when is_list(list_a) and is_list(list_b) do
    if length(list_a) == length(list_b) do
      anti_unify_list(list_a, list_b, state)
    else
      make_hole(list_a, list_b, state)
    end
  end

  defp do_anti_unify(a, b, state), do: make_hole(a, b, state)

  defp make_hole(a, b, {index, holes}) do
    var_name = :"hole#{index}"
    hole = %{var: var_name, values: [a, b]}
    node = {var_name, [], nil}
    {node, {index + 1, [hole | holes]}}
  end

  defp anti_unify_list(list_a, list_b, state) do
    {reversed, state} =
      list_a
      |> Enum.zip(list_b)
      |> Enum.reduce({[], state}, fn {a, b}, {acc, st} ->
        {node, st} = do_anti_unify(a, b, st)
        {[node | acc], st}
      end)

    {Enum.reverse(reversed), state}
  end

  defp merge_meta(meta_a, meta_b) do
    line_a = Keyword.get(meta_a, :line)
    line_b = Keyword.get(meta_b, :line)

    if line_a && line_a == line_b do
      [line: line_a]
    else
      []
    end
  end
end
