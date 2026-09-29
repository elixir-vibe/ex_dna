defmodule ExDNA.CredoTest do
  use Credo.Test.Case

  alias Credo.Service.SourceFileSource
  alias ExDNA.Credo, as: Check
  alias ExDNA.Detection.AnalysisError

  setup_all do
    Application.ensure_all_started(:credo)
    :ok
  end

  @duplicate_a """
  defmodule A do
    def process(data) do
      data
      |> Enum.map(fn x -> x * 2 end)
      |> Enum.filter(fn x -> x > 10 end)
      |> Enum.sort()
      |> Enum.take(5)
    end
  end
  """

  @duplicate_b """
  defmodule B do
    def process(data) do
      data
      |> Enum.map(fn x -> x * 2 end)
      |> Enum.filter(fn x -> x > 10 end)
      |> Enum.sort()
      |> Enum.take(5)
    end
  end
  """

  @unique_a """
  defmodule UniqueA do
    def foo(x), do: x + 1
  end
  """

  @unique_b """
  defmodule UniqueB do
    def bar(x, y), do: x * y - 3
  end
  """

  test "reports issues for duplicate code across files" do
    issues =
      [
        to_source_file(@duplicate_a, "a.ex"),
        to_source_file(@duplicate_b, "b.ex")
      ]
      |> run_check(Check, paths: [], min_mass: 5)

    assert length(issues) >= 2

    issue_a = Enum.find(issues, &(&1.filename == "a.ex"))
    issue_b = Enum.find(issues, &(&1.filename == "b.ex"))

    assert issue_a.category == :design
    assert issue_a.message =~ "Duplicate code"
    assert issue_a.message =~ "b.ex"
    assert issue_b.message =~ "a.ex"
  end

  test "reports no issues for unique code" do
    issues =
      [
        to_source_file(@unique_a, "unique_a.ex"),
        to_source_file(@unique_b, "unique_b.ex")
      ]
      |> run_check(Check, paths: [], min_mass: 10)

    assert issues == []
  end

  test "respects ExDNA paths instead of analyzing every Credo source file" do
    dir = Path.join(System.tmp_dir!(), "ex_dna_credo_test_#{:erlang.unique_integer([:positive])}")
    lib_dir = Path.join(dir, "lib")
    test_dir = Path.join(dir, "test")
    File.mkdir_p!(lib_dir)
    File.mkdir_p!(test_dir)

    on_exit(fn -> File.rm_rf!(dir) end)

    lib_a = Path.join(lib_dir, "a.ex")
    lib_b = Path.join(lib_dir, "b.ex")
    test_a = Path.join(test_dir, "a_test.exs")
    test_b = Path.join(test_dir, "b_test.exs")

    Enum.each(
      [
        {lib_a, @duplicate_a},
        {lib_b, @duplicate_b},
        {test_a, @duplicate_a},
        {test_b, @duplicate_b}
      ],
      fn {path, source} -> File.write!(path, source) end
    )

    issues =
      [
        to_source_file(@duplicate_a, lib_a),
        to_source_file(@duplicate_b, lib_b),
        to_source_file(@duplicate_a, test_a),
        to_source_file(@duplicate_b, test_b)
      ]
      |> run_check(Check, paths: [lib_dir], min_mass: 5)

    assert issues != []
    assert Enum.all?(issues, &String.starts_with?(&1.filename, lib_dir))
  end

  test "detects renamed-variable clones with literal_mode: :abstract" do
    renamed_a = """
    defmodule C do
      def transform(items) do
        items
        |> Enum.map(fn item -> item * 2 end)
        |> Enum.filter(fn item -> item > 10 end)
        |> Enum.sort()
        |> Enum.take(5)
      end
    end
    """

    renamed_b = """
    defmodule D do
      def transform(values) do
        values
        |> Enum.map(fn value -> value * 2 end)
        |> Enum.filter(fn value -> value > 10 end)
        |> Enum.sort()
        |> Enum.take(5)
      end
    end
    """

    issues =
      [
        to_source_file(renamed_a, "c.ex"),
        to_source_file(renamed_b, "d.ex")
      ]
      |> run_check(Check, paths: [], min_mass: 5, literal_mode: :abstract)

    assert length(issues) >= 2
  end

  test "respects excluded_macros" do
    schema_a = """
    defmodule SchemaA do
      use Ecto.Schema

      schema "users" do
        field :name, :string
        field :email, :string
        timestamps()
      end
    end
    """

    schema_b = """
    defmodule SchemaB do
      use Ecto.Schema

      schema "posts" do
        field :title, :string
        field :body, :string
        timestamps()
      end
    end
    """

    issues =
      [
        to_source_file(schema_a, "schema_a.ex"),
        to_source_file(schema_b, "schema_b.ex")
      ]
      |> run_check(Check, paths: [], min_mass: 5, excluded_macros: [:@, :schema])

    schema_issues = Enum.filter(issues, &(&1.message =~ "schema"))
    assert schema_issues == []
  end

  test "message includes type label" do
    issues =
      [
        to_source_file(@duplicate_a, "a.ex"),
        to_source_file(@duplicate_b, "b.ex")
      ]
      |> run_check(Check, paths: [], min_mass: 5)

    assert Enum.all?(issues, &(&1.message =~ "exact" or &1.message =~ "renamed"))
  end

  test "does not emit self-match issues when all fragments resolve to the same location" do
    duplicate = """
    defmodule SameFile do
      def foo(data) do
        data
        |> Enum.map(fn x -> x * 2 end)
        |> Enum.filter(fn x -> x > 10 end)
        |> Enum.sort()
        |> Enum.take(5)
      end

      def bar(data) do
        data
        |> Enum.map(fn x -> x * 2 end)
        |> Enum.filter(fn x -> x > 10 end)
        |> Enum.sort()
        |> Enum.take(5)
      end
    end
    """

    issues =
      [to_source_file(duplicate, "same_file.ex")]
      |> run_check(Check, paths: [], min_mass: 5)

    refute Enum.any?(issues, fn issue ->
             issue.line_no == 0 and String.contains?(issue.message, "also in .")
           end)
  end

  test "does not emit line 0 issues for reduced reports from issue #1" do
    reduced = """
    defmodule Example.A do
      defp organization_tone(:government), do: "purple"
      defp organization_tone(:business), do: "blue"
      defp organization_tone(:individual), do: "green"
      defp organization_tone(:non_profit), do: "orange"
      defp organization_tone(:event), do: "pink"
      defp organization_tone(:chamber), do: "indigo"
    end

    defmodule Example.B do
      defp encode_csv_row(fields) do
        fields
        |> Enum.map_join(",", &escape_csv_field/1)
      end

      defp escape_csv_field(value), do: to_string(value)
    end
    """

    issues =
      [to_source_file(reduced, "issue_1_reduced.ex")]
      |> run_check(Check, paths: [], min_mass: 30, literal_mode: :abstract)

    refute Enum.any?(issues, &(&1.line_no == 0))
    refute Enum.any?(issues, &String.contains?(&1.message, "also in ."))
  end

  describe "cache param" do
    @describetag :tmp_dir

    test "reuses the previous result and still maps issues to source files", %{tmp_dir: dir} do
      cache_path = Path.join(dir, ".ex_dna_cache")
      sources = [to_source_file(@duplicate_a, "a.ex"), to_source_file(@duplicate_b, "b.ex")]
      params = [paths: [], min_mass: 5, cache: true, cache_path: cache_path]

      first = run_check(sources, Check, params)
      assert length(first) >= 2
      assert File.exists?(cache_path)

      second = run_check(sources, Check, params)

      assert Enum.map(second, &{&1.filename, &1.line_no}) ==
               Enum.map(first, &{&1.filename, &1.line_no})
    end
  end

  describe "on_error param" do
    # Credo keeps source text in ETS; storing nil there makes analysis of that
    # one file crash while the AST is still valid, exercising isolation.
    defp broken_source_file do
      source_file = to_source_file("defmodule Broken, do: nil", "broken.ex")
      SourceFileSource.put(source_file, nil)
      source_file
    end

    test ":warn skips a file whose analysis crashes and reports the rest" do
      broken = broken_source_file()

      {issues, output} =
        ExUnit.CaptureIO.with_io(:stderr, fn ->
          [to_source_file(@duplicate_a, "a.ex"), to_source_file(@duplicate_b, "b.ex"), broken]
          |> run_check(Check, paths: [], min_mass: 5)
        end)

      assert output =~ "ExDNA skipped broken.ex"
      assert length(issues) >= 2
    end

    test ":raise fails the check with the offending file" do
      broken = broken_source_file()

      assert_raise AnalysisError, ~r/broken\.ex/, fn ->
        [to_source_file(@duplicate_a, "a.ex"), broken]
        |> run_check(Check, paths: [], min_mass: 5, on_error: :raise)
      end
    end
  end
end
