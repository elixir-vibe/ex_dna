defmodule ExDNA.CLI.Options do
  @moduledoc false

  def validate_parse!([]), do: :ok

  def validate_parse!(invalid) do
    message = Enum.map_join(invalid, ", ", fn {flag, value} -> "#{flag}=#{value}" end)
    Mix.raise("Invalid option(s): #{message}")
  end

  def literal_mode(opts) do
    if Keyword.has_key?(opts, :literal_mode) do
      case Keyword.fetch!(opts, :literal_mode) do
        "keep" -> :keep
        "abstract" -> :abstract
        mode -> Mix.raise("Invalid literal mode #{inspect(mode)}. Expected keep or abstract")
      end
    end
  end

  def excluded_macros(opts) do
    case Keyword.get_values(opts, :exclude_macro) do
      [] -> nil
      macros -> Enum.map(macros, &String.to_atom/1)
    end
  end

  def ignored_attributes(opts) do
    extra_ignored =
      opts
      |> Keyword.get_values(:ignore_attribute)
      |> Enum.map(&String.to_atom/1)

    if extra_ignored != [] do
      ExDNA.Config.default(:ignored_attributes) ++ extra_ignored
    end
  end

  def explicit_value(opts, key) do
    if Keyword.has_key?(opts, key), do: Keyword.fetch!(opts, key)
  end

  def optional_values(opts, key) do
    case Keyword.get_values(opts, key) do
      [] -> nil
      values -> values
    end
  end

  def maybe_put(opts, _key, nil), do: opts
  def maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
