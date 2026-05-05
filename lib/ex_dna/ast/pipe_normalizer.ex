defmodule ExDNA.AST.PipeNormalizer do
  @moduledoc """
  Normalizes pipe operators to nested function calls.

  `x |> foo() |> bar(1)` becomes `bar(foo(x), 1)`.

  This ensures that stylistic choices between pipe chains and nested calls
  don't prevent clone detection.
  """

  alias ExDNA.AST.Pipe

  @doc """
  Convert all pipe expressions in an AST to nested function calls.
  """
  @spec normalize(Macro.t()) :: Macro.t()
  def normalize(ast) do
    Macro.prewalk(ast, &flatten_pipe/1)
  end

  defp flatten_pipe({:|>, _meta, [left, right]}) do
    Pipe.inject_first_arg(right, left)
  end

  defp flatten_pipe(other), do: other
end
