defmodule ExDNA.AST.Fingerprint do
  @moduledoc """
  Computes structural fingerprints (hashes) for AST subtrees.

  Every subtree whose *mass* (node count) meets the threshold is hashed.
  Two normalized ASTs with the same hash are structurally identical clones.

  Each fragment also carries a set of lightweight sub-hashes from its child
  subtrees, computed during the same walk, for efficient Jaccard-based
  fuzzy candidate pruning in `ExDNA.Detection.Fuzzy`.

  Sliding windows over sibling sequences in module bodies are fingerprinted
  to catch clones that span multiple adjacent statements.
  """

  alias ExDNA.AST.{Location, Normalizer}

  @type hash :: binary()
  @type fragment :: %{
          hash: hash(),
          mass: pos_integer(),
          ast: Macro.t(),
          file: String.t(),
          line: pos_integer(),
          sub_hashes: MapSet.t(integer())
        }

  # Minimum AST mass for a sub-node to contribute a sub-hash.
  # Nodes below this (single calls, variables) are too common to discriminate.
  @sub_hash_min_mass 5
  @module_level_forms [:def, :defp, :defmacro, :defmacrop]

  @doc """
  Walk an AST and return all subtree fragments that meet `min_mass`.
  """
  @spec fragments(Macro.t(), String.t(), pos_integer(), keyword()) :: [fragment()]
  def fragments(ast, file, min_mass, opts \\ []) do
    ctx = %{
      file: file,
      min_mass: min_mass,
      norm_opts: Keyword.take(opts, [:literal_mode, :normalize_pipes, :normalize_variables]),
      excluded: Keyword.get(opts, :excluded_macros, []) |> MapSet.new(),
      ignored_attrs: Keyword.get(opts, :ignored_attributes, []) |> MapSet.new(),
      max_window_size: Keyword.get(opts, :max_window_size, 4),
      max_module_forms: Keyword.get(opts, :max_module_forms, 200)
    }

    {_ast, frags, _sub_hashes} = walk(ast, ctx, [])
    frags
  end

  # __block__ — walk children, track per-child sub-hashes for window construction
  defp walk({:__block__, _meta, args} = node, ctx, acc) when is_list(args) do
    {acc, per_child_subs, all_subs} =
      Enum.reduce(args, {acc, [], MapSet.new()}, fn child, {a, per_child, all} ->
        {_, a, child_s} = walk(child, ctx, a)
        {a, [child_s | per_child], MapSet.union(all, child_s)}
      end)

    per_child_subs = Enum.reverse(per_child_subs)

    acc =
      if module_body?(args, ctx) do
        sibling_windows(args, per_child_subs, ctx, acc)
      else
        acc
      end

    {node, acc, all_subs}
  end

  # Module attribute (@attr value) — skip ignored attributes, fingerprint the rest
  defp walk({:@, _meta, [{attr_name, _, _}]} = node, ctx, acc) when is_atom(attr_name) do
    if MapSet.member?(ctx.ignored_attrs, attr_name) do
      {node, acc, MapSet.new()}
    else
      do_walk_call(node, ctx, acc)
    end
  end

  # Regular call nodes — walk children, fingerprint if large enough
  defp walk({form, _meta, args} = node, ctx, acc) when is_list(args) do
    if excluded_macro?(form, ctx.excluded) do
      {node, acc, MapSet.new()}
    else
      do_walk_call(node, ctx, acc)
    end
  end

  defp walk({left, right}, ctx, acc) do
    {_, acc, subs_l} = walk(left, ctx, acc)
    {_, acc, subs_r} = walk(right, ctx, acc)
    {{left, right}, acc, MapSet.union(subs_l, subs_r)}
  end

  defp walk(list, ctx, acc) when is_list(list) do
    {acc, subs} = walk_children(list, ctx, acc)
    {list, acc, subs}
  end

  defp walk(leaf, _ctx, acc), do: {leaf, acc, MapSet.new()}

  defp do_walk_call({form, _meta, args} = node, ctx, acc) do
    {acc, child_subs} = walk_children(args, ctx, acc)

    mass = mass(node)

    my_sub_hash =
      if mass >= @sub_hash_min_mass do
        child_forms = Enum.map(args, &child_form/1)
        MapSet.new([:erlang.phash2({form, child_forms, mass})])
      else
        MapSet.new()
      end

    all_subs = MapSet.union(child_subs, my_sub_hash)

    if mass >= ctx.min_mass do
      normalized = Normalizer.normalize(node, ctx.norm_opts)
      hash = compute_hash(normalized)
      line = Location.start_line(node)

      frag = %{
        hash: hash,
        mass: mass,
        ast: node,
        file: ctx.file,
        line: line,
        sub_hashes: all_subs
      }

      {node, [frag | acc], all_subs}
    else
      {node, acc, all_subs}
    end
  end

  defp walk_children(children, ctx, acc) do
    Enum.reduce(children, {acc, MapSet.new()}, fn child, {a, subs} ->
      {_, a, child_s} = walk(child, ctx, a)
      {a, MapSet.union(subs, child_s)}
    end)
  end

  # --- Sibling windows ---

  defp module_body?(children, ctx) do
    length(children) <= ctx.max_module_forms and
      Enum.any?(children, fn
        {form, _, _} when form in @module_level_forms -> true
        _ -> false
      end)
  end

  defp sibling_windows([], _per_child_subs, _ctx, acc), do: acc
  defp sibling_windows([_], _per_child_subs, _ctx, acc), do: acc

  defp sibling_windows(children, per_child_subs, ctx, acc) do
    children_with_subs =
      children
      |> Enum.zip(per_child_subs)
      |> Enum.reject(fn
        {{:@, _, [{attr_name, _, _}]}, _} when is_atom(attr_name) ->
          MapSet.member?(ctx.ignored_attrs, attr_name)

        {{form, _, _}, _} ->
          excluded_macro?(form, ctx.excluded)

        _ ->
          false
      end)

    len = length(children_with_subs)
    max_win = min(ctx.max_window_size, len)

    Enum.reduce(2..max_win//1, acc, fn window_size, acc_outer ->
      children_with_subs
      |> Enum.chunk_every(window_size, 1, :discard)
      |> Enum.reduce(acc_outer, fn window_with_subs, acc_inner ->
        {window, subs_list} = Enum.unzip(window_with_subs)
        window_subs = Enum.reduce(subs_list, MapSet.new(), &MapSet.union/2)
        maybe_window_fragment(window, window_subs, ctx, acc_inner)
      end)
    end)
  end

  defp maybe_window_fragment(window, window_subs, ctx, acc) do
    combined_mass = Enum.sum(Enum.map(window, &mass/1))

    if combined_mass < ctx.min_mass do
      acc
    else
      synthetic = {:__block__, [], window}
      normalized = Normalizer.normalize(synthetic, ctx.norm_opts)
      hash = compute_hash(normalized)

      frag = %{
        hash: hash,
        mass: combined_mass,
        ast: synthetic,
        file: ctx.file,
        line: Location.start_line(synthetic),
        sub_hashes: window_subs
      }

      [frag | acc]
    end
  end

  # --- Helpers ---

  defp child_form({form, _, _}) when is_atom(form), do: form
  defp child_form({form, _, _}) when is_tuple(form), do: :remote_call
  defp child_form(_), do: :leaf

  defp excluded_macro?(form, excluded) when is_atom(form), do: MapSet.member?(excluded, form)
  defp excluded_macro?(_, _), do: false

  @doc """
  Count the number of AST nodes in a tree (its "mass").
  """
  @spec mass(Macro.t()) :: non_neg_integer()
  def mass({_form, _meta, args}) when is_list(args) do
    1 + Enum.sum(Enum.map(args, &mass/1))
  end

  def mass({left, right}), do: 1 + mass(left) + mass(right)

  def mass(list) when is_list(list) do
    Enum.sum(Enum.map(list, &mass/1))
  end

  def mass(_leaf), do: 1

  @doc """
  Compute a deterministic hash for a normalized AST.
  """
  @spec compute_hash(Macro.t()) :: hash()
  def compute_hash(normalized_ast) do
    normalized_ast
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:blake2b, &1))
  end
end
