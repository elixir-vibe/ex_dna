defmodule ExDNA.Refactor.Suggestion do
  @moduledoc """
  Generates refactoring suggestions from detected clones.

  Uses anti-unification to find the common structure between clone fragments,
  then proposes an extracted function whose parameters are the "holes" —
  the positions where the fragments diverge.
  """

  alias ExDNA.AST.AntiUnifier
  alias ExDNA.AST.Normalizer
  alias ExDNA.Detection.Clone
  alias ExDNA.Refactor.MacroSuggestion

  @type kind :: :extract_function | :extract_macro

  @type t :: %__MODULE__{
          kind: kind(),
          name: String.t(),
          params: [atom()],
          body: String.t(),
          call_sites: [%{file: String.t(), line: pos_integer(), call: String.t()}],
          occurrence_count: non_neg_integer() | nil
        }

  defstruct [:kind, :name, :body, :occurrence_count, params: [], call_sites: []]

  @doc """
  Generate a refactoring suggestion for a clone group.

  Takes the first two fragments, anti-unifies them, and builds a function
  extraction suggestion. When there are zero holes the suggestion is a
  simple extract; when there are holes they become function parameters.
  """
  @spec suggest(Clone.t()) :: t() | nil
  def suggest(%Clone{fragments: []}), do: nil
  def suggest(%Clone{fragments: [_]}), do: nil

  def suggest(%Clone{} = clone) do
    if MacroSuggestion.macro_candidate?(clone) do
      suggest_macro(clone)
    else
      suggest_function(clone)
    end
  end

  defp suggest_macro(%Clone{fragments: frags} = clone) do
    [frag_a, frag_b | _] = frags

    ast_a = Normalizer.strip_metadata(frag_a.ast)
    ast_b = Normalizer.strip_metadata(frag_b.ast)

    {_pattern, holes} = AntiUnifier.anti_unify(ast_a, ast_b)

    macro_name = MacroSuggestion.macro_name(clone)
    param_names = if holes == [], do: [], else: [:opts]

    %__MODULE__{
      kind: :extract_macro,
      name: macro_name,
      params: param_names,
      body: frag_a.ast |> humanize_ast() |> safe_to_string(),
      occurrence_count: length(frags),
      call_sites: Enum.map(frags, fn frag -> %{file: frag.file, line: frag.line, call: ""} end)
    }
  end

  defp suggest_function(%Clone{fragments: frags} = clone) do
    [frag_a, frag_b | _] = frags

    ast_a = Normalizer.strip_metadata(frag_a.ast)
    ast_b = Normalizer.strip_metadata(frag_b.ast)

    {pattern, holes} = AntiUnifier.anti_unify(ast_a, ast_b)

    unless callee_hole?(pattern, holes) do
      build_function_suggestion(clone, pattern, holes, ast_a)
    end
  end

  defp build_function_suggestion(%Clone{fragments: frags} = clone, pattern, holes, ast_a) do
    func_name = generate_name(clone)

    %__MODULE__{
      kind: :extract_function,
      name: func_name,
      params: Enum.map(holes, fn hole -> rename_hole(hole.var) end),
      body: suggestion_body(pattern, holes),
      call_sites: call_sites(frags, ast_a, holes, func_name)
    }
  end

  defp suggestion_body(pattern, []), do: pattern |> humanize_ast() |> safe_to_string()

  defp suggestion_body(pattern, holes) do
    pattern |> rename_holes(holes) |> humanize_ast() |> safe_to_string()
  end

  defp call_sites(frags, ast_a, holes, func_name) do
    frags
    |> Enum.with_index()
    |> Enum.map(fn {frag, idx} -> call_site(frag, ast_a, holes, idx, func_name) end)
  end

  defp call_site(frag, ast_a, holes, idx, func_name) do
    args =
      frag
      |> extract_hole_values(ast_a, holes, idx)
      |> Enum.map_join(", ", fn value -> value |> humanize_ast() |> safe_to_string() end)

    call = if args == "", do: "#{func_name}()", else: "#{func_name}(#{args})"

    %{file: frag.file, line: frag.line, call: call}
  end

  defp generate_name(%Clone{fragments: [frag | _]}) do
    ast = Normalizer.strip_metadata(frag.ast)
    name_from_ast(ast)
  end

  # 0. Grouped multi-clause def → delegate to the first clause
  defp name_from_ast({:__ex_dna_grouped_def__, _, [first | _]}) do
    name_from_ast(first)
  end

  # 1a. def / defp with guard clause → shared_<name>
  defp name_from_ast({def_kind, _, [{:when, _, [{name, _, _} | _]} | _]})
       when def_kind in [:def, :defp] and is_atom(name) do
    "shared_#{name}"
  end

  # 1b. def / defp wrapper → shared_<name>
  defp name_from_ast({def_kind, _, [{name, _, _} | _]})
       when def_kind in [:def, :defp] and is_atom(name) do
    "shared_#{name}"
  end

  # 2. Struct literal %Mod{...} → derive from struct + optional id field
  defp name_from_ast({:%, _, [{:__aliases__, _, parts}, {:%{}, _, fields}]}) do
    struct_name = parts |> List.last() |> Atom.to_string() |> Macro.underscore()

    case Keyword.get(fields, :id) do
      nil ->
        "build_#{struct_name}"

      id_val when is_atom(id_val) ->
        id_str = id_val |> Atom.to_string() |> String.trim_leading(":")
        "#{id_str}_#{struct_name}"

      id_val when is_binary(id_val) ->
        "#{id_val}_#{struct_name}"

      _ ->
        "build_#{struct_name}"
    end
  end

  # 3. case / if / cond → look at subject
  defp name_from_ast({:case, _, [subject | _]}) do
    "handle_#{subject_name(subject)}"
  end

  defp name_from_ast({:if, _, [subject | _]}) do
    "handle_#{subject_name(subject)}"
  end

  defp name_from_ast({:cond, _, _}) do
    "handle_condition"
  end

  # 4. Pipe chain → use last function in the chain
  defp name_from_ast({:|>, _, _} = ast) do
    calls = collect_pipe_calls(ast)

    case calls do
      [] ->
        "duplicated_block"

      [single] ->
        single

      calls ->
        # credo:disable-for-next-line ExSlop.Check.Refactor.ListLast
        last = List.last(calls)
        second_last = Enum.at(calls, -2)

        if second_last do
          "#{second_last}_and_#{last}"
        else
          last
        end
    end
  end

  # 5. Dominant call is a known pattern (e.g. Ecto.Changeset.cast)
  defp name_from_ast(ast) do
    dominant_call_name(ast) || "duplicated_block"
  end

  # --- Helpers for generate_name ---

  defp subject_name({{:., _, [{:__aliases__, _, _parts}, func_name]}, _, _})
       when is_atom(func_name) do
    Atom.to_string(func_name)
  end

  defp subject_name({func_name, _, args})
       when is_atom(func_name) and is_list(args) do
    Atom.to_string(func_name)
  end

  defp subject_name({name, _, ctx}) when is_atom(name) and is_atom(ctx) do
    Atom.to_string(name)
  end

  defp subject_name(_), do: "result"

  # Collect function names from a pipe chain
  defp collect_pipe_calls({:|>, _, [left, right]}) do
    collect_pipe_calls(left) ++ extract_call_name(right)
  end

  defp collect_pipe_calls(_), do: []

  defp extract_call_name({{:., _, [{:__aliases__, _, _}, func_name]}, _, _})
       when is_atom(func_name) do
    [Atom.to_string(func_name)]
  end

  defp extract_call_name({func_name, _, args})
       when is_atom(func_name) and is_list(args) and func_name != :|> do
    [Atom.to_string(func_name)]
  end

  defp extract_call_name(_), do: []

  # Check for known dominant call patterns in the AST
  @known_patterns %{
    [:Ecto, :Changeset] => "build_changeset",
    [:Ecto, :Query] => "build_query",
    [:Ecto, :Multi] => "build_multi",
    [:Repo] => "run_query",
    [:Jason] => "encode_json",
    [:Plug, :Conn] => "build_response"
  }

  defp dominant_call_name(ast) do
    calls = collect_all_calls(ast)

    Enum.find_value(@known_patterns, fn {mod_parts, name} ->
      if mod_parts in calls, do: name
    end)
  end

  defp collect_all_calls(ast) do
    {_, calls} =
      Macro.prewalk(ast, [], fn
        {{:., _, [{:__aliases__, _, parts}, _func]}, _, _} = node, acc ->
          {node, [parts | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.uniq(calls)
  end

  defp extract_hole_values(frag, ref_ast, holes, idx) do
    case idx do
      0 ->
        Enum.map(holes, fn hole -> Enum.at(hole.values, 0) end)

      1 ->
        Enum.map(holes, fn hole -> Enum.at(hole.values, 1) end)

      _ ->
        frag_ast = Normalizer.strip_metadata(frag.ast)
        ref_stripped = Normalizer.strip_metadata(ref_ast)
        {_pattern, frag_holes} = AntiUnifier.anti_unify(ref_stripped, frag_ast)
        Enum.map(frag_holes, fn hole -> Enum.at(hole.values, 1) end)
    end
  end

  defp rename_holes(ast, holes) do
    Enum.reduce(holes, ast, fn hole, acc ->
      renamed = rename_hole(hole.var)

      Macro.prewalk(acc, fn
        {var, meta, nil} when var == hole.var -> {renamed, meta, nil}
        other -> other
      end)
    end)
  end

  defp callee_hole?(_pattern, []), do: false

  defp callee_hole?(pattern, holes) do
    hole_vars = MapSet.new(holes, & &1.var)

    {_ast, found?} =
      Macro.prewalk(pattern, false, fn
        {form, _meta, args} = node, found? when is_list(args) ->
          {node, found? or contains_hole?(form, hole_vars)}

        node, found? ->
          {node, found?}
      end)

    found?
  end

  defp contains_hole?({var, _meta, nil}, hole_vars) when is_atom(var) do
    MapSet.member?(hole_vars, var)
  end

  defp contains_hole?(ast, hole_vars) do
    {_ast, found?} =
      Macro.prewalk(ast, false, fn
        {var, _meta, nil} = node, found? when is_atom(var) ->
          {node, found? or MapSet.member?(hole_vars, var)}

        node, found? ->
          {node, found?}
      end)

    found?
  end

  defp rename_hole(var) do
    var
    |> Atom.to_string()
    |> String.replace("hole", "arg")
    |> String.to_atom()
  end

  defp safe_to_string(ast) do
    Macro.to_string(ast)
  rescue
    _ -> inspect(ast)
  end

  defp humanize_ast(ast) do
    ast = unwrap_grouped_def(ast)

    Macro.prewalk(ast, fn
      {name, meta, ctx} when is_atom(name) and is_atom(ctx) ->
        str = Atom.to_string(name)

        clean_name =
          cond do
            # Hole parameters renamed to argN — keep them as-is
            String.match?(str, ~r/^arg\d+$/) ->
              name

            # Normalized variables ($0, $1, ...) → var_0, var_1, ...
            String.match?(str, ~r/^\$\d+$/) ->
              index = String.trim_leading(str, "$")
              :"var_#{index}"

            # Original variable names — keep them if they're valid identifiers
            String.match?(str, ~r/^[a-z][a-zA-Z0-9_]*$/) ->
              name

            # Anything else — sanitize to valid identifier
            true ->
              sanitized =
                str
                |> String.replace(~r/[^a-zA-Z0-9_]/, "_")
                |> String.replace(~r/^[^a-z]/, "v_")

              String.to_atom(sanitized)
          end

        {clean_name, meta, ctx}

      other ->
        other
    end)
  end

  defp unwrap_grouped_def(ast) do
    Macro.prewalk(ast, fn
      {:__ex_dna_grouped_def__, _meta, clauses} -> {:__block__, [], clauses}
      node -> node
    end)
  end
end
