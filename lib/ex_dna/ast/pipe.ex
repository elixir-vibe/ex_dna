defmodule ExDNA.AST.Pipe do
  @moduledoc false

  @spec inject_first_arg(Macro.t(), Macro.t()) :: Macro.t()
  def inject_first_arg({call, meta, args}, first_arg) when is_list(args) do
    {call, meta, [first_arg | args]}
  end

  def inject_first_arg({call, meta, nil}, first_arg) do
    {call, meta, [first_arg]}
  end

  def inject_first_arg(other, first_arg) do
    {other, [], [first_arg]}
  end
end
