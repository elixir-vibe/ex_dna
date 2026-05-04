defmodule ExDNA.AST.Normalizer do
  @moduledoc """
  Normalizes Elixir AST for structural comparison.

  Transforms an AST so that structurally equivalent code produces identical
  output regardless of variable names, metadata, or (optionally) literal values.

  ## Normalization passes

  1. **Metadata stripping** — removes line numbers, columns, counters, and
     other compiler metadata from every node.
  2. **Variable normalization** — replaces variable names with positional
     placeholders (`:$0`, `:$1`, …) based on first-occurrence order.
  3. **Literal abstraction** (optional) — replaces concrete literals with
     type-tagged placeholders to detect Type-II clones.
  4. **Map/struct field sorting** (abstract mode) — sorts key-value pairs
     so that `%{b: 1, a: 2}` and `%{a: 2, b: 1}` produce the same hash.
  5. **Guard abstraction** (abstract mode) — replaces guard type-check
     function names (`is_binary`, `is_atom`, …) with a `:__guard__`
     placeholder so that `when is_binary(x)` and `when is_atom(x)` produce
     the same hash.
  """

  alias ExDNA.AST.PipeNormalizer

  @type option :: {:literal_mode, :keep | :abstract} | {:normalize_pipes, boolean()}

  @doc """
  Normalize an AST fragment.

  ## Options

    * `:literal_mode` — `:keep` preserves literal values (Type-I detection),
      `:abstract` replaces them with placeholders (Type-II detection).
      Defaults to `:keep`.
    * `:normalize_pipes` — when `true`, convert pipe chains to nested calls
      so `x |> f()` matches `f(x)`. Defaults to `false`.
  """
  @spec normalize(Macro.t(), [option()]) :: Macro.t()
  def normalize(ast, opts \\ []) do
    literal_mode = Keyword.get(opts, :literal_mode, :keep)
    normalize_pipes = Keyword.get(opts, :normalize_pipes, false)

    ast
    |> strip_metadata()
    |> maybe_normalize_pipes(normalize_pipes)
    |> normalize_variables()
    |> maybe_abstract_literals(literal_mode)
  end

  @doc """
  Remove all metadata from every AST node, keeping only structural shape.
  """
  @spec strip_metadata(Macro.t()) :: Macro.t()
  def strip_metadata(ast) do
    Macro.prewalk(ast, fn
      {form, _meta, args} when is_list(args) -> {form, [], args}
      {form, _meta, atom} when is_atom(atom) -> {form, [], atom}
      other -> other
    end)
  end

  @doc """
  Replace all variable names with positional placeholders based on binding order.

  `foo + bar` and `x + y` both become `:"$0" + :"$1"`.
  """
  @spec normalize_variables(Macro.t()) :: Macro.t()
  def normalize_variables(ast) do
    {normalized, _env} = Macro.prewalk(ast, %{}, &rename_var/2)
    normalized
  end

  @special_vars ~w(__MODULE__ __ENV__ __DIR__ __CALLER__ __STACKTRACE__ _)a

  defp rename_var({name, meta, context}, env) when is_atom(name) and is_atom(context) do
    if name in @special_vars do
      {{name, meta, context}, env}
    else
      key = {name, context}

      case env do
        %{^key => placeholder} ->
          {{placeholder, meta, context}, env}

        _ ->
          index = map_size(env)
          placeholder = :"$#{index}"
          {{placeholder, meta, context}, Map.put(env, key, placeholder)}
      end
    end
  end

  defp rename_var(node, env), do: {node, env}

  defp maybe_normalize_pipes(ast, false), do: ast
  defp maybe_normalize_pipes(ast, true), do: PipeNormalizer.normalize(ast)

  defp maybe_abstract_literals(ast, :keep), do: ast
  defp maybe_abstract_literals(ast, :abstract), do: abstract_walk(ast)

  @guard_functions ~w(
    is_atom is_binary is_bitstring is_boolean is_float is_function
    is_integer is_list is_map is_map_key is_nil is_number is_pid
    is_port is_reference is_tuple is_struct is_exception
  )a

  defp abstract_walk({guard_fn, meta, args})
       when guard_fn in @guard_functions and is_list(args) do
    {:__guard__, meta, Enum.map(args, &abstract_walk/1)}
  end

  defp abstract_walk({:%, meta, [struct_name, {:%{}, map_meta, fields}]})
       when is_list(fields) do
    walked = walk_map_fields(fields)
    {:%, meta, [abstract_walk(struct_name), {:%{}, map_meta, walked}]}
  end

  defp abstract_walk({:%{}, meta, fields}) when is_list(fields) do
    {:%{}, meta, walk_map_fields(fields)}
  end

  defp abstract_walk({form, meta, args}) when is_list(args) do
    {abstract_walk(form), meta, Enum.map(args, &abstract_walk/1)}
  end

  defp abstract_walk({form, meta, context}) when is_atom(context) do
    {abstract_walk(form), meta, context}
  end

  defp abstract_walk({left, right}) do
    {abstract_walk(left), abstract_walk(right)}
  end

  defp abstract_walk(list) when is_list(list) do
    Enum.map(list, &abstract_walk/1)
  end

  defp abstract_walk(int) when is_integer(int), do: :__integer__
  defp abstract_walk(float) when is_float(float), do: :__float__
  defp abstract_walk(str) when is_binary(str), do: :__string__
  defp abstract_walk(atom) when is_atom(atom), do: atom

  defp walk_map_fields(fields) do
    if all_kv_pairs?(fields) do
      fields
      |> Enum.map(fn {k, v} -> {k, abstract_walk(v)} end)
      |> Enum.sort_by(fn {k, _v} -> k end)
    else
      Enum.map(fields, &abstract_walk/1)
    end
  end

  defp all_kv_pairs?(fields) do
    Enum.all?(fields, fn
      {_k, _v} -> true
      _ -> false
    end)
  end
end
