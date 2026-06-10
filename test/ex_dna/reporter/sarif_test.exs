defmodule ExDNA.Reporter.SARIFTest do
  use ExUnit.Case, async: true

  alias ExDNA.Config
  alias ExDNA.Detection.Clone
  alias ExDNA.Report
  alias ExDNA.Reporter.SARIF

  @output_file "ex_dna.sarif"

  setup do
    on_exit(fn -> File.rm(@output_file) end)
  end

  test "writes valid SARIF 2.1.0 file" do
    clone = %Clone{
      type: :type_i,
      mass: 42,
      similarity: nil,
      suggestion: %{
        kind: :extract_function,
        name: "shared_process",
        params: [],
        body: "",
        call_sites: []
      },
      fragments: [
        %{file: "lib/foo.ex", line: 10, ast: {:ok, [], nil}, mass: 42},
        %{file: "lib/bar.ex", line: 20, ast: {:ok, [], nil}, mass: 42}
      ],
      source_snippets: ["def hello, do: :world", "def hello, do: :world"]
    }

    report = %Report{
      clones: [clone],
      stats: %{
        files_analyzed: 2,
        total_clones: 1,
        total_duplicated_lines: 2,
        type_i_count: 1,
        type_ii_count: 0,
        type_iii_count: 0,
        detection_time_ms: 0
      },
      config: Config.new(paths: ["lib/"], reporters: [])
    }

    SARIF.report(report)

    assert File.exists?(@output_file)
    sarif = @output_file |> File.read!() |> Jason.decode!()

    assert sarif["version"] == "2.1.0"
    assert sarif["$schema"] =~ "sarif"

    [run] = sarif["runs"]
    assert run["tool"]["driver"]["name"] == "ExDNA"
    assert length(run["tool"]["driver"]["rules"]) == 3

    results = run["results"]
    assert length(results) == 2

    [result | _] = results
    assert result["ruleId"] == "ExDNA/type-i"
    assert result["level"] == "warning"
    assert result["message"]["text"] =~ "Exact code clone"
    assert result["message"]["text"] =~ "shared_process()"

    [location] = result["locations"]
    assert location["physicalLocation"]["region"]["startLine"] > 0

    assert length(result["relatedLocations"]) == 1
  end

  test "uses configured output file" do
    output = "custom_ex_dna.sarif"
    on_exit(fn -> File.rm(output) end)

    report = %Report{
      clones: [],
      stats: %{},
      config: Config.new(paths: ["lib/"], reporters: [], output_file: output)
    }

    SARIF.report(report)

    assert File.exists?(output)
  end

  test "renders Type III results with similarity" do
    clone = %Clone{
      type: :type_iii,
      mass: 30,
      similarity: 0.857,
      suggestion: nil,
      fragments: [
        %{file: "lib/a.ex", line: 5, ast: {:ok, [], nil}, mass: 30},
        %{file: "lib/b.ex", line: 10, ast: {:ok, [], nil}, mass: 30}
      ],
      source_snippets: ["code_a", "code_b"]
    }

    report = %Report{
      clones: [clone],
      stats: %{
        files_analyzed: 2,
        total_clones: 1,
        total_duplicated_lines: 2,
        type_i_count: 0,
        type_ii_count: 0,
        type_iii_count: 1,
        detection_time_ms: 0
      },
      config: Config.new(paths: ["lib/"], reporters: [])
    }

    SARIF.report(report)

    sarif = @output_file |> File.read!() |> Jason.decode!()
    [result | _] = sarif["runs"] |> hd() |> Map.get("results")

    assert result["ruleId"] == "ExDNA/type-iii"
    assert result["level"] == "note"
    assert result["message"]["text"] =~ "85.7%"
  end

  test "renders empty report" do
    report = %Report{
      clones: [],
      stats: %{
        files_analyzed: 5,
        total_clones: 0,
        total_duplicated_lines: 0,
        type_i_count: 0,
        type_ii_count: 0,
        type_iii_count: 0,
        detection_time_ms: 0
      },
      config: Config.new(paths: ["lib/"], reporters: [])
    }

    SARIF.report(report)

    sarif = @output_file |> File.read!() |> Jason.decode!()
    assert sarif["runs"] |> hd() |> Map.get("results") == []
  end
end
