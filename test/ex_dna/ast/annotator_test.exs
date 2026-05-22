defmodule ExDNA.AST.AnnotatorTest do
  use ExUnit.Case, async: true

  alias ExDNA.AST.Annotator

  describe "suppressed_lines/1" do
    test "detects next-line suppression comments" do
      source = """
      defmodule Foo do
        # ex_dna:disable-for-next-line
        def skip_me(x), do: x + 1
      end
      """

      assert Annotator.suppressed_lines(source) == MapSet.new([3])
    end

    test "detects previous-line suppression comments" do
      source = """
      defmodule Foo do
        def skip_me(x), do: x + 1
        # ex_dna:disable-for-previous-line
      end
      """

      assert Annotator.suppressed_lines(source) == MapSet.new([2])
    end

    test "detects file suppression comments" do
      assert Annotator.suppressed_lines("# ex_dna:disable-for-this-file\n") == :all
    end

    test "detects line range suppression comments" do
      source = """
      defmodule Foo do
        # ex_dna:disable-for-lines:2
        def skip_a(x), do: x + 1
        def skip_b(x), do: x - 1
      end
      """

      assert Annotator.suppressed_lines(source) == MapSet.new([3, 4])
    end
  end

  describe "strip_suppressed/2" do
    test "removes def on suppressed line" do
      ast =
        Code.string_to_quoted!("""
        defmodule Foo do
          def skip_me(x), do: x + 1

          def keep_me(x), do: x * 2
        end
        """)

      stripped = Annotator.strip_suppressed(ast, MapSet.new([2]))
      code = Macro.to_string(stripped)

      refute code =~ "skip_me"
      assert code =~ "keep_me"
    end

    test "removes defp on suppressed line" do
      ast =
        Code.string_to_quoted!("""
        defmodule Foo do
          defp helper(x), do: x + 1

          def public(x), do: x * 2
        end
        """)

      stripped = Annotator.strip_suppressed(ast, MapSet.new([2]))
      code = Macro.to_string(stripped)

      refute code =~ "helper"
      assert code =~ "public"
    end

    test "removes defmacro on suppressed line" do
      ast =
        Code.string_to_quoted!("""
        defmodule Foo do
          defmacro skip_me(value), do: value

          def keep_me(x), do: x * 2
        end
        """)

      stripped = Annotator.strip_suppressed(ast, MapSet.new([2]))
      code = Macro.to_string(stripped)

      refute code =~ "skip_me"
      assert code =~ "keep_me"
    end

    test "removes all clauses when one clause is suppressed" do
      ast =
        Code.string_to_quoted!("""
        defmodule Foo do
          def skip_me(:a), do: :a
          def skip_me(:b), do: :b

          def keep_me(x), do: x
        end
        """)

      stripped = Annotator.strip_suppressed(ast, MapSet.new([2]))
      code = Macro.to_string(stripped)

      refute code =~ "skip_me"
      assert code =~ "keep_me"
    end

    test "keeps defs without suppression" do
      ast =
        Code.string_to_quoted!("""
        defmodule Foo do
          def alpha(x), do: x + 1
          def beta(x), do: x * 2
        end
        """)

      stripped = Annotator.strip_suppressed(ast, MapSet.new())
      code = Macro.to_string(stripped)

      assert code =~ "alpha"
      assert code =~ "beta"
    end

    test "removes multiple suppressed defs" do
      ast =
        Code.string_to_quoted!("""
        defmodule Foo do
          def skip_a(x), do: x + 1
          def skip_b(x), do: x - 1

          def keep(x), do: x * 2
        end
        """)

      stripped = Annotator.strip_suppressed(ast, MapSet.new([2, 3]))
      code = Macro.to_string(stripped)

      refute code =~ "skip_a"
      refute code =~ "skip_b"
      assert code =~ "keep"
    end

    test "handles nested modules" do
      ast =
        Code.string_to_quoted!("""
        defmodule Outer do
          defmodule Inner do
            def skip(x), do: x

            def keep(x), do: x + 1
          end

          def outer_keep(x), do: x * 3
        end
        """)

      stripped = Annotator.strip_suppressed(ast, MapSet.new([3]))
      code = Macro.to_string(stripped)

      refute code =~ "skip"
      assert code =~ "keep"
      assert code =~ "outer_keep"
    end

    test "passes through AST without defmodule unchanged" do
      ast =
        Code.string_to_quoted!("""
        x = 1 + 2
        """)

      assert Annotator.strip_suppressed(ast, MapSet.new([1])) == ast
    end
  end
end
