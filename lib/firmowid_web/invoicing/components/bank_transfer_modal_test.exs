defmodule FirmowidWeb.Invoicing.Components.BankTransferModalTest do
  @moduledoc "Checks that imported invoice text remains data in clipboard controls."

  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias FirmowidWeb.Invoicing.Components.BankTransferModal

  test "quotes, markup and newlines stay in data attributes, not executable JavaScript" do
    value = "O'Connor');window.__invoice_xss = true;//\n<img src=x onerror=alert(1)>"

    html =
      render_component(BankTransferModal, %{
        id: "transfer-test",
        invoice: %{
          seller: value,
          effective_seller_address: value,
          effective_account_number: value,
          invoice_identifier: value,
          effective_amount: Money.new(:PLN, "123.45")
        }
      })

    document = LazyHTML.from_fragment(html)
    buttons = LazyHTML.query(document, "[data-copy-value]")
    assert Enum.empty?(LazyHTML.query(document, "img, script"))

    assert [^value, ^value, ^value, title, "123.45", "PLN"] =
             LazyHTML.attribute(buttons, "data-copy-value")

    assert title =~ value

    assert LazyHTML.attribute(buttons, "onclick") ==
             List.duplicate("navigator.clipboard.writeText(this.dataset.copyValue)", 6)
  end
end
