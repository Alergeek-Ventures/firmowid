defmodule Firmowid.Ash.Delegations.DelegationExpenseExtractorTest do
  use ExUnit.Case, async: false

  alias Firmowid.Ash.Delegations.DelegationExpenseExtractor

  defmodule UnavailableReductoClient do
    @moduledoc false

    def extract_file(_path, _schema, _options), do: {:error, :unavailable}
  end

  setup do
    previous_client = Application.get_env(:firmowid, :reducto_api_client_module)
    previous_enabled = Application.get_env(:firmowid, :delegation_expense_extraction_enabled)
    Application.put_env(:firmowid, :reducto_api_client_module, UnavailableReductoClient)
    Application.put_env(:firmowid, :delegation_expense_extraction_enabled, true)

    on_exit(fn ->
      restore_env(:reducto_api_client_module, previous_client)
      restore_env(:delegation_expense_extraction_enabled, previous_enabled)
    end)
  end

  test "leaves fields blank when Reducto is unavailable" do
    assert %{} = DelegationExpenseExtractor.extract("/tmp/bilet.pdf", :transport)
    assert %{} = DelegationExpenseExtractor.extract("/tmp/nocleg.pdf", :accommodation)
    assert %{} = DelegationExpenseExtractor.extract("/tmp/inne.pdf", :other)
  end

  test "leaves fields blank when extraction is disabled" do
    Application.put_env(:firmowid, :delegation_expense_extraction_enabled, false)

    assert %{} = DelegationExpenseExtractor.extract("/tmp/bilet.pdf", :transport)
  end

  defp restore_env(key, nil), do: Application.delete_env(:firmowid, key)
  defp restore_env(key, value), do: Application.put_env(:firmowid, key, value)
end
