defmodule Mix.Tasks.ExDna.Explain do
  @shortdoc "Show detailed analysis for a specific clone"
  @moduledoc """
  Deep-dive into a specific clone, showing the anti-unification result,
  the common structure, the divergence points (holes), and the suggested
  refactoring.

      $ mix ex_dna.explain 1
      $ mix ex_dna.explain 1 --min-mass 10

  The clone number comes from `mix ex_dna` output.
  """

  use Mix.Task

  alias ExDNA.AST.{AntiUnifier, Normalizer}
  alias ExDNA.CLI.Options

  @impl Mix.Task
  def run(argv) do
    {opts, args, _} =
      OptionParser.parse(argv,
        strict: [
          min_mass: :integer,
          min_occurrences: :integer,
          min_similarity: :float,
          literal_mode: :string,
          normalize_pipes: :boolean,
          ignore: :keep
        ],
        aliases: [m: :min_mass, o: :min_occurrences, s: :min_similarity, i: :ignore]
      )

    clone_index =
      case args do
        [n | _] -> String.to_integer(n)
        _ -> 1
      end

    literal_mode =
      case Keyword.get(opts, :literal_mode, "keep") do
        "abstract" -> :abstract
        _ -> :keep
      end

    config_opts =
      [
        reporters: [],
        literal_mode: literal_mode,
        normalize_pipes: Keyword.get(opts, :normalize_pipes, false)
      ]
      |> Options.maybe_put(:ignore, Options.optional_values(opts, :ignore))
      |> Options.maybe_put(:min_mass, Keyword.get(opts, :min_mass))
      |> Options.maybe_put(:min_occurrences, Keyword.get(opts, :min_occurrences))
      |> Options.maybe_put(:min_similarity, Keyword.get(opts, :min_similarity))

    report = ExDNA.analyze(config_opts)

    case Enum.at(report.clones, clone_index - 1) do
      nil ->
        IO.puts([
          "\n",
          IO.ANSI.red(),
          "Clone ##{clone_index} not found. ",
          IO.ANSI.reset(),
          "Found #{report.stats.total_clones} clones total.\n"
        ])

      clone ->
        explain_clone(clone, clone_index)
    end
  end

  defp explain_clone(clone, index) do
    IO.puts([
      "\n",
      IO.ANSI.yellow(),
      "═══ Clone ##{index} — Detailed Analysis ",
      String.duplicate("═", 40),
      IO.ANSI.reset(),
      "\n"
    ])

    IO.puts([IO.ANSI.cyan(), "Type: ", IO.ANSI.reset(), format_type(clone.type)])
    IO.puts([IO.ANSI.cyan(), "Mass: ", IO.ANSI.reset(), "#{clone.mass} AST nodes"])

    IO.puts([
      IO.ANSI.cyan(),
      "Locations: ",
      IO.ANSI.reset(),
      "#{length(clone.fragments)} occurrences\n"
    ])

    Enum.each(clone.fragments, fn frag ->
      IO.puts(["  • ", IO.ANSI.faint(), "#{frag.file}:#{frag.line}", IO.ANSI.reset()])
    end)

    if length(clone.fragments) >= 2 do
      [frag_a, frag_b | _] = clone.fragments

      ast_a = Normalizer.strip_metadata(frag_a.ast)
      ast_b = Normalizer.strip_metadata(frag_b.ast)

      {pattern, holes} = AntiUnifier.anti_unify(ast_a, ast_b)

      IO.puts([
        "\n",
        IO.ANSI.yellow(),
        "─── Common Structure ",
        String.duplicate("─", 42),
        IO.ANSI.reset(),
        "\n"
      ])

      pattern |> Macro.to_string() |> print_code()

      if holes != [] do
        IO.puts([
          "\n",
          IO.ANSI.yellow(),
          "─── Divergence Points (#{length(holes)} holes) ",
          String.duplicate("─", 30),
          IO.ANSI.reset(),
          "\n"
        ])

        Enum.each(holes, fn hole ->
          [val_a, val_b] = hole.values

          IO.puts([
            "  ",
            IO.ANSI.magenta(),
            "#{hole.var}",
            IO.ANSI.reset()
          ])

          IO.puts([
            "    fragment A: ",
            IO.ANSI.faint(),
            Macro.to_string(val_a),
            IO.ANSI.reset()
          ])

          IO.puts([
            "    fragment B: ",
            IO.ANSI.faint(),
            Macro.to_string(val_b),
            IO.ANSI.reset(),
            "\n"
          ])
        end)
      end

      if clone.suggestion do
        IO.puts([
          IO.ANSI.yellow(),
          "─── Suggested Refactoring ",
          String.duplicate("─", 37),
          IO.ANSI.reset(),
          "\n"
        ])

        print_suggestion(clone.suggestion)
      end
    end

    IO.puts("")
  end

  defp print_suggestion(%{kind: :extract_function} = s) do
    params = Enum.join(s.params, ", ")
    IO.puts([IO.ANSI.green(), "  defp #{s.name}(#{params}) do", IO.ANSI.reset()])

    s.body
    |> String.split("\n")
    |> Enum.each(fn line ->
      IO.puts([IO.ANSI.green(), "    #{line}", IO.ANSI.reset()])
    end)

    IO.puts([IO.ANSI.green(), "  end", IO.ANSI.reset(), "\n"])

    IO.puts([IO.ANSI.cyan(), "  Call sites:", IO.ANSI.reset(), "\n"])

    Enum.each(s.call_sites, fn site ->
      IO.puts([
        "    ",
        IO.ANSI.faint(),
        "#{site.file}:#{site.line} → #{site.call}",
        IO.ANSI.reset()
      ])
    end)
  end

  defp print_code(code) do
    code
    |> String.split("\n")
    |> Enum.each(fn line ->
      IO.puts(["  ", IO.ANSI.faint(), line, IO.ANSI.reset()])
    end)
  end

  defp format_type(:type_i), do: "exact (Type I)"
  defp format_type(:type_ii), do: "renamed (Type II)"
  defp format_type(:type_iii), do: "near-miss (Type III)"
end
