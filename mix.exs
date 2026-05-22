defmodule ExDNA.MixProject do
  use Mix.Project

  @version "1.5.2"
  @source_url "https://github.com/elixir-vibe/ex_dna"

  def project do
    [
      app: :ex_dna,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "ExDNA",
      description: "Code duplication detector powered by Elixir AST analysis",
      source_url: @source_url,
      docs: docs(),
      package: package(),
      aliases: aliases(),
      dialyzer: [
        plt_file: {:no_warn, "_build/dev/dialyxir_plt.plt"},
        plt_add_apps: [:mix, :credo]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.0"},
      {:gen_lsp, "~> 0.11", optional: true},
      {:makeup, "~> 1.0", optional: true},
      {:makeup_elixir, "~> 0.14 or ~> 1.0", optional: true},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", optional: true},
      {:ex_slop, "~> 0.4", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "LICENSE"]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib mix.exs README.md LICENSE .formatter.exs)
    ]
  end

  def cli do
    [preferred_envs: [ci: :test]]
  end

  defp aliases do
    [
      ci: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "cmd mix credo --strict",
        "cmd mix test",
        "cmd mix dialyzer",
        "cmd mix ex_dna"
      ]
    ]
  end
end
