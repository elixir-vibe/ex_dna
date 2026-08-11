defmodule ExDNATest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  setup do
    dir = Path.join(System.tmp_dir!(), "ex_dna_test_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  describe "suppression comments" do
    test "compile without module attribute warnings" do
      module = Module.concat(__MODULE__, "Suppressed#{System.unique_integer([:positive])}")

      warnings =
        capture_io(:stderr, fn ->
          Code.compile_string("""
          defmodule #{module} do
            # ex_dna:disable-for-next-line
            def intentional_duplicate, do: :ok
          end
          """)
        end)

      refute warnings =~ "module attribute"
    end
  end

  describe "analyze/1" do
    test "accepts a path string", %{dir: dir} do
      File.write!(Path.join(dir, "empty.ex"), """
      defmodule Empty do
      end
      """)

      report = ExDNA.analyze(paths: [dir], reporters: [])
      assert %ExDNA.Report{} = report
      assert report.stats.total_clones == 0
    end

    test "accepts keyword options", %{dir: dir} do
      File.write!(Path.join(dir, "opt.ex"), """
      defmodule Opt do
        def foo, do: :ok
      end
      """)

      report = ExDNA.analyze(paths: [dir], min_mass: 5, reporters: [])
      assert %ExDNA.Report{} = report
    end

    test "cache preserves the normal report", %{dir: dir} do
      for name <- ~w(a.ex b.ex) do
        File.write!(Path.join(dir, name), """
        defmodule #{name |> Path.rootname() |> Macro.camelize()} do
          def duplicated(value) do
            value
            |> Enum.map(&to_string/1)
            |> Enum.sort()
          end
        end
        """)
      end

      cache_path = Path.join(dir, ".ex_dna_cache")

      opts = [
        paths: [dir],
        reporters: [],
        min_mass: 5,
        cache: true,
        cache_path: cache_path
      ]

      first = ExDNA.analyze(opts)
      second = ExDNA.analyze(opts)

      assert first.clones != []
      assert second.clones == first.clones
      assert second.stats.files_analyzed == first.stats.files_analyzed
      assert File.regular?(cache_path)
    end
  end
end
