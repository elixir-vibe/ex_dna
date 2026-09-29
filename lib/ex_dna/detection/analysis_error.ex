defmodule ExDNA.Detection.AnalysisError do
  @moduledoc """
  Raised when analysis of a single file crashes and `:on_error` is `:raise`.

  Per-file work runs in isolated tasks, so a crash surfaces here as an
  `{exception, stacktrace}` or other exit reason attached to the file that
  triggered it.
  """

  defexception [:file, :reason]

  @type t :: %__MODULE__{file: String.t(), reason: term()}

  @impl true
  def message(%__MODULE__{file: file, reason: reason}) do
    "ExDNA failed to analyze #{file}: " <> Exception.format_exit(reason)
  end
end
