defmodule ExDNA.Detection.Fuzzy do
  @moduledoc """
  Type-III (near-miss) clone detection.

  Uses an inverted index on structural sub-hashes for candidate-pair
  generation, with MinHash acceleration for large posting lists.

  Each fragment carries a set of lightweight sub-hashes from its child
  subtrees (computed during fingerprinting). The inverted index identifies
  all pairs sharing at least one sub-hash. Small posting lists use exact
  Jaccard similarity as a pre-filter; large ones (above `@lsh_cutover`)
  switch to an O(k) MinHash estimate, avoiding quadratic blowup without
  the recall loss of a hard posting-list cap.
  """

  alias ExDNA.AST.{EditDistance, Normalizer}
  alias ExDNA.Detection.{Clone, LSH}

  # Minimum approximate Jaccard to proceed to expensive edit distance.
  @jaccard_threshold 0.3
  # Posting lists above this size use MinHash pre-filter instead of exact Jaccard.
  @lsh_cutover 50
  # Number of hashes for the MinHash pre-filter.
  @minhash_size 32

  @doc """
  Find Type-III clones from a list of fragments at the given similarity threshold.
  """
  @type fuzzy_opts :: [mass_tolerance: float(), normalizer_opts: keyword()]

  @spec detect([map()], float(), MapSet.t(), fuzzy_opts()) :: [Clone.t()]
  def detect(fragments, min_similarity, exact_hashes, opts \\ []) do
    mass_tolerance = Keyword.get(opts, :mass_tolerance, 0.3)
    normalizer_opts = Keyword.get(opts, :normalizer_opts, [])

    candidates =
      fragments
      |> Enum.reject(fn f -> MapSet.member?(exact_hashes, f.hash) end)
      |> Enum.sort_by(& &1.mass, :desc)
      |> Enum.with_index()

    by_idx = Map.new(candidates, fn {frag, idx} -> {idx, frag} end)

    inverted = build_inverted_index(candidates)
    sig_cache = build_signature_cache(inverted, by_idx)
    pairs = find_pairs(inverted, by_idx, sig_cache, mass_tolerance)

    needed_indices =
      pairs
      |> Enum.flat_map(fn {i, j} -> [i, j] end)
      |> Enum.uniq()

    norms =
      Map.new(needed_indices, fn idx ->
        {idx, Normalizer.normalize(by_idx[idx].ast, normalizer_opts)}
      end)

    pairs
    |> Enum.flat_map(fn {i, j} ->
      sim = EditDistance.similarity(norms[i], norms[j])
      if sim >= min_similarity, do: [{i, j, sim}], else: []
    end)
    |> group_pairs(by_idx)
  end

  defp build_inverted_index(indexed) do
    Enum.reduce(indexed, %{}, fn {frag, idx}, acc ->
      Enum.reduce(frag.sub_hashes, acc, fn h, a ->
        Map.update(a, h, [idx], &[idx | &1])
      end)
    end)
  end

  defp build_signature_cache(inverted, by_idx) do
    inverted
    |> Map.values()
    |> Enum.filter(&(length(&1) > @lsh_cutover))
    |> List.flatten()
    |> MapSet.new()
    |> Map.new(fn idx ->
      {idx, LSH.signature(by_idx[idx].sub_hashes, @minhash_size)}
    end)
  end

  defp find_pairs(inverted, by_idx, sig_cache, mass_tolerance) do
    Enum.reduce(inverted, MapSet.new(), fn {_hash, indices}, pairs ->
      pairs_from_posting(indices, pairs, by_idx, sig_cache, mass_tolerance)
    end)
    |> MapSet.to_list()
  end

  defp pairs_from_posting(indices, pairs, by_idx, sig_cache, mass_tolerance) do
    if length(indices) > @lsh_cutover do
      {num_bands, rows_per_band} = LSH.optimal_params(@jaccard_threshold)

      indices
      |> Enum.filter(&sig_cache[&1])
      |> Enum.map(&{&1, sig_cache[&1]})
      |> LSH.candidate_pairs(num_bands, rows_per_band)
      |> add_compatible_pairs(pairs, by_idx, mass_tolerance)
    else
      for i <- indices,
          j <- indices,
          i < j,
          mass_compatible?(by_idx[i], by_idx[j], mass_tolerance),
          not same_location?(by_idx[i], by_idx[j]),
          jaccard_compatible?(by_idx[i], by_idx[j]),
          reduce: pairs do
        acc -> MapSet.put(acc, {i, j})
      end
    end
  end

  defp add_compatible_pairs(candidate_pairs, pairs, by_idx, mass_tolerance) do
    Enum.reduce(candidate_pairs, pairs, fn {i, j}, acc ->
      maybe_add_pair(acc, i, j, by_idx, mass_tolerance)
    end)
  end

  defp maybe_add_pair(pairs, i, j, by_idx, mass_tolerance) do
    if mass_compatible?(by_idx[i], by_idx[j], mass_tolerance) and
         not same_location?(by_idx[i], by_idx[j]) do
      MapSet.put(pairs, {i, j})
    else
      pairs
    end
  end

  defp jaccard_compatible?(a, b) do
    sa = a.sub_hashes
    sb = b.sub_hashes

    if MapSet.size(sa) == 0 or MapSet.size(sb) == 0 do
      false
    else
      intersection = MapSet.intersection(sa, sb) |> MapSet.size()
      union = MapSet.union(sa, sb) |> MapSet.size()
      intersection / union >= @jaccard_threshold
    end
  end

  defp mass_compatible?(a, b, mass_tolerance) do
    ratio = min(a.mass, b.mass) / max(a.mass, b.mass)
    ratio >= 1.0 - mass_tolerance
  end

  defp same_location?(a, b) do
    a.file == b.file and a.line == b.line
  end

  defp group_pairs([], _by_idx), do: []

  defp group_pairs(pairs, by_idx) do
    adjacency = adjacency(pairs)

    adjacency
    |> Map.keys()
    |> connected_components(adjacency)
    |> Enum.map(&component_to_clone(&1, pairs, by_idx))
  end

  @spec adjacency([{non_neg_integer(), non_neg_integer(), float()}]) :: %{
          non_neg_integer() => [non_neg_integer()]
        }
  defp adjacency(pairs) do
    Enum.reduce(pairs, %{}, fn {i, j, _sim}, acc ->
      acc
      |> Map.update(i, [j], &[j | &1])
      |> Map.update(j, [i], &[i | &1])
    end)
  end

  @spec connected_components([non_neg_integer()], %{non_neg_integer() => [non_neg_integer()]}) ::
          [
            [non_neg_integer()]
          ]
  defp connected_components(indices, adjacency) do
    {_seen, components} =
      Enum.reduce(indices, {%{}, []}, fn idx, {seen, components} ->
        if Map.has_key?(seen, idx) do
          {seen, components}
        else
          component = collect_component([idx], adjacency, %{})
          {Map.merge(seen, component), [Map.keys(component) | components]}
        end
      end)

    Enum.reverse(components)
  end

  @spec collect_component([non_neg_integer()], %{non_neg_integer() => [non_neg_integer()]}, %{
          non_neg_integer() => true
        }) :: %{non_neg_integer() => true}
  defp collect_component([], _adjacency, seen), do: seen

  defp collect_component([idx | rest], adjacency, seen) do
    if Map.has_key?(seen, idx) do
      collect_component(rest, adjacency, seen)
    else
      neighbours = Map.get(adjacency, idx, [])
      collect_component(neighbours ++ rest, adjacency, Map.put(seen, idx, true))
    end
  end

  @spec component_to_clone(
          [non_neg_integer()],
          [{non_neg_integer(), non_neg_integer(), float()}],
          %{
            non_neg_integer() => map()
          }
        ) :: Clone.t()
  defp component_to_clone(component, pairs, by_idx) do
    component_set = MapSet.new(component)

    similarity =
      pairs
      |> Enum.filter(fn {i, j, _sim} ->
        MapSet.member?(component_set, i) and MapSet.member?(component_set, j)
      end)
      |> Enum.map(fn {_i, _j, sim} -> sim end)
      |> Enum.min()

    fragments =
      component
      |> Enum.map(&by_idx[&1])
      |> Enum.sort_by(& &1.mass, :desc)
      |> Enum.uniq_by(&{&1.file, &1.line})
      |> Enum.sort_by(&{&1.file, &1.line, &1.mass})

    %Clone{
      type: :type_iii,
      hash: nil,
      mass: fragments |> Enum.map(& &1.mass) |> Enum.max(),
      fragments:
        Enum.map(fragments, fn frag ->
          %{file: frag.file, line: frag.line, ast: frag.ast, mass: frag.mass}
        end),
      suggestion: nil,
      similarity: similarity
    }
  end
end
