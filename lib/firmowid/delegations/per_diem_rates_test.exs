defmodule Firmowid.Delegations.PerDiemRatesTest do
  use ExUnit.Case, async: true

  alias Firmowid.Delegations.PerDiemRates

  # Calls the Sejm ELI API. Excluded by default; run with `mix check --external`.
  @moduletag :external

  test "the regulation has not changed since the rate table was updated" do
    source = PerDiemRates.source()
    act = Req.get!("https://api.sejm.gov.pl/eli/acts/#{source.act}").body

    assert act["inForce"] == "IN_FORCE"
    assert Enum.sort(ids(act, "Akty zmieniające")) == Enum.sort(source.amending_acts)
    assert ids(act, "Inf. o tekście jednolitym") == [source.consolidated_text]
  end

  defp ids(act, reference), do: Enum.map(act["references"][reference] || [], & &1["id"])
end
