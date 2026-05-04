defmodule ExDNA.AST.ClauseGrouperTest do
  use ExUnit.Case, async: true

  alias ExDNA.AST.ClauseGrouper

  describe "group/1" do
    test "groups consecutive defp clauses with same name/arity" do
      ast =
        quote do
          defmodule Foo do
            defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
            defp format_bytes(bytes) when bytes < 1_048_576, do: "#{bytes} KB"
            defp format_bytes(bytes), do: "#{bytes} MB"
          end
        end

      grouped = ClauseGrouper.group(ast)
      {:defmodule, _, [_, [do: {:__block__, _, body}]]} = grouped

      assert [{:__ex_dna_grouped_def__, _, clauses}] = body
      assert length(clauses) == 3
      assert Enum.all?(clauses, &match?({:defp, _, _}, &1))
    end

    test "groups consecutive def clauses" do
      ast =
        quote do
          defmodule Foo do
            def foo(:a), do: 1
            def foo(:b), do: 2
          end
        end

      grouped = ClauseGrouper.group(ast)
      {:defmodule, _, [_, [do: {:__block__, _, body}]]} = grouped

      assert [{:__ex_dna_grouped_def__, _, clauses}] = body
      assert length(clauses) == 2
    end

    test "does not group single-clause functions" do
      ast =
        quote do
          defmodule Foo do
            def bar(x), do: x + 1
          end
        end

      grouped = ClauseGrouper.group(ast)
      {:defmodule, _, [_, [do: body]]} = grouped

      refute match?({:__block__, _, [{:__ex_dna_grouped_def__, _, _}]}, body)
    end

    test "does not group non-consecutive clauses" do
      ast =
        quote do
          defmodule Foo do
            defp foo(:a), do: 1
            defp bar(x), do: x
            defp foo(:b), do: 2
          end
        end

      grouped = ClauseGrouper.group(ast)
      {:defmodule, _, [_, [do: {:__block__, _, body}]]} = grouped

      grouped_nodes = Enum.filter(body, &match?({:__ex_dna_grouped_def__, _, _}, &1))
      assert grouped_nodes == []
    end

    test "does not group clauses with different arities" do
      ast =
        quote do
          defmodule Foo do
            defp foo(x), do: x
            defp foo(x, y), do: x + y
          end
        end

      grouped = ClauseGrouper.group(ast)
      {:defmodule, _, [_, [do: {:__block__, _, body}]]} = grouped

      grouped_nodes = Enum.filter(body, &match?({:__ex_dna_grouped_def__, _, _}, &1))
      assert grouped_nodes == []
    end

    test "does not group def and defp with same name" do
      ast =
        quote do
          defmodule Foo do
            def foo(:a), do: 1
            defp foo(:b), do: 2
          end
        end

      grouped = ClauseGrouper.group(ast)
      {:defmodule, _, [_, [do: {:__block__, _, body}]]} = grouped

      grouped_nodes = Enum.filter(body, &match?({:__ex_dna_grouped_def__, _, _}, &1))
      assert grouped_nodes == []
    end

    test "handles multiple grouped functions in same module" do
      ast =
        quote do
          defmodule Foo do
            defp foo(:a), do: 1
            defp foo(:b), do: 2
            defp bar(:x), do: :x
            defp bar(:y), do: :y
          end
        end

      grouped = ClauseGrouper.group(ast)
      {:defmodule, _, [_, [do: {:__block__, _, body}]]} = grouped

      grouped_nodes = Enum.filter(body, &match?({:__ex_dna_grouped_def__, _, _}, &1))
      assert length(grouped_nodes) == 2
    end

    test "preserves non-def nodes between groups" do
      ast =
        quote do
          defmodule Foo do
            @doc "hello"
            defp foo(:a), do: 1
            defp foo(:b), do: 2
          end
        end

      grouped = ClauseGrouper.group(ast)
      {:defmodule, _, [_, [do: {:__block__, _, body}]]} = grouped

      assert length(body) == 2
      assert match?({:@, _, _}, hd(body))
      # credo:disable-for-next-line ExSlop.Check.Refactor.ListLast
      assert match?({:__ex_dna_grouped_def__, _, _}, List.last(body))
    end

    test "handles nested modules" do
      ast =
        quote do
          defmodule Outer do
            defmodule Inner do
              defp foo(:a), do: 1
              defp foo(:b), do: 2
            end
          end
        end

      grouped = ClauseGrouper.group(ast)
      {:defmodule, _, [_, [do: inner_module]]} = grouped
      {:defmodule, _, [_, [do: {:__block__, _, inner_body}]]} = inner_module

      assert [{:__ex_dna_grouped_def__, _, clauses}] = inner_body
      assert length(clauses) == 2
    end

    test "passes through AST without defmodule unchanged" do
      ast = quote do: 1 + 2
      assert ClauseGrouper.group(ast) == ast
    end

    test "groups defmacro clauses" do
      ast =
        quote do
          defmodule Foo do
            defmacro bar(:a), do: 1
            defmacro bar(:b), do: 2
          end
        end

      grouped = ClauseGrouper.group(ast)
      {:defmodule, _, [_, [do: {:__block__, _, body}]]} = grouped

      assert [{:__ex_dna_grouped_def__, _, clauses}] = body
      assert length(clauses) == 2
    end
  end

  describe "delegation grouping" do
    test "groups wrapper clause with its target" do
      ast =
        quote do
          defmodule Foo do
            def fetch(id), do: fetch(id, [])

            def fetch(id, opts) do
              GenServer.call(server(), {:fetch, id}, Keyword.get(opts, :timeout, 5000))
            end
          end
        end

      grouped = ClauseGrouper.group(ast)
      {:defmodule, _, [_, [do: {:__block__, _, body}]]} = grouped

      assert [{:__ex_dna_grouped_def__, _, clauses}] = body
      assert length(clauses) == 2
    end

    test "groups defp wrapper with defp target" do
      ast =
        quote do
          defmodule Foo do
            defp parse(data), do: parse(data, [])
            defp parse(data, opts), do: do_parse(data, opts)
          end
        end

      grouped = ClauseGrouper.group(ast)
      {:defmodule, _, [_, [do: {:__block__, _, body}]]} = grouped

      assert [{:__ex_dna_grouped_def__, _, clauses}] = body
      assert length(clauses) == 2
    end

    test "does not group when wrapper calls a different function" do
      ast =
        quote do
          defmodule Foo do
            def fetch(id), do: do_fetch(id, [])
            def fetch(id, opts), do: do_fetch(id, opts)
          end
        end

      grouped = ClauseGrouper.group(ast)
      {:defmodule, _, [_, [do: {:__block__, _, body}]]} = grouped

      grouped_nodes = Enum.filter(body, &match?({:__ex_dna_grouped_def__, _, _}, &1))
      assert grouped_nodes == []
    end

    test "does not group when arities go wrong direction" do
      ast =
        quote do
          defmodule Foo do
            def fetch(id, opts), do: fetch(id)
            def fetch(id), do: :ok
          end
        end

      grouped = ClauseGrouper.group(ast)
      {:defmodule, _, [_, [do: {:__block__, _, body}]]} = grouped

      grouped_nodes = Enum.filter(body, &match?({:__ex_dna_grouped_def__, _, _}, &1))
      assert grouped_nodes == []
    end

    test "groups delegation that already has same-arity grouping on target" do
      ast =
        quote do
          defmodule Foo do
            def process(data), do: process(data, [])
            def process(data, opts) when is_list(opts), do: do_it(data, opts)
            def process(data, opts) when is_map(opts), do: do_it(data, Map.to_list(opts))
          end
        end

      grouped = ClauseGrouper.group(ast)
      {:defmodule, _, [_, [do: {:__block__, _, body}]]} = grouped

      assert [{:__ex_dna_grouped_def__, _, clauses}] = body
      assert length(clauses) == 2

      [_wrapper, target] = clauses
      assert match?({:__ex_dna_grouped_def__, _, _}, target)
    end
  end
end
