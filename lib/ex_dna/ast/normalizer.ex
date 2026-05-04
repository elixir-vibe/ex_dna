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
  5. **Guard abstraction** (abstract mode) — in `when` clauses, replaces
     all function/macro call names with a `:__guard__` placeholder so that
     `when is_binary(x)` and `when is_atom(x)` produce the same hash.
     Covers all Kernel guards, Erlang BIF guards, `defguard` macros,
     and library guards like `Integer.is_even/1`.
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

  defp abstract_walk({:when, meta, [pattern, guard]}) do
    {:when, meta, [abstract_walk(pattern), abstract_guard(guard)]}
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

  # Guard-position abstraction: replaces all call names with :__guard__
  # so that guards differing only in predicate (`is_binary` vs `is_atom`,
  # `Integer.is_even` vs `Integer.is_odd`, custom defguards, etc.) hash
  # identically.
  defp abstract_guard({:and, meta, [left, right]}) do
    {:and, meta, [abstract_guard(left), abstract_guard(right)]}
  end

  defp abstract_guard({:or, meta, [left, right]}) do
    {:or, meta, [abstract_guard(left), abstract_guard(right)]}
  end

  defp abstract_guard({:not, meta, [arg]}) do
    {:not, meta, [abstract_guard(arg)]}
  end

  defp abstract_guard({:when, meta, [left, right]}) do
    {:when, meta, [abstract_guard(left), abstract_guard(right)]}
  end

  defp abstract_guard({{:., meta, [mod, _fun]}, call_meta, args}) do
    {{:., meta, [abstract_walk(mod), :__guard__]}, call_meta, Enum.map(args, &abstract_walk/1)}
  end

  defp abstract_guard({name, meta, args}) when is_atom(name) and is_list(args) do
    {:__guard__, meta, Enum.map(args, &abstract_walk/1)}
  end

  defp abstract_guard(other), do: abstract_walk(other)

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
