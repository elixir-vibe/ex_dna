defmodule Mix.Tasks.ExDnaTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Error
  alias Mix.Tasks.ExDna
  alias Mix.Tasks.ExDna.Explain

  setup do
    dir = Path.join(System.tmp_dir!(), "ex_dna_task_test_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  test "raises a Mix error when clones exceed the budget", %{dir: dir} do
    write_duplicate_pair(dir)

    output =
      capture_io(fn ->
        error =
          assert_raise Error, fn ->
            ExDna.run(["--min-mass", "5", dir])
          end

        assert Exception.message(error) =~ "ExDNA found"
      end)

    assert output =~ "code duplication report"
  end

  test "does not raise when clones are within the configured budget", %{dir: dir} do
    write_duplicate_pair(dir)

    capture_io(fn ->
      assert is_nil(ExDna.run(["--min-mass", "5", "--max-clones", "10", dir]))
    end)
  end

  test "does not raise when file is ignored in config", %{dir: dir} do
    write_duplicate_pair(dir)

    capture_io(fn ->
      File.cd!(dir, fn ->
        File.write!(Path.join(dir, ".ex_dna.exs"), ~s/%{ignore: ["b.ex"]}/)
        assert is_nil(ExDna.run(["--min-mass", "5", File.cwd!()]))
      end)
    end)
  end

  test "does not override config paths when no path is passed", %{dir: dir} do
    write_duplicate_pair(dir)

    capture_io(fn ->
      File.cd!(dir, fn ->
        File.write!(Path.join(dir, ".ex_dna.exs"), ~s/%{paths: ["."], ignore: ["b.ex"]}/)
        assert is_nil(ExDna.run(["--min-mass", "5"]))
      end)
    end)
  end

  test "raises a Mix error for invalid format" do
    error =
      assert_raise Error, fn ->
        ExDna.run(["--format", "xml"])
      end

    assert Exception.message(error) =~ "Invalid format"
  end

  test "cached JSON preserves clone groups and explicit paths", %{dir: dir} do
    write_duplicate_pair(dir)

    {first, second} =
      File.cd!(dir, fn ->
        argv = [
          "--cache",
          "--format",
          "json",
          "--min-mass",
          "5",
          "--max-clones",
          "10",
          dir
        ]

        {capture_io(fn -> ExDna.run(argv) end), capture_io(fn -> ExDna.run(argv) end)}
      end)

    first = Jason.decode!(first)
    second = Jason.decode!(second)

    assert first["clones"] != []
    assert second["clones"] == first["clones"]
    assert second["stats"]["files_analyzed"] == 2
    assert File.regular?(Path.join(dir, ".ex_dna_cache"))
  end

  test "raises a Mix error for invalid explain option" do
    error =
      assert_raise Error, fn ->
        Explain.run(["--unknown"])
      end

    assert Exception.message(error) =~ "Invalid option"
  end

  test "explain accepts a clone index followed by paths", %{dir: dir} do
    write_duplicate_pair(dir)

    output =
      capture_io(fn ->
        Explain.run(["1", "--min-mass", "5", dir])
      end)

    assert output =~ "Clone #1"
    assert output =~ "Detailed Analysis"
  end

  test "explain respects ignored files in config", %{dir: dir} do
    write_duplicate_pair(dir)

    output =
      capture_io(fn ->
        File.cd!(dir, fn ->
          File.write!(Path.join(dir, ".ex_dna.exs"), ~s/%{ignore: ["b.ex"]}/)
          Explain.run(["1", "--min-mass", "5"])
        end)
      end)

    assert output =~ "Found 0 clones total"
  end

  defp write_duplicate_pair(dir) do
    File.write!(Path.join(dir, "a.ex"), duplicate_module("A"))
    File.write!(Path.join(dir, "b.ex"), duplicate_module("B"))
  end

  defp duplicate_module(name) do
    """
    defmodule #{name} do
      def process(data) do
        data
        |> Enum.map(fn x -> x * 2 end)
        |> Enum.filter(fn x -> x > 10 end)
        |> Enum.sort()
        |> Enum.take(5)
      end
    end
    """
  end
end
