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
  alias IO.ANSI

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
          ANSI.red(),
          "Clone ##{clone_index} not found. ",
          ANSI.reset(),
          "Found #{report.stats.total_clones} clones total.\n"
        ])

      clone ->
        explain_clone(clone, clone_index)
    end
  end

  defp explain_clone(clone, index) do
    IO.puts([
      "\n",
      ANSI.yellow(),
      "═══ Clone ##{index} — Detailed Analysis ",
      String.duplicate("═", 40),
      ANSI.reset(),
      "\n"
    ])

    IO.puts([ANSI.cyan(), "Type: ", ANSI.reset(), format_type(clone.type)])
    IO.puts([ANSI.cyan(), "Mass: ", ANSI.reset(), "#{clone.mass} AST nodes"])

    IO.puts([
      ANSI.cyan(),
      "Locations: ",
      ANSI.reset(),
      "#{length(clone.fragments)} occurrences\n"
    ])

    Enum.each(clone.fragments, fn frag ->
      IO.puts(["  • ", ANSI.faint(), "#{frag.file}:#{frag.line}", ANSI.reset()])
    end)

    if length(clone.fragments) >= 2 do
      [frag_a, frag_b | _] = clone.fragments

      ast_a = Normalizer.strip_metadata(frag_a.ast)
      ast_b = Normalizer.strip_metadata(frag_b.ast)

      {pattern, holes} = AntiUnifier.anti_unify(ast_a, ast_b)

      IO.puts([
        "\n",
        ANSI.yellow(),
        "─── Common Structure ",
        String.duplicate("─", 42),
        ANSI.reset(),
        "\n"
      ])

      pattern |> Macro.to_string() |> print_code()

      if holes != [] do
        IO.puts([
          "\n",
          ANSI.yellow(),
          "─── Divergence Points (#{length(holes)} holes) ",
          String.duplicate("─", 30),
          ANSI.reset(),
          "\n"
        ])

        Enum.each(holes, fn hole ->
          [val_a, val_b] = hole.values

          IO.puts([
            "  ",
            ANSI.magenta(),
            "#{hole.var}",
            ANSI.reset()
          ])

          IO.puts([
            "    fragment A: ",
            ANSI.faint(),
            Macro.to_string(val_a),
            ANSI.reset()
          ])

          IO.puts([
            "    fragment B: ",
            ANSI.faint(),
            Macro.to_string(val_b),
            ANSI.reset(),
            "\n"
          ])
        end)
      end

      if clone.suggestion do
        IO.puts([
          ANSI.yellow(),
          "─── Suggested Refactoring ",
          String.duplicate("─", 37),
          ANSI.reset(),
          "\n"
        ])

        print_suggestion(clone.suggestion)
      end
    end

    IO.puts("")
  end

  defp print_suggestion(%{kind: :extract_function} = s) do
    params = Enum.join(s.params, ", ")
    IO.puts([ANSI.green(), "  defp #{s.name}(#{params}) do", ANSI.reset()])

    s.body
    |> String.split("\n")
    |> Enum.each(fn line ->
      IO.puts([ANSI.green(), "    #{line}", ANSI.reset()])
    end)

    IO.puts([ANSI.green(), "  end", ANSI.reset(), "\n"])

    IO.puts([ANSI.cyan(), "  Call sites:", ANSI.reset(), "\n"])

    Enum.each(s.call_sites, fn site ->
      IO.puts([
        "    ",
        ANSI.faint(),
        "#{site.file}:#{site.line} → #{site.call}",
        ANSI.reset()
      ])
    end)
  end

  defp print_code(code) do
    code
    |> String.split("\n")
    |> Enum.each(fn line ->
      IO.puts(["  ", ANSI.faint(), line, ANSI.reset()])
    end)
  end

  defp format_type(:type_i), do: "exact (Type I)"
  defp format_type(:type_ii), do: "renamed (Type II)"
  defp format_type(:type_iii), do: "near-miss (Type III)"
end
