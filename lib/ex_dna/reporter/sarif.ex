defmodule ExDNA.Reporter.SARIF do
  @moduledoc """
  Outputs clone detection results in SARIF 2.1.0 format.

  SARIF (Static Analysis Results Interchange Format) is an OASIS standard
  supported by GitHub Code Scanning, VS Code, and other security/quality tools.

  Writes `ex_dna.sarif` to the current directory.
  """

  @behaviour ExDNA.Reporter

  @output_file "ex_dna.sarif"
  @schema_uri "https://json.schemastore.org/sarif-2.1.0.json"
  @info_uri "https://github.com/elixir-vibe/ex_dna"

  @impl true
  def report(%ExDNA.Report{clones: clones, config: config}) do
    sarif = %{
      "$schema": @schema_uri,
      version: "2.1.0",
      runs: [build_run(clones)]
    }

    output_file = config.output_file || @output_file

    sarif
    |> Jason.encode!(pretty: true)
    |> then(&File.write!(output_file, &1))

    IO.puts("  SARIF report written to #{output_file}")
    :ok
  end

  defp build_run(clones) do
    rules = build_rules()

    %{
      tool: %{
        driver: %{
          name: "ExDNA",
          version: to_string(Application.spec(:ex_dna, :vsn) || "dev"),
          informationUri: @info_uri,
          rules: rules
        }
      },
      results: Enum.flat_map(clones, &clone_to_results/1)
    }
  end

  defp build_rules do
    [
      %{
        id: "ExDNA/type-i",
        name: "ExactClone",
        shortDescription: %{text: "Exact code clone (Type I)"},
        fullDescription: %{
          text:
            "Identical code fragments (modulo whitespace and comments). These can typically be extracted into a shared function."
        },
        defaultConfiguration: %{level: "warning"},
        helpUri: @info_uri
      },
      %{
        id: "ExDNA/type-ii",
        name: "RenamedClone",
        shortDescription: %{text: "Renamed code clone (Type II)"},
        fullDescription: %{
          text: "Structurally identical code with renamed variables or different literal values."
        },
        defaultConfiguration: %{level: "warning"},
        helpUri: @info_uri
      },
      %{
        id: "ExDNA/type-iii",
        name: "NearMissClone",
        shortDescription: %{text: "Near-miss code clone (Type III)"},
        fullDescription: %{
          text:
            "Structurally similar code with minor modifications (added, removed, or changed statements)."
        },
        defaultConfiguration: %{level: "note"},
        helpUri: @info_uri
      }
    ]
  end

  defp clone_to_results(clone) do
    rule_id = rule_id(clone.type)
    other_locations = Enum.map(clone.fragments, &fragment_location/1)

    Enum.map(clone.fragments, fn frag ->
      others =
        other_locations
        |> Enum.reject(fn loc ->
          loc.physicalLocation.artifactLocation.uri == relative_uri(frag.file) and
            loc.physicalLocation.region.startLine == frag.line
        end)

      %{
        ruleId: rule_id,
        level: level(clone.type),
        message: %{text: build_message(clone, frag, others)},
        locations: [fragment_location(frag)],
        relatedLocations: index_locations(others)
      }
    end)
  end

  defp fragment_location(frag) do
    %{
      physicalLocation: %{
        artifactLocation: %{
          uri: relative_uri(frag.file),
          uriBaseId: "%SRCROOT%"
        },
        region: %{
          startLine: max(frag.line, 1)
        }
      }
    }
  end

  defp index_locations(locations) do
    locations
    |> Enum.with_index()
    |> Enum.map(fn {loc, idx} ->
      loc
      |> Map.put(:id, idx)
      |> Map.put(:message, %{text: "Also duplicated here"})
    end)
  end

  defp build_message(clone, _frag, others) do
    type_label =
      case clone.type do
        :type_i -> "Exact"
        :type_ii -> "Renamed"
        :type_iii -> "Near-miss (#{Float.round((clone.similarity || 0.0) * 100, 1)}%)"
      end

    suggestion =
      case clone.suggestion do
        %{kind: :extract_function, name: name} -> " → extract #{name}()"
        %{kind: :extract_macro, name: name} -> " → extract macro #{name}"
        _ -> ""
      end

    locations =
      Enum.map_join(others, ", ", fn loc ->
        "#{loc.physicalLocation.artifactLocation.uri}:#{loc.physicalLocation.region.startLine}"
      end)

    "#{type_label} code clone (#{clone.mass} nodes) also in: #{locations}#{suggestion}"
  end

  defp rule_id(:type_i), do: "ExDNA/type-i"
  defp rule_id(:type_ii), do: "ExDNA/type-ii"
  defp rule_id(:type_iii), do: "ExDNA/type-iii"

  defp level(:type_i), do: "warning"
  defp level(:type_ii), do: "warning"
  defp level(:type_iii), do: "note"

  defp relative_uri(path) do
    Path.relative_to_cwd(path)
  end
end
