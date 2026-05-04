defmodule ExDNA.Refactor.MacroSuggestion do
  @moduledoc """
  Detects clone groups that should be refactored into macros rather than functions.

  A macro is suggested when a clone group has 3+ fragments that are all
  module-level constructs (not inside a `def`) and contain struct literals
  or DSL calls like `field :name, :string` or `pipe_through [:browser]`.
  """

  alias ExDNA.Detection.Clone

  @dsl_calls ~w(field belongs_to has_one has_many many_to_many embeds_one embeds_many
                 timestamps pipe_through plug get post put patch delete resources
                 live scope forward)a

  @doc """
  Returns true if the clone group qualifies for a macro extraction suggestion.
  """
  @spec macro_candidate?(Clone.t()) :: boolean()
  def macro_candidate?(%Clone{fragments: []}), do: false
  def macro_candidate?(%Clone{fragments: [_]}), do: false
  def macro_candidate?(%Clone{fragments: [_, _]}), do: false

  def macro_candidate?(%Clone{fragments: frags}) do
    Enum.all?(frags, fn frag ->
      not inside_def?(frag.ast) and has_macro_content?(frag.ast)
    end)
  end

  @doc """
  Generate a macro name from a clone's fragments.
  """
  @spec macro_name(Clone.t()) :: String.t()
  def macro_name(%Clone{fragments: [frag | _]}) do
    name_from_ast(frag.ast)
  end

  defp inside_def?({kind, _, _}) when kind in [:def, :defp], do: true
  defp inside_def?(_), do: false

  defp has_macro_content?(ast) do
    has_struct_literal?(ast) or has_dsl_call?(ast)
  end

  defp has_struct_literal?(ast) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        {:%, _, _} = node, _acc -> {node, true}
        node, acc -> {node, acc}
      end)

    found
  end

  defp has_dsl_call?(ast) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        {name, _, args} = node, acc when is_atom(name) and is_list(args) ->
          if name in @dsl_calls, do: {node, true}, else: {node, acc}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp name_from_ast({:%, _, [{:__aliases__, _, parts}, _]}) do
    struct_name = parts |> List.last() |> Atom.to_string() |> Macro.underscore()
    "build_#{struct_name}"
  end

  defp name_from_ast({name, _, args}) when is_atom(name) and is_list(args) do
    if name in @dsl_calls do
      "#{name}_block"
    else
      "shared_#{name}"
    end
  end

  defp name_from_ast(_), do: "shared_macro"
end
