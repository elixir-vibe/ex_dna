defmodule ExDNA.Refactor.SuggestionTest do
  use ExUnit.Case, async: true

  alias ExDNA.Detection.Clone
  alias ExDNA.Refactor.Suggestion

  describe "suggest/1" do
    test "returns nil for clones with fewer than 2 fragments" do
      clone = %Clone{
        type: :type_i,
        hash: "x",
        mass: 10,
        fragments: [%{file: "a.ex", line: 1, ast: quote(do: 1 + 2), mass: 10}]
      }

      assert Suggestion.suggest(clone) == nil
    end

    test "generates suggestion for exact clone" do
      ast =
        quote do
          data
          |> Enum.map(fn x -> x * 2 end)
          |> Enum.filter(fn x -> x > 0 end)
        end

      clone = %Clone{
        type: :type_i,
        hash: "x",
        mass: 20,
        fragments: [
          %{file: "a.ex", line: 5, ast: ast, mass: 20},
          %{file: "b.ex", line: 10, ast: ast, mass: 20}
        ]
      }

      suggestion = Suggestion.suggest(clone)

      assert %Suggestion{kind: :extract_function} = suggestion
      assert suggestion.params == []
      assert suggestion.body =~ "Enum.map"
      assert length(suggestion.call_sites) == 2
    end

    test "generates parameterized suggestion for clones with differences" do
      ast_a =
        quote do
          Enum.map(list, fn x -> x * 2 end)
        end

      ast_b =
        quote do
          Enum.map(items, fn y -> y * 3 end)
        end

      clone = %Clone{
        type: :type_i,
        hash: "x",
        mass: 15,
        fragments: [
          %{file: "a.ex", line: 5, ast: ast_a, mass: 15},
          %{file: "b.ex", line: 10, ast: ast_b, mass: 15}
        ]
      }

      suggestion = Suggestion.suggest(clone)

      assert %Suggestion{kind: :extract_function} = suggestion
      assert suggestion.params != []
      assert suggestion.body =~ "Enum.map"
    end

    test "call sites show original values for holes" do
      ast_a = quote do: String.duplicate("hello", 3)
      ast_b = quote do: String.duplicate("world", 5)

      clone = %Clone{
        type: :type_i,
        hash: "x",
        mass: 10,
        fragments: [
          %{file: "a.ex", line: 1, ast: ast_a, mass: 10},
          %{file: "b.ex", line: 1, ast: ast_b, mass: 10}
        ]
      }

      suggestion = Suggestion.suggest(clone)

      assert suggestion
      [site_a, site_b] = suggestion.call_sites
      assert site_a.call =~ "hello"
      assert site_b.call =~ "world"
    end

    test "skips extraction suggestion when local callee names differ" do
      ast_a = quote do: cost(order, currency)
      ast_b = quote do: lookup(order, currency)

      clone = %Clone{
        type: :type_iii,
        hash: "x",
        mass: 10,
        fragments: [
          %{file: "a.ex", line: 1, ast: ast_a, mass: 10},
          %{file: "b.ex", line: 1, ast: ast_b, mass: 10}
        ]
      }

      assert Suggestion.suggest(clone) == nil
    end

    test "skips extraction suggestion when remote callee names differ" do
      ast_a = quote do: Pricing.cost(order, currency)
      ast_b = quote do: Pricing.lookup(order, currency)

      clone = %Clone{
        type: :type_iii,
        hash: "x",
        mass: 10,
        fragments: [
          %{file: "a.ex", line: 1, ast: ast_a, mass: 10},
          %{file: "b.ex", line: 1, ast: ast_b, mass: 10}
        ]
      }

      assert Suggestion.suggest(clone) == nil
    end

    test "skips extraction suggestion when remote module alias components differ" do
      ast_a = quote do: Pricing.Anthropic.lookup(provider, model, usage)
      ast_b = quote do: Pricing.OpenAI.lookup(provider, model, usage)

      clone = %Clone{
        type: :type_iii,
        hash: "x",
        mass: 10,
        fragments: [
          %{file: "a.ex", line: 1, ast: ast_a, mass: 10},
          %{file: "b.ex", line: 1, ast: ast_b, mass: 10}
        ]
      }

      assert Suggestion.suggest(clone) == nil
    end

    test "names extracted function based on original def" do
      ast =
        quote do
          def process(data) do
            data |> Enum.map(fn x -> x * 2 end) |> Enum.sort()
          end
        end

      clone = %Clone{
        type: :type_i,
        hash: "x",
        mass: 20,
        fragments: [
          %{file: "a.ex", line: 1, ast: ast, mass: 20},
          %{file: "b.ex", line: 1, ast: ast, mass: 20}
        ]
      }

      suggestion = Suggestion.suggest(clone)
      assert suggestion.name == "shared_process"
    end

    test "names grouped multi-clause function with guard" do
      clause_a =
        quote do
          defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
        end

      clause_b =
        quote do
          defp format_bytes(bytes) when bytes < 1_048_576, do: "#{bytes} KB"
        end

      clause_c =
        quote do
          defp format_bytes(bytes), do: "#{bytes} MB"
        end

      grouped_ast = {:__ex_dna_grouped_def__, [], [clause_a, clause_b, clause_c]}

      clone = %Clone{
        type: :type_i,
        hash: "x",
        mass: 50,
        fragments: [
          %{file: "a.ex", line: 1, ast: grouped_ast, mass: 50},
          %{file: "b.ex", line: 1, ast: grouped_ast, mass: 50}
        ]
      }

      suggestion = Suggestion.suggest(clone)
      assert suggestion.name == "shared_format_bytes"
      refute String.contains?(suggestion.body, "__ex_dna_grouped_def__")
    end

    test "names extracted function based on original defp" do
      ast =
        quote do
          defp transform(data) do
            Enum.map(data, &to_string/1)
          end
        end

      clone = %Clone{
        type: :type_i,
        hash: "x",
        mass: 15,
        fragments: [
          %{file: "a.ex", line: 1, ast: ast, mass: 15},
          %{file: "b.ex", line: 1, ast: ast, mass: 15}
        ]
      }

      suggestion = Suggestion.suggest(clone)
      assert suggestion.name == "shared_transform"
    end
  end

  describe "generate_name - struct literals" do
    test "names from struct without id field" do
      ast = quote(do: %Step{action: :run, timeout: 5000})

      clone = %Clone{
        type: :type_i,
        hash: "x",
        mass: 10,
        fragments: [
          %{file: "a.ex", line: 1, ast: ast, mass: 10},
          %{file: "b.ex", line: 1, ast: ast, mass: 10}
        ]
      }

      suggestion = Suggestion.suggest(clone)
      assert suggestion.name == "build_step"
    end

    test "names from struct with atom id field" do
      ast = quote(do: %Step{id: :contact_step, action: :run})

      clone = %Clone{
        type: :type_i,
        hash: "x",
        mass: 10,
        fragments: [
          %{file: "a.ex", line: 1, ast: ast, mass: 10},
          %{file: "b.ex", line: 1, ast: ast, mass: 10}
        ]
      }

      suggestion = Suggestion.suggest(clone)
      assert suggestion.name == "contact_step_step"
    end

    test "names from struct with string id field" do
      ast = quote(do: %Config{id: "main_config", value: 42})

      clone = %Clone{
        type: :type_i,
        hash: "x",
        mass: 10,
        fragments: [
          %{file: "a.ex", line: 1, ast: ast, mass: 10},
          %{file: "b.ex", line: 1, ast: ast, mass: 10}
        ]
      }

      suggestion = Suggestion.suggest(clone)
      assert suggestion.name == "main_config_config"
    end

    test "names from struct with non-literal id falls back to build_" do
      ast = quote(do: %Step{id: some_var, action: :run})

      clone = %Clone{
        type: :type_i,
        hash: "x",
        mass: 10,
        fragments: [
          %{file: "a.ex", line: 1, ast: ast, mass: 10},
          %{file: "b.ex", line: 1, ast: ast, mass: 10}
        ]
      }

      suggestion = Suggestion.suggest(clone)
      assert suggestion.name == "build_step"
    end
  end

  describe "generate_name - case/if/cond" do
    test "case with module function call subject" do
      ast =
        quote do
          case Foo.bar(x) do
            :ok -> 1
            :error -> 2
          end
        end

      clone = %Clone{
        type: :type_i,
        hash: "x",
        mass: 15,
        fragments: [
          %{file: "a.ex", line: 1, ast: ast, mass: 15},
          %{file: "b.ex", line: 1, ast: ast, mass: 15}
        ]
      }

      suggestion = Suggestion.suggest(clone)
      assert suggestion.name == "handle_bar"
    end

    test "case with local function call subject" do
      ast =
        quote do
          case validate(input) do
            {:ok, result} -> result
            {:error, reason} -> raise reason
          end
        end

      clone = %Clone{
        type: :type_i,
        hash: "x",
        mass: 15,
        fragments: [
          %{file: "a.ex", line: 1, ast: ast, mass: 15},
          %{file: "b.ex", line: 1, ast: ast, mass: 15}
        ]
      }

      suggestion = Suggestion.suggest(clone)
      assert suggestion.name == "handle_validate"
    end

    test "case with variable subject" do
      ast =
        quote do
          case status do
            :active -> true
            :inactive -> false
          end
        end

      clone = %Clone{
        type: :type_i,
        hash: "x",
        mass: 10,
        fragments: [
          %{file: "a.ex", line: 1, ast: ast, mass: 10},
          %{file: "b.ex", line: 1, ast: ast, mass: 10}
        ]
      }

      suggestion = Suggestion.suggest(clone)
      assert suggestion.name == "handle_status"
    end

    test "if expression derives name from subject" do
      ast =
        quote do
          if valid?(data) do
            :ok
          else
            :error
          end
        end

      clone = %Clone{
        type: :type_i,
        hash: "x",
        mass: 10,
        fragments: [
          %{file: "a.ex", line: 1, ast: ast, mass: 10},
          %{file: "b.ex", line: 1, ast: ast, mass: 10}
        ]
      }

      suggestion = Suggestion.suggest(clone)
      assert suggestion.name == "handle_valid?"
    end

    test "cond expression gets generic name" do
      ast =
        quote do
          cond do
            x > 0 -> :positive
            x < 0 -> :negative
            true -> :zero
          end
        end

      clone = %Clone{
        type: :type_i,
        hash: "x",
        mass: 12,
        fragments: [
          %{file: "a.ex", line: 1, ast: ast, mass: 12},
          %{file: "b.ex", line: 1, ast: ast, mass: 12}
        ]
      }

      suggestion = Suggestion.suggest(clone)
      assert suggestion.name == "handle_condition"
    end
  end

  describe "generate_name - pipe chains" do
    test "pipe chain uses last two function names" do
      ast =
        quote do
          data
          |> Enum.map(fn x -> x * 2 end)
          |> Enum.sort()
        end

      clone = %Clone{
        type: :type_i,
        hash: "x",
        mass: 15,
        fragments: [
          %{file: "a.ex", line: 1, ast: ast, mass: 15},
          %{file: "b.ex", line: 1, ast: ast, mass: 15}
        ]
      }

      suggestion = Suggestion.suggest(clone)
      assert suggestion.name == "map_and_sort"
    end

    test "pipe chain with single function" do
      ast =
        quote do
          data |> Enum.sort()
        end

      clone = %Clone{
        type: :type_i,
        hash: "x",
        mass: 10,
        fragments: [
          %{file: "a.ex", line: 1, ast: ast, mass: 10},
          %{file: "b.ex", line: 1, ast: ast, mass: 10}
        ]
      }

      suggestion = Suggestion.suggest(clone)
      assert suggestion.name == "sort"
    end

    test "pipe chain with three+ functions uses last two" do
      ast =
        quote do
          data
          |> Enum.map(&to_string/1)
          |> Enum.filter(&(&1 != ""))
          |> Enum.sort()
        end

      clone = %Clone{
        type: :type_i,
        hash: "x",
        mass: 20,
        fragments: [
          %{file: "a.ex", line: 1, ast: ast, mass: 20},
          %{file: "b.ex", line: 1, ast: ast, mass: 20}
        ]
      }

      suggestion = Suggestion.suggest(clone)
      assert suggestion.name == "filter_and_sort"
    end
  end

  describe "generate_name - known patterns" do
    test "Ecto.Changeset call produces build_changeset" do
      ast =
        quote do
          Ecto.Changeset.cast(struct, params, [:name, :email])
        end

      clone = %Clone{
        type: :type_i,
        hash: "x",
        mass: 12,
        fragments: [
          %{file: "a.ex", line: 1, ast: ast, mass: 12},
          %{file: "b.ex", line: 1, ast: ast, mass: 12}
        ]
      }

      suggestion = Suggestion.suggest(clone)
      assert suggestion.name == "build_changeset"
    end

    test "Ecto.Query call produces build_query" do
      ast =
        quote do
          Ecto.Query.from(u in User, where: u.active == true)
        end

      clone = %Clone{
        type: :type_i,
        hash: "x",
        mass: 15,
        fragments: [
          %{file: "a.ex", line: 1, ast: ast, mass: 15},
          %{file: "b.ex", line: 1, ast: ast, mass: 15}
        ]
      }

      suggestion = Suggestion.suggest(clone)
      assert suggestion.name == "build_query"
    end
  end

  describe "generate_name - fallback" do
    test "unknown AST shape falls back to duplicated_block" do
      ast = quote(do: 1 + 2 + 3)

      clone = %Clone{
        type: :type_i,
        hash: "x",
        mass: 10,
        fragments: [
          %{file: "a.ex", line: 1, ast: ast, mass: 10},
          %{file: "b.ex", line: 1, ast: ast, mass: 10}
        ]
      }

      suggestion = Suggestion.suggest(clone)
      assert suggestion.name == "duplicated_block"
    end
  end

  describe "humanize_ast - variable names" do
    test "preserves original variable names in body" do
      ast =
        quote do
          Enum.map(users, fn user -> user.name end)
        end

      clone = %Clone{
        type: :type_i,
        hash: "x",
        mass: 12,
        fragments: [
          %{file: "a.ex", line: 1, ast: ast, mass: 12},
          %{file: "b.ex", line: 1, ast: ast, mass: 12}
        ]
      }

      suggestion = Suggestion.suggest(clone)
      assert suggestion.body =~ "users"
      assert suggestion.body =~ "user"
    end

    test "hole parameters become argN in body" do
      ast_a = quote(do: String.duplicate("hello", 3))
      ast_b = quote(do: String.duplicate("world", 5))

      clone = %Clone{
        type: :type_i,
        hash: "x",
        mass: 10,
        fragments: [
          %{file: "a.ex", line: 1, ast: ast_a, mass: 10},
          %{file: "b.ex", line: 1, ast: ast_b, mass: 10}
        ]
      }

      suggestion = Suggestion.suggest(clone)
      assert suggestion.body =~ "arg0"
      assert suggestion.body =~ "arg1"
      assert suggestion.params == [:arg0, :arg1]
    end

    test "call sites use original variable names" do
      ast_a =
        quote do
          Enum.map(users, fn x -> x * 2 end)
        end

      ast_b =
        quote do
          Enum.map(items, fn y -> y * 3 end)
        end

      clone = %Clone{
        type: :type_i,
        hash: "x",
        mass: 15,
        fragments: [
          %{file: "a.ex", line: 1, ast: ast_a, mass: 15},
          %{file: "b.ex", line: 1, ast: ast_b, mass: 15}
        ]
      }

      suggestion = Suggestion.suggest(clone)
      [site_a, site_b] = suggestion.call_sites
      assert site_a.call =~ "users"
      assert site_b.call =~ "items"
    end
  end
end
