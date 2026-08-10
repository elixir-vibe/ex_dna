defmodule ExDNA.CacheTest do
  use ExUnit.Case, async: true

  alias ExDNA.{Cache, Config}

  @moduletag :tmp_dir
  setup %{tmp_dir: tmp_dir} do
    cache_path = Path.join(tmp_dir, "test_cache")
    {:ok, cache_path: cache_path}
  end

  describe "write/3 and read/2" do
    test "round-trips source digests and clone results", %{cache_path: path} do
      state = %{digests: %{"lib/foo.ex" => <<1>>}, clones: [%{type: :type_i}]}

      assert :ok = Cache.write(state, path)
      assert Cache.read(path) == state
    end

    test "creates the cache directory", %{tmp_dir: dir} do
      path = Path.join([dir, "nested", "cache", "results"])
      state = %{digests: %{}, clones: []}

      assert :ok = Cache.write(state, path)
      assert Cache.read(path) == state
    end

    test "returns empty state when the file does not exist", %{cache_path: path} do
      assert Cache.read(path) == %{digests: %{}, clones: nil}
    end

    test "returns empty state when the file is corrupt", %{cache_path: path} do
      File.write!(path, "not a valid term")
      assert Cache.read(path) == %{digests: %{}, clones: nil}
    end

    test "returns empty state when cache version mismatches", %{cache_path: path} do
      binary = :erlang.term_to_binary({999, <<>>, %{}, []})
      File.write!(path, binary)
      assert Cache.read(path) == %{digests: %{}, clones: nil}
    end

    test "invalidates output-shaping config changes", %{cache_path: path} do
      original = Config.new(reporters: [])
      changed = Config.new(reporters: [], min_occurrences: 3)
      state = %{digests: %{}, clones: []}

      assert :ok = Cache.write(state, path, Cache.config_hash(original))
      assert Cache.read(path, Cache.config_hash(original)) == state
      assert Cache.read(path, Cache.config_hash(changed)) == %{digests: %{}, clones: nil}
    end
  end

  describe "source_digests/1" do
    test "changes with contents even when mtime is unchanged", %{tmp_dir: dir} do
      file = Path.join(dir, "changed.ex")
      File.write!(file, "defmodule A, do: nil")
      mtime = File.stat!(file, time: :posix).mtime
      original = Cache.source_digests([file])

      File.write!(file, "defmodule B, do: nil")
      File.touch!(file, mtime)

      refute Cache.source_digests([file]) == original
    end

    test "captures additions and removals", %{tmp_dir: dir} do
      first = Path.join(dir, "first.ex")
      second = Path.join(dir, "second.ex")
      File.write!(first, "defmodule First, do: nil")
      File.write!(second, "defmodule Second, do: nil")

      assert Map.keys(Cache.source_digests([first, second])) |> Enum.sort() ==
               Enum.sort([first, second])

      assert Map.keys(Cache.source_digests([first])) == [first]
    end
  end

  describe "file_digest/1" do
    test "returns a digest for an existing file", %{tmp_dir: dir} do
      file = Path.join(dir, "exists.ex")
      File.write!(file, "ok")

      assert is_binary(Cache.file_digest(file))
      assert byte_size(Cache.file_digest(file)) == 32
    end

    test "returns nil for a missing file" do
      assert Cache.file_digest("/nonexistent/path.ex") == nil
    end
  end
end
