defmodule Firmowid.ErrorKindTest do
  @moduledoc false

  use ExUnit.Case, async: true

  test "classifies values without exposing their contents" do
    assert Firmowid.ErrorKind.classify(%RuntimeError{}) == "Elixir.RuntimeError"
    assert Firmowid.ErrorKind.classify({:error, :timeout}) == "error:timeout"
    assert Firmowid.ErrorKind.classify("private") == "binary"
  end
end
