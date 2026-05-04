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
  @type fuzzy_opts :: [mass_tolerance: float()]

  @spec detect([map()], float(), MapSet.t(), fuzzy_opts()) :: [Clone.t()]
  def detect(fragments, min_similarity, exact_hashes, opts \\ []) do
    mass_tolerance = Keyword.get(opts, :mass_tolerance, 0.3)

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

    norms = Map.new(needed_indices, fn idx -> {idx, Normalizer.normalize(by_idx[idx].ast)} end)

    pairs
    |> Enum.flat_map(fn {i, j} ->
      sim = EditDistance.similarity(norms[i], norms[j])
      if sim >= min_similarity, do: [{by_idx[i], by_idx[j], sim}], else: []
    end)
    |> deduplicate_pairs()
    |> Enum.map(&pair_to_clone/1)
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
      for i <- indices,
          j <- indices,
          i < j,
          mass_compatible?(by_idx[i], by_idx[j], mass_tolerance),
          not same_location?(by_idx[i], by_idx[j]),
          minhash_compatible?(sig_cache[i], sig_cache[j]),
          reduce: pairs do
        acc -> MapSet.put(acc, {i, j})
      end
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

  defp minhash_compatible?(nil, _), do: false
  defp minhash_compatible?(_, nil), do: false

  defp minhash_compatible?(sig_a, sig_b) do
    matching = count_matching(sig_a, sig_b, 0)
    matching / @minhash_size >= @jaccard_threshold
  end

  defp count_matching([], [], acc), do: acc
  defp count_matching([h | ta], [h | tb], acc), do: count_matching(ta, tb, acc + 1)
  defp count_matching([_ | ta], [_ | tb], acc), do: count_matching(ta, tb, acc)

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

  defp deduplicate_pairs(pairs) do
    pairs
    |> Enum.sort_by(fn {_, _, sim} -> sim end, :desc)
    |> Enum.reduce({[], MapSet.new()}, fn {a, b, sim}, {acc, seen} ->
      key_a = {a.file, a.line}
      key_b = {b.file, b.line}

      if MapSet.member?(seen, key_a) or MapSet.member?(seen, key_b) do
        {acc, seen}
      else
        seen = seen |> MapSet.put(key_a) |> MapSet.put(key_b)
        {[{a, b, sim} | acc], seen}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp pair_to_clone({frag_a, frag_b, similarity}) do
    mass = max(frag_a.mass, frag_b.mass)

    %Clone{
      type: :type_iii,
      hash: nil,
      mass: mass,
      fragments: [
        %{file: frag_a.file, line: frag_a.line, ast: frag_a.ast, mass: frag_a.mass},
        %{file: frag_b.file, line: frag_b.line, ast: frag_b.ast, mass: frag_b.mass}
      ],
      suggestion: nil,
      similarity: similarity
    }
  end
end
