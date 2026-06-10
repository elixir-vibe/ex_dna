defmodule ExDNA.AST.Normalizer do
  @moduledoc """
  Normalizes Elixir AST for structural comparison.

  Transforms an AST so that structurally equivalent code produces identical
  output regardless of variable names, metadata, or (optionally) literal values.

  All normalizations are performed in at most two AST traversals:

  **Pass 1** (always, single fused walk):

  1. **Metadata stripping** — removes line numbers, columns, counters, and
     other compiler metadata from every node.
  2. **Boolean operator canonicalization** — `&&`/`||`/`!` are rewritten to
     `and`/`or`/`not` so stylistic choice between short-circuit and keyword
     operators doesn't affect comparison.
  3. **Sigil expansion** — `~w(foo bar)a` is expanded to `[:foo, :bar]` (and
     likewise for string modifiers) so sigil word-lists match their literal
     equivalents.
  4. **Pipe normalization** (optional) — `x |> f()` is rewritten to `f(x)`.
  5. **Variable normalization** — replaces variable names with positional
     placeholders (`:$0`, `:$1`, …) based on first-occurrence order.

  **Pass 2** (abstract mode only, single recursive walk):

  6. **Literal abstraction** — replaces concrete literals with type-tagged
     placeholders to detect Type-II clones.
  7. **Map/struct field sorting** — sorts key-value pairs so that
     `%{b: 1, a: 2}` and `%{a: 2, b: 1}` produce the same hash.
  8. **Guard abstraction** — in `when` clauses, replaces all function/macro
     call names with a `:__guard__` placeholder so that
     `when is_binary(x)` and `when is_atom(x)` produce the same hash.
     Covers all Kernel guards, Erlang BIF guards, `defguard` macros,
     and library guards like `Integer.is_even/1`.
  """

  alias ExDNA.AST.Pipe

  @type option ::
          {:literal_mode, :keep | :abstract}
          | {:normalize_pipes, boolean()}
          | {:normalize_variables, boolean()}

  @doc """
  Normalize an AST fragment.

  ## Options

    * `:literal_mode` — `:keep` preserves literal values (Type-I detection),
      `:abstract` replaces them with placeholders (Type-II detection).
      Defaults to `:keep`.
    * `:normalize_pipes` — when `true`, convert pipe chains to nested calls
      so `x |> f()` matches `f(x)`. Defaults to `false`.
    * `:normalize_variables` — when `true`, replace variable names with
      positional placeholders. Defaults to `true`.
  """
  @spec normalize(Macro.t(), [option()]) :: Macro.t()
  def normalize(ast, opts \\ []) do
    literal_mode = Keyword.get(opts, :literal_mode, :keep)
    normalize_pipes = Keyword.get(opts, :normalize_pipes, false)
    normalize_variables = Keyword.get(opts, :normalize_variables, true)

    {normalized, _env} = fused_walk(ast, normalize_pipes, normalize_variables, %{})

    case literal_mode do
      :keep -> normalized
      :abstract -> abstract_walk(normalized)
    end
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

  # --- Pass 1: fused walk (strip metadata + canonicalize + expand + pipes + rename vars) ---

  @special_vars ~w(__MODULE__ __ENV__ __DIR__ __CALLER__ __STACKTRACE__ _)a
  @bool_canon %{:&& => :and, :|| => :or, :! => :not}

  # Sigil ~w with static content — expand before recursing
  defp fused_walk({:sigil_w, _meta, [{:<<>>, _, [content]}, modifier]}, _pipes, _vars, env)
       when is_binary(content) do
    expanded = expand_sigil_w(content, modifier)
    # Expanded list is all literals, no variables to rename
    {expanded, env}
  end

  # Pipe: flatten then recurse into the result
  defp fused_walk({:|>, _meta, [left, right]}, true = pipes, vars, env) do
    {left_n, env} = fused_walk(left, pipes, vars, env)
    {right_n, env} = fused_walk(right, pipes, vars, env)
    {Pipe.inject_first_arg(right_n, left_n), env}
  end

  # Variable node
  defp fused_walk({name, _meta, context}, _pipes, vars, env)
       when is_atom(name) and is_atom(context) do
    cond do
      name in @special_vars ->
        {{name, [], context}, env}

      not vars ->
        {{name, [], context}, env}

      true ->
        key = {name, context}

        case env do
          %{^key => placeholder} ->
            {{placeholder, [], context}, env}

          _ ->
            index = map_size(env)
            placeholder = :"$#{index}"
            {{placeholder, [], context}, Map.put(env, key, placeholder)}
        end
    end
  end

  # Call node with boolean canonicalization
  defp fused_walk({form, _meta, args}, pipes, vars, env) when is_list(args) do
    canonical_form = Map.get(@bool_canon, form, form)
    {form_n, env} = fused_walk(canonical_form, pipes, vars, env)
    {args_n, env} = fused_walk_list(args, pipes, vars, env)
    {{form_n, [], args_n}, env}
  end

  # Two-tuple (keyword pair, etc.)
  defp fused_walk({left, right}, pipes, vars, env) do
    {left_n, env} = fused_walk(left, pipes, vars, env)
    {right_n, env} = fused_walk(right, pipes, vars, env)
    {{left_n, right_n}, env}
  end

  # List
  defp fused_walk(list, pipes, vars, env) when is_list(list) do
    fused_walk_list(list, pipes, vars, env)
  end

  # Leaf (literal or atom) — pass through
  defp fused_walk(leaf, _pipes, _vars, env), do: {leaf, env}

  defp fused_walk_list(list, pipes, vars, env) do
    {reversed, env} =
      Enum.reduce(list, {[], env}, fn node, {acc, env} ->
        {n, env} = fused_walk(node, pipes, vars, env)
        {[n | acc], env}
      end)

    {Enum.reverse(reversed), env}
  end

  # --- Sigil expansion ---

  defp expand_sigil_w(content, modifier) do
    words = String.split(content)

    case modifier do
      ~c"a" -> Enum.map(words, &String.to_atom/1)
      ~c"c" -> Enum.map(words, &String.to_charlist/1)
      _ -> words
    end
  end

  # --- Pass 2: abstract walk (literal abstraction + map sorting + guard abstraction) ---

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
    if Enum.all?(fields, &match?({_, _}, &1)) do
      fields
      |> Enum.map(fn {k, v} -> {k, abstract_walk(v)} end)
      |> Enum.sort_by(fn {k, _v} -> k end)
    else
      Enum.map(fields, &abstract_walk/1)
    end
  end

  # --- Legacy public API kept for rename_var/2 usage in tests ---

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
end
