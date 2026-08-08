defmodule Mix.Tasks.Compile.ExDnaTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Compile.ExDna

  test "is registered under the documented compiler name" do
    assert Mix.Task.get("compile.ex_dna") == ExDna
  end

  test "declares its cache manifest" do
    assert ExDna.manifests() == [".ex_dna_cache"]
  end
end
