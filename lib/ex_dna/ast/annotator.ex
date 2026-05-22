defmodule ExDNA.AST.Annotator do
  @moduledoc """
  Pre-processes the AST to handle source comments that suppress clone detection.

  ExDNA supports Credo-style comments:

      # ex_dna:disable-for-this-file
      # ex_dna:disable-for-next-line
      # ex_dna:disable-for-previous-line
      # ex_dna:disable-for-lines:3

  When a suppression comment targets a function or macro definition, that
  definition is stripped from the AST before fingerprinting.
  """

  @definition_forms [:def, :defp, :defmacro, :defmacrop]

  @doc """
  Remove function and macro definitions whose line is suppressed.
  """
  @spec strip_suppressed(Macro.t(), MapSet.t(pos_integer()) | :all) :: Macro.t()
  def strip_suppressed(_ast, :all), do: nil

  def strip_suppressed(ast, ignored_lines) do
    Macro.prewalk(ast, fn
      {:defmodule, meta, [alias_node, [do: {:__block__, block_meta, body}]]}
      when is_list(body) ->
        stripped_body = strip_body(body, ignored_lines)
        {:defmodule, meta, [alias_node, [do: {:__block__, block_meta, stripped_body}]]}

      {:defmodule, meta, [alias_node, [do: body]]} = node ->
        if ignored_def?(body, ignored_lines) do
          {:defmodule, meta, [alias_node, [do: {:__block__, [], []}]]}
        else
          node
        end

      other ->
        other
    end)
  end

  @doc """
  Returns suppressed lines from ExDNA config comments in source.
  """
  @spec suppressed_lines(String.t()) :: MapSet.t(pos_integer()) | :all
  def suppressed_lines(source) do
    source
    |> String.split("\n", trim: false)
    |> Enum.with_index(1)
    |> Enum.reduce(MapSet.new(), fn {line, line_no}, ignored_lines ->
      parse_comment(line, line_no, ignored_lines)
    end)
  end

  defp strip_body(nodes, ignored_lines) do
    ignored_signatures =
      nodes
      |> Enum.filter(&ignored_def?(&1, ignored_lines))
      |> Enum.map(&definition_signature/1)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    Enum.reject(nodes, fn node ->
      ignored_def?(node, ignored_lines) or ignored_signature?(node, ignored_signatures)
    end)
  end

  defp ignored_def?({form, meta, _args}, ignored_lines) when form in @definition_forms do
    meta
    |> Keyword.get(:line, 0)
    |> then(&MapSet.member?(ignored_lines, &1))
  end

  defp ignored_def?(_node, _ignored_lines), do: false

  defp ignored_signature?(node, ignored_signatures) do
    case definition_signature(node) do
      nil -> false
      signature -> MapSet.member?(ignored_signatures, signature)
    end
  end

  defp definition_signature({form, _meta, [{:when, _, [head | _guards]} | _body]})
       when form in @definition_forms do
    definition_head_signature(head)
  end

  defp definition_signature({form, _meta, [head | _body]}) when form in @definition_forms do
    definition_head_signature(head)
  end

  defp definition_signature(_node), do: nil

  defp definition_head_signature({name, _meta, args}) when is_atom(name) and is_list(args) do
    {name, length(args)}
  end

  defp definition_head_signature({name, _meta, atom}) when is_atom(name) and is_atom(atom) do
    {name, 0}
  end

  defp definition_head_signature(_head), do: nil

  defp parse_comment(line, line_no, ignored_lines) do
    case String.trim_leading(line) do
      "# ex_dna:disable-for-this-file" <> _rest ->
        :all

      "# ex_dna:disable-for-next-line" <> _rest ->
        add_line(ignored_lines, line_no + 1)

      "# ex_dna:disable-for-previous-line" <> _rest ->
        add_line(ignored_lines, line_no - 1)

      "# ex_dna:disable-for-lines:" <> rest ->
        add_line_range(ignored_lines, line_no, rest)

      _other ->
        ignored_lines
    end
  end

  defp add_line(:all, _line_no), do: :all
  defp add_line(ignored_lines, line_no) when line_no > 0, do: MapSet.put(ignored_lines, line_no)
  defp add_line(ignored_lines, _line_no), do: ignored_lines

  defp add_line_range(:all, _line_no, _rest), do: :all

  defp add_line_range(ignored_lines, line_no, rest) do
    case Integer.parse(rest) do
      {count, _suffix} when count > 0 ->
        Enum.reduce((line_no + 1)..(line_no + count), ignored_lines, &add_line(&2, &1))

      {count, _suffix} when count < 0 ->
        Enum.reduce((line_no + count)..(line_no - 1), ignored_lines, &add_line(&2, &1))

      _other ->
        ignored_lines
    end
  end
end
