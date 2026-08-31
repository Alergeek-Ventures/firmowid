defmodule Firmowid.Ash.Timetracker.DelegationExpenseExtractorTest do
  use ExUnit.Case, async: false

  alias Firmowid.Ash.Timetracker.DelegationExpenseExtractor

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

  test "uses type-specific samples when Reducto is unavailable" do
    assert %{document_number: "TRANSPORT-001", expense_amount: transport_amount} =
             DelegationExpenseExtractor.extract("/tmp/bilet.pdf", :transport)

    assert %{document_number: "NOCLEG-001", expense_amount: accommodation_amount} =
             DelegationExpenseExtractor.extract("/tmp/nocleg.pdf", :accommodation)

    assert %{document_number: "INNE-001", expense_amount: other_amount} =
             DelegationExpenseExtractor.extract("/tmp/inne.pdf", :other)

    assert Money.equal?(transport_amount, Money.new(:PLN, "36.20"))
    assert Money.equal?(accommodation_amount, Money.new(:PLN, "530.20"))
    assert Money.equal?(other_amount, Money.new(:PLN, "78.00"))
  end

  defp restore_env(key, nil), do: Application.delete_env(:firmowid, key)
  defp restore_env(key, value), do: Application.put_env(:firmowid, key, value)
end
