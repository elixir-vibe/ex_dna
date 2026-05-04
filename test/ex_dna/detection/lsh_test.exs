defmodule ExDNA.Detection.LSHTest do
  use ExUnit.Case, async: true

  alias ExDNA.Detection.LSH

  describe "optimal_params/1" do
    test "returns params with inflection near the target" do
      for target <- [0.3, 0.5, 0.7, 0.85] do
        {b, r} = LSH.optimal_params(target)
        inflection = :math.pow(1 / b, 1 / r)
        assert_in_delta inflection, target, 0.05, "target=#{target}, got b=#{b}, r=#{r}"
      end
    end

    test "total hashes are in practical range" do
      for target <- [0.3, 0.5, 0.7, 0.85] do
        {b, r} = LSH.optimal_params(target)
        total = b * r
        assert total >= 16 and total <= 64
      end
    end
  end

  describe "signature/2" do
    test "returns nil for empty sets" do
      assert LSH.signature(MapSet.new(), 10) == nil
    end

    test "returns a list of the requested length" do
      set = MapSet.new([1, 2, 3, 4, 5])
      sig = LSH.signature(set, 20)
      assert length(sig) == 20
    end

    test "identical sets produce identical signatures" do
      set = MapSet.new([10, 20, 30])
      assert LSH.signature(set, 16) == LSH.signature(set, 16)
    end

    test "similar sets produce similar signatures" do
      set_a = MapSet.new(1..10)
      set_b = MapSet.new(1..8 |> Enum.to_list() |> Kernel.++([11, 12]))

      sig_a = LSH.signature(set_a, 100)
      sig_b = LSH.signature(set_b, 100)

      matching = Enum.zip(sig_a, sig_b) |> Enum.count(fn {a, b} -> a == b end)
      estimated_jaccard = matching / 100

      exact_jaccard =
        MapSet.intersection(set_a, set_b)
        |> MapSet.size()
        |> Kernel./(MapSet.union(set_a, set_b) |> MapSet.size())

      assert_in_delta estimated_jaccard, exact_jaccard, 0.15
    end
  end

  describe "candidate_pairs/3" do
    test "finds pairs with identical signatures" do
      sig = [1, 2, 3, 4]
      pairs = LSH.candidate_pairs([{0, sig}, {1, sig}], 2, 2)
      assert MapSet.member?(pairs, {0, 1})
    end

    test "does not pair completely different signatures" do
      sig_a = [1, 2, 3, 4, 5, 6]
      sig_b = [7, 8, 9, 10, 11, 12]
      pairs = LSH.candidate_pairs([{0, sig_a}, {1, sig_b}], 3, 2)
      refute MapSet.member?(pairs, {0, 1})
    end

    test "pairs are always {i, j} with i < j" do
      sig = [1, 2, 3, 4]
      pairs = LSH.candidate_pairs([{0, sig}, {1, sig}, {2, sig}], 2, 2)

      Enum.each(pairs, fn {i, j} ->
        assert i < j
      end)
    end
  end
end
