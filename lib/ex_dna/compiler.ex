defmodule ExDNA.Compiler do
  @moduledoc """
  A `Mix.Task.Compiler` that runs clone detection incrementally.

  On first run every source file is analyzed and the clone result is cached.
  On subsequent compilations source digests determine whether that result can
  be returned immediately or normal analysis needs to run again.

  ## Setup

  Add `:ex_dna` to the compilers list in your `mix.exs`:

      def project do
        [compilers: Mix.compilers() ++ [:ex_dna]]
      end

  The cache is stored in `.ex_dna_cache` and should be added to `.gitignore`.
  """

  use Mix.Task.Compiler

  alias ExDNA.Config
  alias ExDNA.Detection.CachedDetector

  @impl true
  def run(argv) do
    config = Config.new([])
    force? = "--force" in argv or "--force-ex_dna" in argv
    {status, clones, _files_analyzed} = CachedDetector.run(config, force: force?)
    {status, diagnostics(clones)}
  end

  defp diagnostics(clones) do
    Enum.flat_map(clones, fn clone ->
      Enum.map(clone.fragments, fn fragment ->
        %Mix.Task.Compiler.Diagnostic{
          file: fragment.file,
          position: fragment.line,
          message: "Code clone detected (#{clone.type}, mass: #{clone.mass})",
          severity: :warning,
          compiler_name: "ExDNA"
        }
      end)
    end)
  end
end
