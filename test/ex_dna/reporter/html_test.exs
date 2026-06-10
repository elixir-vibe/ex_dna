defmodule ExDNA.Reporter.HTMLTest do
  use ExUnit.Case, async: true

  alias ExDNA.Config
  alias ExDNA.Detection.Clone
  alias ExDNA.Report
  alias ExDNA.Reporter.HTML

  @output_file "ex_dna_report.html"

  setup do
    on_exit(fn -> File.rm(@output_file) end)
  end

  test "writes HTML report file with expected content" do
    clone = %Clone{
      type: :type_i,
      mass: 42,
      similarity: nil,
      suggestion: nil,
      fragments: [
        %{file: "lib/foo.ex", line: 10, ast: {:ok, [], nil}, mass: 42},
        %{file: "lib/bar.ex", line: 20, ast: {:ok, [], nil}, mass: 42}
      ],
      source_snippets: [
        "def hello do\n  :world\nend",
        "def hello do\n  :world\nend"
      ]
    }

    report = %Report{
      clones: [clone],
      stats: %{
        files_analyzed: 5,
        total_clones: 1,
        total_duplicated_lines: 6,
        type_i_count: 1,
        type_ii_count: 0,
        type_iii_count: 0,
        detection_time_ms: 0
      },
      config: Config.new(paths: ["lib/"], reporters: [])
    }

    HTML.report(report)

    assert File.exists?(@output_file)
    html = File.read!(@output_file)

    assert html =~ "<!DOCTYPE html>"
    assert html =~ "ExDNA"
    assert html =~ "Files analyzed"
    assert html =~ "badge-i"
    assert html =~ "lib/foo.ex:10"
    assert html =~ "lib/bar.ex:20"
    assert html =~ ":world"
    assert html =~ "42 nodes"
    assert html =~ "file://"
  end

  test "uses configured output file" do
    output = "custom_ex_dna_report.html"
    on_exit(fn -> File.rm(output) end)

    report = %Report{
      clones: [],
      stats: %{
        files_analyzed: 0,
        total_clones: 0,
        total_duplicated_lines: 0,
        type_i_count: 0,
        type_ii_count: 0,
        type_iii_count: 0,
        detection_time_ms: 0
      },
      config: Config.new(paths: ["lib/"], reporters: [], output_file: output)
    }

    HTML.report(report)

    assert File.exists?(output)
  end

  test "renders Type II and Type III badges" do
    make_clone = fn type ->
      %Clone{
        type: type,
        mass: 10,
        similarity: if(type == :type_iii, do: 0.857, else: nil),
        suggestion: nil,
        fragments: [%{file: "lib/a.ex", line: 1, ast: {:ok, [], nil}, mass: 10}],
        source_snippets: ["def a, do: :ok"]
      }
    end

    report = %Report{
      clones: [make_clone.(:type_ii), make_clone.(:type_iii)],
      stats: %{
        files_analyzed: 1,
        total_clones: 2,
        total_duplicated_lines: 2,
        type_i_count: 0,
        type_ii_count: 1,
        type_iii_count: 1,
        detection_time_ms: 0
      },
      config: Config.new(paths: ["lib/"], reporters: [])
    }

    HTML.report(report)

    html = File.read!(@output_file)
    assert html =~ "badge-ii"
    assert html =~ "badge-iii"
    assert html =~ "85.7%"
  end

  test "renders suggestion section" do
    clone = %Clone{
      type: :type_i,
      mass: 30,
      similarity: nil,
      fragments: [
        %{file: "lib/a.ex", line: 1, ast: {:ok, [], nil}, mass: 30},
        %{file: "lib/b.ex", line: 5, ast: {:ok, [], nil}, mass: 30}
      ],
      source_snippets: ["def a, do: :ok"],
      suggestion: %{
        kind: :extract_function,
        name: "shared_hello",
        params: [:arg1, :arg2],
        body: "def shared_hello(arg1, arg2), do: arg1 + arg2",
        call_sites: [
          %{file: "lib/a.ex", line: 1, call: "shared_hello(1, 2)"},
          %{file: "lib/b.ex", line: 5, call: "shared_hello(3, 4)"}
        ]
      }
    }

    report = %Report{
      clones: [clone],
      stats: %{
        files_analyzed: 2,
        total_clones: 1,
        total_duplicated_lines: 1,
        type_i_count: 1,
        type_ii_count: 0,
        type_iii_count: 0,
        detection_time_ms: 0
      },
      config: Config.new(paths: ["lib/"], reporters: [])
    }

    HTML.report(report)

    html = File.read!(@output_file)
    assert html =~ "Extract function"
    assert html =~ "shared_hello"
    assert html =~ "arg1, arg2"
  end

  test "renders empty report" do
    report = %Report{
      clones: [],
      stats: %{
        files_analyzed: 3,
        total_clones: 0,
        total_duplicated_lines: 0,
        type_i_count: 0,
        type_ii_count: 0,
        type_iii_count: 0,
        detection_time_ms: 0
      },
      config: Config.new(paths: ["lib/"], reporters: [])
    }

    HTML.report(report)

    html = File.read!(@output_file)
    assert html =~ "No code duplication detected"
  end
end
