defmodule ExDNA.ConfigTest do
  use ExUnit.Case, async: false

  alias ExDNA.Config

  describe "new/1" do
    test "applies defaults" do
      config = Config.new([])
      assert config.min_mass == 30
      assert config.min_occurrences == 2
      assert config.min_similarity == 1.0
      assert config.paths == ["lib/"]
      assert config.excluded_macros == []
      assert config.parse_timeout == 5_000
      assert config.normalize_pipes == false
    end

    test "overrides defaults with provided options" do
      config = Config.new(min_mass: 10, normalize_pipes: true, excluded_macros: [:@, :schema])

      assert config.min_mass == 10
      assert config.normalize_pipes == true
      assert config.excluded_macros == [:@, :schema]
    end

    test "loads config file when present" do
      dir =
        Path.join(System.tmp_dir!(), "ex_dna_config_test_#{:erlang.unique_integer([:positive])}")

      File.mkdir_p!(dir)
      config_path = Path.join(dir, ".ex_dna.exs")
      File.write!(config_path, "%{min_mass: 15, excluded_macros: [:schema, :plug]}")

      original_cwd = File.cwd!()
      File.cd!(dir)

      try do
        config = Config.new([])
        assert config.min_mass == 15
        assert config.excluded_macros == [:schema, :plug]
      after
        File.cd!(original_cwd)
        File.rm_rf!(dir)
      end
    end

    test "CLI options override config file" do
      dir =
        Path.join(System.tmp_dir!(), "ex_dna_config_test_#{:erlang.unique_integer([:positive])}")

      File.mkdir_p!(dir)
      config_path = Path.join(dir, ".ex_dna.exs")
      File.write!(config_path, "%{min_mass: 15}")

      original_cwd = File.cwd!()
      File.cd!(dir)

      try do
        config = Config.new(min_mass: 50)
        assert config.min_mass == 50
      after
        File.cd!(original_cwd)
        File.rm_rf!(dir)
      end
    end
  end
end
