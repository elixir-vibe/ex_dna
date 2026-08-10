defmodule ExDNA.CompilerTest do
  use ExUnit.Case, async: true

  alias ExDNA.{Cache, Config, Incremental}

  @moduletag :tmp_dir
  setup %{tmp_dir: dir} do
    cache_path = Path.join(dir, ".ex_dna_cache")
    write_duplicate_files(dir)

    config = Config.new(paths: [dir], reporters: [], min_mass: 5)
    {:ok, cache_path: cache_path, config: config, dir: dir}
  end

  test "an unchanged analysis returns cached clone groups", %{
    cache_path: cache_path,
    config: config
  } do
    assert {:ok, clones, 2} = Incremental.run(config, cache_path: cache_path)
    assert clones != []

    assert {:noop, ^clones, 2} = Incremental.run(config, cache_path: cache_path)
  end

  test "same-mtime content changes refresh analysis", %{
    cache_path: cache_path,
    config: config,
    dir: dir
  } do
    assert {:ok, clones, 2} = Incremental.run(config, cache_path: cache_path)
    assert clones != []

    file = Path.join(dir, "dup_b.ex")
    mtime = File.stat!(file, time: :posix).mtime
    File.write!(file, "defmodule Unique, do: nil")
    File.touch!(file, mtime)

    assert {:ok, [], 2} = Incremental.run(config, cache_path: cache_path)
  end

  test "removed files refresh analysis", %{cache_path: cache_path, config: config, dir: dir} do
    assert {:ok, clones, 2} = Incremental.run(config, cache_path: cache_path)
    assert clones != []

    File.rm!(Path.join(dir, "dup_b.ex"))

    assert {:ok, [], 1} = Incremental.run(config, cache_path: cache_path)
  end

  test "force refreshes an unchanged analysis", %{cache_path: cache_path, config: config} do
    assert {:ok, clones, 2} = Incremental.run(config, cache_path: cache_path)
    assert {:ok, refreshed, 2} = Incremental.run(config, cache_path: cache_path, force: true)

    assert clone_signatures(refreshed) == clone_signatures(clones)
  end

  test "cache stores clone results and source digests", %{
    cache_path: cache_path,
    config: config
  } do
    assert {:ok, _clones, 2} = Incremental.run(config, cache_path: cache_path)

    cached = Cache.read(cache_path, Cache.config_hash(config))
    assert cached.clones != []
    assert map_size(cached.digests) == 2
  end

  test "cache write failures do not fail analysis", %{config: config, dir: dir} do
    cache_path = Path.join(dir, "cache_directory")
    File.mkdir_p!(cache_path)

    assert {:ok, clones, 2} = Incremental.run(config, cache_path: cache_path)
    assert clones != []
  end

  defp write_duplicate_files(dir) do
    for name <- ~w(dup_a.ex dup_b.ex) do
      File.write!(Path.join(dir, name), """
      defmodule #{String.replace(name, ".ex", "") |> Macro.camelize()} do
        def process(data) do
          data
          |> Enum.map(fn x -> x * 2 end)
          |> Enum.filter(fn x -> x > 10 end)
          |> Enum.sort()
          |> Enum.take(5)
        end
      end
      """)
    end
  end

  defp clone_signatures(clones) do
    clones
    |> Enum.map(&{&1.type, &1.mass})
    |> Enum.sort()
  end
end
