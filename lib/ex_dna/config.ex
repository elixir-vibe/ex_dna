defmodule ExDNA.Config do
  @moduledoc """
  Configuration for ExDNA.

  Options can be provided in three layers (later wins):

  1. Built-in defaults
  2. `.ex_dna.exs` config file in the project root
  3. Keyword options passed to `ExDNA.analyze/1` or CLI flags

  ## Config file

  Create `.ex_dna.exs` in your project root:

      %{
        min_mass: 25,
        min_occurrences: 3,
        ignore: ["lib/my_app_web/templates/**"],
        excluded_macros: [:schema, :pipe_through, :plug],
        normalize_pipes: true
      }

  The file is evaluated with `Code.eval_file/1` and must return a map.
  """

  @defaults %{
    paths: ["lib/"],
    min_mass: 30,
    min_occurrences: 2,
    min_similarity: 1.0,
    ignore: [],
    reporters: [ExDNA.Reporter.Console],
    literal_mode: :keep,
    normalize_pipes: false,
    excluded_macros: [],
    ignored_attributes: [
      :moduledoc,
      :doc,
      :typedoc,
      :type,
      :typep,
      :opaque,
      :spec,
      :callback,
      :macrocallback,
      :impl,
      :behaviour,
      :optional_callbacks,
      :deprecated,
      :derive,
      :enforce_keys,
      :before_compile,
      :after_compile,
      :after_verify,
      :compile,
      :dialyzer,
      :external_resource,
      :on_load,
      :on_definition,
      :vsn,
      :no_clone
    ],
    parse_timeout: 5_000
  }

  defstruct Map.keys(@defaults)

  @type literal_mode :: :keep | :abstract
  @type t :: %__MODULE__{
          paths: [String.t()],
          min_mass: pos_integer(),
          min_occurrences: pos_integer(),
          min_similarity: float(),
          ignore: [String.t()],
          reporters: [module()],
          literal_mode: literal_mode(),
          normalize_pipes: boolean(),
          excluded_macros: [atom()],
          ignored_attributes: [atom()],
          parse_timeout: pos_integer()
        }

  @spec new(keyword()) :: t()
  def new(opts) do
    file_opts = load_config_file()

    attrs =
      @defaults
      |> Map.merge(file_opts)
      |> Map.merge(Map.new(opts))

    config = struct!(__MODULE__, attrs)
    validate!(config)
    config
  end

  @spec default(atom()) :: term()
  def default(key), do: Map.fetch!(@defaults, key)

  defp validate!(config) do
    unless is_integer(config.min_mass) and config.min_mass > 0 do
      raise ArgumentError, "min_mass must be a positive integer, got: #{inspect(config.min_mass)}"
    end

    unless is_integer(config.min_occurrences) and config.min_occurrences > 1 do
      raise ArgumentError,
            "min_occurrences must be an integer greater than 1, got: #{inspect(config.min_occurrences)}"
    end

    unless is_float(config.min_similarity) and config.min_similarity >= 0.0 and
             config.min_similarity <= 1.0 do
      raise ArgumentError,
            "min_similarity must be a float between 0.0 and 1.0, got: #{inspect(config.min_similarity)}"
    end

    unless config.literal_mode in [:keep, :abstract] do
      raise ArgumentError,
            "literal_mode must be :keep or :abstract, got: #{inspect(config.literal_mode)}"
    end
  end

  defp load_config_file do
    path = Path.join(File.cwd!(), ".ex_dna.exs")

    if File.regular?(path) do
      {config, _binding} = Code.eval_file(path)

      unless is_map(config) do
        raise "#{path} must return a map, got: #{inspect(config)}"
      end

      config
    else
      %{}
    end
  end
end
