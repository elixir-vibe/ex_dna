defmodule ExDNA.AST.AntiUnifierTest do
  use ExUnit.Case, async: true

  alias ExDNA.AST.AntiUnifier

  describe "anti_unify/2" do
    test "identical ASTs produce zero holes" do
      ast = quote do: 1 + 2
      {pattern, holes} = AntiUnifier.anti_unify(ast, ast)

      assert holes == []
      assert pattern == ast
    end

    test "different variables produce holes" do
      ast_a = quote do: foo + bar
      ast_b = quote do: baz + qux

      {_pattern, holes} = AntiUnifier.anti_unify(ast_a, ast_b)

      assert length(holes) == 2
      assert Enum.all?(holes, fn h -> length(h.values) == 2 end)
    end

    test "preserves common structure" do
      ast_a =
        quote do
          Enum.map(list, fn x -> x * 2 end)
        end

      ast_b =
        quote do
          Enum.map(items, fn y -> y * 3 end)
        end

      {pattern, holes} = AntiUnifier.anti_unify(ast_a, ast_b)

      pattern_str = Macro.to_string(pattern)
      assert pattern_str =~ "Enum.map"
      assert holes != []
    end

    test "different literals become holes" do
      ast_a = quote do: String.duplicate("hello", 3)
      ast_b = quote do: String.duplicate("world", 5)

      {pattern, holes} = AntiUnifier.anti_unify(ast_a, ast_b)

      assert length(holes) == 2
      pattern_str = Macro.to_string(pattern)
      assert pattern_str =~ "String.duplicate"
    end

    test "different alias components become one whole-alias hole" do
      ast_a = quote do: Pricing.Anthropic.lookup(provider, model, usage)
      ast_b = quote do: Pricing.OpenAI.lookup(provider, model, usage)

      {pattern, holes} = AntiUnifier.anti_unify(ast_a, ast_b)

      assert [hole] = holes
      assert hole.values == [quote(do: Pricing.Anthropic), quote(do: Pricing.OpenAI)]
      assert Macro.to_string(pattern) =~ "hole0.lookup"
    end

    test "completely different trees produce a single hole" do
      ast_a = quote do: foo(1, 2, 3)
      ast_b = quote do: bar(1)

      {_pattern, holes} = AntiUnifier.anti_unify(ast_a, ast_b)

      assert length(holes) == 1
    end

    test "pipes with different data but same operations" do
      ast_a =
        quote do
          data
          |> Enum.map(fn x -> x * 2 end)
          |> Enum.filter(fn x -> x > 0 end)
        end

      ast_b =
        quote do
          items
          |> Enum.map(fn y -> y * 2 end)
          |> Enum.filter(fn y -> y > 0 end)
        end

      {pattern, holes} = AntiUnifier.anti_unify(ast_a, ast_b)

      pattern_str = Macro.to_string(pattern)
      assert pattern_str =~ "Enum.map"
      assert pattern_str =~ "Enum.filter"
      assert holes != []
    end

    test "holes contain both original values" do
      ast_a = quote do: x + 42
      ast_b = quote do: y + 99

      {_pattern, holes} = AntiUnifier.anti_unify(ast_a, ast_b)

      int_hole = Enum.find(holes, fn h -> 42 in h.values end)
      assert int_hole
      assert 99 in int_hole.values
    end
  end
end
