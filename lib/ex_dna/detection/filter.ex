defmodule ExDNA.Detection.Filter do
  @moduledoc """
  Prunes overlapping and nested clones.

  When a large subtree is a clone, all its sub-subtrees will also match.
  We keep only the largest non-overlapping clone per file location.
  """

  alias ExDNA.AST.Location
  alias ExDNA.Detection.Clone

  @doc """
  Remove clones whose fragment locations are all contained within a larger clone's fragments.
  """
  @spec prune_nested([Clone.t()]) :: [Clone.t()]
  def prune_nested(clones) do
    sorted = Enum.sort_by(clones, & &1.mass, :desc)
    prune_nested(sorted, [])
  end

  defp prune_nested([], acc), do: Enum.reverse(acc)

  defp prune_nested([clone | rest], accepted) do
    if subsumed_by_any?(clone, accepted) do
      prune_nested(rest, accepted)
    else
      prune_nested(rest, [clone | accepted])
    end
  end

  defp subsumed_by_any?(clone, accepted) do
    Enum.any?(accepted, fn larger -> subsumes?(larger, clone) end)
  end

  defp subsumes?(larger, smaller) do
    larger.mass > smaller.mass and
      Enum.all?(smaller.fragments, fn small_frag ->
        Enum.any?(larger.fragments, fn large_frag ->
          large_frag.file == small_frag.file and
            location_overlap?(large_frag, small_frag)
        end)
      end)
  end

  defp location_overlap?(larger_frag, smaller_frag) do
    case {line_interval(larger_frag), line_interval(smaller_frag)} do
      {{large_start, large_end}, {small_start, small_end}} ->
        small_start >= large_start and small_end <= large_end

      _unknown ->
        true
    end
  end

  defp line_interval(%{ast: ast, line: fallback_line}) do
    case Location.line_range(ast) do
      {start_line, end_line} when is_integer(start_line) and is_integer(end_line) ->
        {start_line, end_line}

      _ when is_integer(fallback_line) and fallback_line > 0 ->
        {fallback_line, fallback_line}

      _ ->
        :unknown
    end
  end
end
