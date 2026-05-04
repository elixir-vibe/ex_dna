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

  ## Advanced tuning

    * `:max_window_size` — maximum number of consecutive sibling functions
      combined into a single fingerprint for cross-module clone detection.
      Higher values catch clones spanning more adjacent functions at the cost
      of more fragments to compare. Must be ≥ 2. Default: `4`.

    * `:mass_tolerance` — maximum relative size difference allowed between
      two fragments for Type-III (fuzzy) comparison. A value of `0.3` means
      fragments are compared only if the smaller is at least 70% the size of
      the larger. Raise toward `0.5` to catch clones between thin wrappers
      and fat implementations. Must be in `(0.0, 1.0]`. Default: `0.3`.


  """

  @defaults %{
    paths: ["lib/"],
    min_mass: 30,
    min_occurrences: 2,
    min_similarity: 1.0,
    max_window_size: 4,
    mass_tolerance: 0.3,
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
          max_window_size: pos_integer(),
          mass_tolerance: float(),
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
    validate_pos_int!(:min_mass, config.min_mass)
    validate_int_gt!(:min_occurrences, config.min_occurrences, 1)
    validate_float_range!(:min_similarity, config.min_similarity, 0.0, 1.0)
    validate_int_gte!(:max_window_size, config.max_window_size, 2)
    validate_float_range_exclusive_min!(:mass_tolerance, config.mass_tolerance, 0.0, 1.0)

    unless config.literal_mode in [:keep, :abstract] do
      raise ArgumentError,
            "literal_mode must be :keep or :abstract, got: #{inspect(config.literal_mode)}"
    end
  end

  defp validate_pos_int!(name, value) do
    unless is_integer(value) and value > 0 do
      raise ArgumentError, "#{name} must be a positive integer, got: #{inspect(value)}"
    end
  end

  defp validate_int_gt!(name, value, min) do
    unless is_integer(value) and value > min do
      raise ArgumentError,
            "#{name} must be an integer greater than #{min}, got: #{inspect(value)}"
    end
  end

  defp validate_int_gte!(name, value, min) do
    unless is_integer(value) and value >= min do
      raise ArgumentError, "#{name} must be an integer >= #{min}, got: #{inspect(value)}"
    end
  end

  defp validate_float_range!(name, value, min, max) do
    unless is_float(value) and value >= min and value <= max do
      raise ArgumentError,
            "#{name} must be a float between #{min} and #{max}, got: #{inspect(value)}"
    end
  end

  defp validate_float_range_exclusive_min!(name, value, min, max) do
    unless is_float(value) and value > min and value <= max do
      raise ArgumentError,
            "#{name} must be a float between #{min} (exclusive) and #{max}, got: #{inspect(value)}"
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
