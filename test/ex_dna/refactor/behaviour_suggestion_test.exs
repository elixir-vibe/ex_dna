defmodule ExDNA.Refactor.BehaviourSuggestionTest do
  use ExUnit.Case, async: true

  alias ExDNA.Detection.Clone
  alias ExDNA.Refactor.BehaviourSuggestion

  setup do
    dir = Path.join(System.tmp_dir!(), "ex_dna_bs_test_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  defp def_ast(name, arity) do
    args =
      case arity do
        0 -> nil
        n -> Enum.map(1..n, fn i -> {:"arg#{i}", [line: 1], nil} end)
      end

    {:def, [line: 1], [{name, [line: 1], args}, [do: {:ok, [], nil}]]}
  end

  defp write_and_parse(dir, name, content) do
    path = Path.join(dir, name)
    File.write!(path, content)
    {:ok, ast} = Code.string_to_quoted(content, line: 1, columns: true, file: path)
    {path, ast}
  end

  describe "suggest/2" do
    test "suggests behaviour for identical defs in different files", %{dir: dir} do
      ast = def_ast(:validate, 1)

      {file_a, ast_a} =
        write_and_parse(dir, "bank_complaint.ex", """
        defmodule MyApp.BankComplaint do
          def validate(data), do: {:ok, data}
        end
        """)

      {file_b, ast_b} =
        write_and_parse(dir, "mfo_complaint.ex", """
        defmodule MyApp.MFOComplaint do
          def validate(data), do: {:ok, data}
        end
        """)

      file_asts = %{file_a => ast_a, file_b => ast_b}

      clone = %Clone{
        type: :type_i,
        hash: "x",
        mass: 15,
        fragments: [
          %{file: file_a, line: 2, ast: ast, mass: 15},
          %{file: file_b, line: 2, ast: ast, mass: 15}
        ]
      }

      suggestion = BehaviourSuggestion.suggest(clone, file_asts)

      assert %BehaviourSuggestion{} = suggestion
      assert suggestion.callback_name == :validate
      assert suggestion.callback_arity == 1
      assert "MyApp.BankComplaint" in suggestion.modules
      assert "MyApp.MFOComplaint" in suggestion.modules
    end

    test "resolves nested modules correctly", %{dir: dir} do
      ast = def_ast(:run, 0)

      {file, file_ast} =
        write_and_parse(dir, "outer.ex", """
        defmodule Outer do
          defmodule Inner do
            def run, do: :ok
          end

          defmodule Other do
            def run, do: :ok
          end
        end
        """)

      clone = %Clone{
        type: :type_i,
        hash: "x",
        mass: 8,
        fragments: [
          %{file: file, line: 3, ast: ast, mass: 8},
          %{file: file, line: 7, ast: ast, mass: 8}
        ]
      }

      suggestion = BehaviourSuggestion.suggest(clone, %{file => file_ast})

      assert %BehaviourSuggestion{} = suggestion
      assert "Outer.Inner" in suggestion.modules
      assert "Outer.Other" in suggestion.modules
    end

    test "suggests behaviour for zero-arity defs", %{dir: dir} do
      ast = def_ast(:defaults, 0)

      {file_a, ast_a} =
        write_and_parse(dir, "http.ex", "defmodule HttpClient do\n  def defaults, do: []\nend\n")

      {file_b, ast_b} =
        write_and_parse(dir, "grpc.ex", "defmodule GrpcClient do\n  def defaults, do: []\nend\n")

      clone = %Clone{
        type: :type_i,
        hash: "x",
        mass: 10,
        fragments: [
          %{file: file_a, line: 2, ast: ast, mass: 10},
          %{file: file_b, line: 2, ast: ast, mass: 10}
        ]
      }

      suggestion = BehaviourSuggestion.suggest(clone, %{file_a => ast_a, file_b => ast_b})
      assert suggestion.callback_name == :defaults
      assert suggestion.callback_arity == 0
    end

    test "returns nil when fragments are not defs" do
      ast =
        quote do
          Enum.map(list, fn x -> x * 2 end)
        end

      clone = %Clone{
        type: :type_i,
        hash: "x",
        mass: 10,
        fragments: [
          %{file: "lib/a.ex", line: 1, ast: ast, mass: 10},
          %{file: "lib/b.ex", line: 1, ast: ast, mass: 10}
        ]
      }

      assert BehaviourSuggestion.suggest(clone) == nil
    end

    test "returns nil when defs have different names" do
      ast_a = def_ast(:validate, 1)
      ast_b = def_ast(:verify, 1)

      clone = %Clone{
        type: :type_i,
        hash: "x",
        mass: 10,
        fragments: [
          %{file: "lib/a.ex", line: 1, ast: ast_a, mass: 10},
          %{file: "lib/b.ex", line: 1, ast: ast_b, mass: 10}
        ]
      }

      assert BehaviourSuggestion.suggest(clone) == nil
    end

    test "returns nil when all fragments come from the same module", %{dir: dir} do
      ast = def_ast(:validate, 1)

      {file, file_ast} =
        write_and_parse(dir, "complaint.ex", """
        defmodule Complaint do
          def validate(a), do: a
          def validate(b), do: b
        end
        """)

      clone = %Clone{
        type: :type_i,
        hash: "x",
        mass: 10,
        fragments: [
          %{file: file, line: 2, ast: ast, mass: 10},
          %{file: file, line: 3, ast: ast, mass: 10}
        ]
      }

      assert BehaviourSuggestion.suggest(clone, %{file => file_ast}) == nil
    end

    test "returns nil for fewer than 2 fragments" do
      ast = def_ast(:validate, 1)

      clone = %Clone{
        type: :type_i,
        hash: "x",
        mass: 10,
        fragments: [%{file: "lib/a.ex", line: 1, ast: ast, mass: 10}]
      }

      assert BehaviourSuggestion.suggest(clone) == nil
    end

    test "works with def across different files", %{dir: dir} do
      ast = def_ast(:transform, 1)

      {file_a, ast_a} =
        write_and_parse(
          dir,
          "parser_a.ex",
          "defmodule ParserA do\n  def transform(x), do: x\nend\n"
        )

      {file_b, ast_b} =
        write_and_parse(
          dir,
          "parser_b.ex",
          "defmodule ParserB do\n  def transform(x), do: x\nend\n"
        )

      clone = %Clone{
        type: :type_i,
        hash: "x",
        mass: 8,
        fragments: [
          %{file: file_a, line: 2, ast: ast, mass: 8},
          %{file: file_b, line: 2, ast: ast, mass: 8}
        ]
      }

      suggestion = BehaviourSuggestion.suggest(clone, %{file_a => ast_a, file_b => ast_b})
      assert suggestion.callback_name == :transform
      assert suggestion.callback_arity == 1
    end

    test "preserves acronyms in module names", %{dir: dir} do
      ast = def_ast(:run, 0)

      {file_a, ast_a} =
        write_and_parse(
          dir,
          "http_api.ex",
          "defmodule MyApp.HTTPAPI do\n  def run, do: :ok\nend\n"
        )

      {file_b, ast_b} =
        write_and_parse(
          dir,
          "grpc_api.ex",
          "defmodule MyApp.GRPCAPI do\n  def run, do: :ok\nend\n"
        )

      clone = %Clone{
        type: :type_i,
        hash: "x",
        mass: 8,
        fragments: [
          %{file: file_a, line: 2, ast: ast, mass: 8},
          %{file: file_b, line: 2, ast: ast, mass: 8}
        ]
      }

      suggestion = BehaviourSuggestion.suggest(clone, %{file_a => ast_a, file_b => ast_b})
      assert "MyApp.HTTPAPI" in suggestion.modules
      assert "MyApp.GRPCAPI" in suggestion.modules
    end
  end

  describe "analyze/2" do
    test "attaches behaviour_suggestion to qualifying clones", %{dir: dir} do
      ast = def_ast(:validate, 1)

      {file_a, ast_a} =
        write_and_parse(dir, "bank.ex", "defmodule Bank do\n  def validate(d), do: d\nend\n")

      {file_b, ast_b} =
        write_and_parse(dir, "mfo.ex", "defmodule MFO do\n  def validate(d), do: d\nend\n")

      clones = [
        %Clone{
          type: :type_i,
          hash: "x",
          mass: 10,
          fragments: [
            %{file: file_a, line: 2, ast: ast, mass: 10},
            %{file: file_b, line: 2, ast: ast, mass: 10}
          ]
        }
      ]

      [clone] = BehaviourSuggestion.analyze(clones, %{file_a => ast_a, file_b => ast_b})
      assert %BehaviourSuggestion{} = clone.behaviour_suggestion
      assert clone.behaviour_suggestion.callback_name == :validate
    end

    test "leaves behaviour_suggestion nil for non-qualifying clones" do
      ast =
        quote do
          Enum.map(list, fn x -> x * 2 end)
        end

      clones = [
        %Clone{
          type: :type_i,
          hash: "x",
          mass: 10,
          fragments: [
            %{file: "lib/a.ex", line: 1, ast: ast, mass: 10},
            %{file: "lib/b.ex", line: 1, ast: ast, mass: 10}
          ]
        }
      ]

      [clone] = BehaviourSuggestion.analyze(clones)
      assert clone.behaviour_suggestion == nil
    end
  end

  describe "find_enclosing_module/2" do
    test "finds single module" do
      {:ok, ast} =
        Code.string_to_quoted("""
        defmodule MyApp.Users do
          def list, do: []
        end
        """)

      assert BehaviourSuggestion.find_enclosing_module(ast, 2) == "MyApp.Users"
    end

    test "finds nested module" do
      {:ok, ast} =
        Code.string_to_quoted("""
        defmodule MyApp do
          defmodule Users do
            def list, do: []
          end
        end
        """)

      assert BehaviourSuggestion.find_enclosing_module(ast, 3) == "MyApp.Users"
    end

    test "distinguishes sibling modules" do
      {:ok, ast} =
        Code.string_to_quoted("""
        defmodule MyApp do
          defmodule Users do
            def list, do: []
          end

          defmodule Posts do
            def list, do: []
          end
        end
        """)

      assert BehaviourSuggestion.find_enclosing_module(ast, 3) == "MyApp.Users"
      assert BehaviourSuggestion.find_enclosing_module(ast, 7) == "MyApp.Posts"
    end

    test "returns nil for line outside any module" do
      {:ok, ast} = Code.string_to_quoted("x = 1")
      assert BehaviourSuggestion.find_enclosing_module(ast, 1) == nil
    end
  end
end
