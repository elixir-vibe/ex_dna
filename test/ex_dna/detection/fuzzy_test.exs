defmodule ExDNA.Detection.FuzzyTest do
  use ExUnit.Case, async: true

  alias ExDNA.AST.Fingerprint
  alias ExDNA.Detection.Fuzzy

  defp make_fragment(code, file, line) do
    ast = Code.string_to_quoted!(code)

    [frag | _] =
      Fingerprint.fragments(ast, file, 1)
      |> Enum.sort_by(& &1.mass, :desc)

    %{frag | line: line}
  end

  defp synthetic_fragment(code, file) do
    ast = Code.string_to_quoted!(code)

    %{
      hash: :crypto.hash(:sha256, code),
      mass: Fingerprint.mass(ast),
      ast: ast,
      file: file,
      line: 1,
      sub_hashes: MapSet.new([:shared])
    }
  end

  describe "detect/3" do
    test "finds near-miss clones above threshold" do
      frag_a =
        make_fragment(
          """
          data
          |> Enum.map(fn x -> x * 2 end)
          |> Enum.filter(fn x -> x > 10 end)
          |> Enum.sort()
          """,
          "a.ex",
          1
        )

      frag_b =
        make_fragment(
          """
          data
          |> Enum.map(fn x -> x * 2 end)
          |> Enum.filter(fn x -> x > 10 end)
          |> Enum.take(5)
          """,
          "b.ex",
          1
        )

      clones = Fuzzy.detect([frag_a, frag_b], 0.7, MapSet.new())

      assert clones != []
      [clone] = clones
      assert clone.type == :type_iii
      assert clone.similarity >= 0.7
    end

    test "groups connected near-miss pairs into one clone" do
      fragments = [
        synthetic_fragment(
          """
          data
          |> Enum.map(fn x -> x * 2 end)
          |> Enum.filter(fn x -> x > 10 end)
          |> Enum.sort()
          """,
          "a.ex"
        ),
        synthetic_fragment(
          """
          data
          |> Enum.map(fn x -> x * 2 end)
          |> Enum.filter(fn x -> x > 10 end)
          |> Enum.take(5)
          """,
          "b.ex"
        ),
        synthetic_fragment(
          """
          data
          |> Enum.map(fn x -> x * 2 end)
          |> Enum.filter(fn x -> x > 10 end)
          |> Enum.reverse()
          """,
          "c.ex"
        )
      ]

      clones = Fuzzy.detect(fragments, 0.7, MapSet.new())

      assert [clone] = clones
      assert length(clone.fragments) == 3
      assert clone.similarity >= 0.7
    end

    test "keeps one fragment per file and line in grouped clones" do
      fragments = [
        synthetic_fragment("foo(a, b, c) |> bar() |> baz()", "a.ex"),
        synthetic_fragment("foo(a, b, c) |> bar()", "a.ex"),
        synthetic_fragment("foo(x, y, z) |> qux() |> baz()", "b.ex")
      ]

      clones = Fuzzy.detect(fragments, 0.3, MapSet.new())

      assert [clone] = clones
      assert Enum.uniq_by(clone.fragments, &{&1.file, &1.line}) == clone.fragments
    end

    test "skips exact matches already found" do
      code = """
      data
      |> Enum.map(fn x -> x * 2 end)
      |> Enum.filter(fn x -> x > 10 end)
      """

      frag_a = make_fragment(code, "a.ex", 1)
      frag_b = make_fragment(code, "b.ex", 1)

      exact_hashes = MapSet.new([frag_a.hash])
      clones = Fuzzy.detect([frag_a, frag_b], 0.7, exact_hashes)

      assert clones == []
    end

    test "ignores pairs below threshold" do
      frag_a = make_fragment("foo(1, 2, 3)", "a.ex", 1)

      frag_b =
        make_fragment(
          "bar(String.upcase(x), Enum.count(y), Map.get(z, :key))",
          "b.ex",
          1
        )

      clones = Fuzzy.detect([frag_a, frag_b], 0.9, MapSet.new())

      assert clones == []
    end

    test "uses configured normalizer options for final similarity" do
      frag_a =
        synthetic_fragment(
          """
          data
          |> Enum.map(fn x -> x * 2 end)
          |> Enum.filter(fn x -> x > 10 end)
          |> Enum.sort()
          """,
          "pipe.ex"
        )

      frag_b =
        synthetic_fragment(
          """
          Enum.sort(Enum.filter(Enum.map(data, fn x -> x * 2 end), fn x -> x > 10 end))
          """,
          "nested.ex"
        )

      assert Fuzzy.detect([frag_a, frag_b], 0.95, MapSet.new()) == []

      clones =
        Fuzzy.detect([frag_a, frag_b], 0.95, MapSet.new(),
          normalizer_opts: [normalize_pipes: true]
        )

      assert [_clone] = clones
    end

    test "ignores fragments at the same location" do
      code_a = """
      data |> Enum.map(fn x -> x * 2 end) |> Enum.sort()
      """

      code_b = """
      data |> Enum.map(fn x -> x * 3 end) |> Enum.sort()
      """

      frag_a = make_fragment(code_a, "same.ex", 5)
      frag_b = make_fragment(code_b, "same.ex", 5)

      clones = Fuzzy.detect([frag_a, frag_b], 0.7, MapSet.new())
      assert clones == []
    end
  end
end
