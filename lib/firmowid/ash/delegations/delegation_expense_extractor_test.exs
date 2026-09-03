defmodule Firmowid.Ash.Delegations.DelegationExpenseExtractorTest do
  use ExUnit.Case, async: false

  alias Firmowid.Ash.Delegations.DelegationExpenseExtractor

  defmodule UnavailableReductoClient do
    @moduledoc false

    def extract_file(_path, _schema, _options), do: {:error, :unavailable}
  end

  setup do
    previous_client = Application.get_env(:firmowid, :reducto_api_client_module)
    Application.put_env(:firmowid, :reducto_api_client_module, UnavailableReductoClient)

    on_exit(fn ->
      restore_env(:reducto_api_client_module, previous_client)
    end)
  end

  test "returns the Reducto error when extraction is unavailable" do
    for expense_type <- [:transport, :accommodation, :other] do
      assert {:error, :unavailable} =
               DelegationExpenseExtractor.extract("/tmp/document.pdf", expense_type)
    end
  end

  defp restore_env(key, nil), do: Application.delete_env(:firmowid, key)
  defp restore_env(key, value), do: Application.put_env(:firmowid, key, value)
end
