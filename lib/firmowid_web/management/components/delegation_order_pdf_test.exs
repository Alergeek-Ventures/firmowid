defmodule FirmowidWeb.Management.Components.DelegationOrderPdfTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FirmowidWeb.Management.Components.DelegationOrderPdf

  test "renders public transport in a delegation order" do
    html =
      render_component(&DelegationOrderPdf.order/1,
        employee: %{name: "Jan Kowalski", email: "jan@example.com"},
        employment_contract: %{position: "Programista"},
        delegation: %{
          reference: "JK-2026-09-1",
          inserted_at: ~U[2026-09-01 12:00:00Z],
          start_date: ~D[2026-09-10],
          end_date: ~D[2026-09-11],
          destination: "Krakow",
          transport_types: [:public_transport],
          purpose: "Spotkanie z klientem",
          advance_amount: Money.new(:PLN, 0)
        },
        footer_logo_data_uri: "data:image/png;base64,"
      )

    assert html =~ "komunikacja publiczna"
  end
end
