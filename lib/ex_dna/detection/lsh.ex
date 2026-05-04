defmodule ExDNA.Detection.LSH do
  @moduledoc """
  Locality-Sensitive Hashing for fast approximate nearest-neighbor search
  on sub-hash sets.

  Computes MinHash signatures and uses banding to find candidate fragment
  pairs with high Jaccard similarity without quadratic pairwise comparison.

  ## How it works

  1. **MinHash** — for each fragment's sub-hash set, compute `k` minimum
     hash values under `k` different hash functions (simulated via seeds).
     The probability that two signatures agree at a position equals their
     exact Jaccard similarity.

  2. **Banding** — split the `k`-length signature into `b` bands of `r`
     rows each. Two fragments become candidates if they match on all rows
     in *any* band. This creates an S-curve acceptance probability:

         P(candidate) = 1 - (1 - J^r)^b

     where J is Jaccard similarity. The inflection point sits at
     approximately `(1/b)^(1/r)`.

  3. **Parameter selection** — `optimal_params/1` picks `(b, r)` so the
     S-curve inflection is near the desired similarity threshold, keeping
     the total hash count between 16 and 64.
  """

  @doc """
  Compute `(num_bands, rows_per_band)` that place the LSH S-curve inflection
  point near `threshold`.

  The inflection point of the banding S-curve is `(1/b)^(1/r)`. We search
  the parameter space for the pair that minimizes distance to the target
  while keeping total hashes in a practical range.
  """
  @spec optimal_params(float()) :: {pos_integer(), pos_integer()}
  def optimal_params(threshold) do
    {_error, b, r} =
      for b <- 2..30,
          r <- 1..8,
          total = b * r,
          total >= 16 and total <= 64,
          inflection = :math.pow(1 / b, 1 / r),
          error = abs(inflection - threshold) do
        {error, b, r}
      end
      |> Enum.min_by(&elem(&1, 0))

    {b, r}
  end

  @doc """
  Compute a MinHash signature for a set of sub-hashes.

  Returns `nil` for empty sets (these fragments cannot participate in
  fuzzy matching).
  """
  @spec signature(MapSet.t(), pos_integer()) :: [non_neg_integer()] | nil
  def signature(sub_hashes, num_hashes) do
    if MapSet.size(sub_hashes) == 0 do
      nil
    else
      hashes = MapSet.to_list(sub_hashes)
      Enum.map(0..(num_hashes - 1), &min_hash(hashes, &1))
    end
  end

  defp min_hash(hashes, seed) do
    Enum.reduce(hashes, :infinity, fn h, min_val ->
      v = :erlang.phash2({h, seed})
      if v < min_val, do: v, else: min_val
    end)
  end

  @doc """
  Find candidate pairs using LSH banding.

  Accepts a list of `{index, signature}` tuples and returns a `MapSet` of
  `{i, j}` pairs (where `i < j`) that collided in at least one band.
  """
  @spec candidate_pairs([{non_neg_integer(), [non_neg_integer()]}], pos_integer(), pos_integer()) ::
          MapSet.t()
  def candidate_pairs(indexed_signatures, num_bands, rows_per_band) do
    Enum.reduce(0..(num_bands - 1), MapSet.new(), fn band, pairs ->
      offset = band * rows_per_band

      indexed_signatures
      |> Enum.group_by(fn {_idx, sig} ->
        :erlang.phash2({band, Enum.slice(sig, offset, rows_per_band)})
      end)
      |> Enum.reduce(pairs, fn {_bucket, members}, pairs ->
        add_pairs_from_bucket(members, pairs)
      end)
    end)
  end

  defp add_pairs_from_bucket(members, pairs) when length(members) < 2, do: pairs

  defp add_pairs_from_bucket(members, pairs) do
    indices = Enum.map(members, &elem(&1, 0))

    for i <- indices, j <- indices, i < j, reduce: pairs do
      acc -> MapSet.put(acc, {i, j})
    end
  end
end
