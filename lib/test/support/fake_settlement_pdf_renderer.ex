defmodule Firmowid.Test.Support.FakeSettlementPdfRenderer do
  @moduledoc "Test renderer that returns a minimal PDF binary without starting Chromium."

  @doc false
  @spec render(binary()) :: {:ok, binary()}
  def render(_html), do: {:ok, "%PDF-1.4 test settlement"}
end
