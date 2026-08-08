defmodule Mix.Tasks.Compile.ExDna do
  @shortdoc "Detect code duplication incrementally"
  @moduledoc """
  Runs ExDNA clone detection as part of `mix compile`.

  Configure the compiler in `mix.exs`:

      compilers: Mix.compilers() ++ [:ex_dna]
  """

  use Mix.Task.Compiler

  alias ExDNA.Cache

  @impl true
  def run(argv), do: ExDNA.Compiler.run(argv)

  @impl true
  def manifests, do: [Cache.default_path()]

  @impl true
  def clean do
    cache_path = Cache.default_path()
    File.rm(cache_path)
    :ok
  end
end
