defmodule Mix.Tasks.Compile.ExDna do
  @shortdoc "Detect code duplication incrementally"
  @moduledoc """
  Runs ExDNA clone detection as part of `mix compile`.

  Configure the compiler in `mix.exs`:

      compilers: Mix.compilers() ++ [:ex_dna]
  """

  use Mix.Task.Compiler

  alias ExDNA.Config

  @impl true
  def run(argv), do: ExDNA.Compiler.run(argv)

  @impl true
  def manifests, do: [Config.new([]).cache_path]

  @impl true
  def clean do
    cache_path = Config.new([]).cache_path
    File.rm(cache_path)
    :ok
  end
end
