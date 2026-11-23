defmodule FirmowidWeb.Invoicing.Components.BankTransferModalTest do
  @moduledoc "Checks the copyable transfer fields and that imported invoice text remains data in them."

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
          effective_seller_nip: value,
          effective_seller_address: value,
          effective_account_number: value,
          invoice_identifier: value,
          effective_amount: Money.new(:PLN, "123.45")
        }
      })

    document = LazyHTML.from_fragment(html)
    buttons = LazyHTML.query(document, "[data-copy-text]")
    assert Enum.empty?(LazyHTML.query(document, "img, script"))

    assert [^value, ^value, ^value, ^value, title, "123.45", "PLN"] =
             LazyHTML.attribute(buttons, "data-copy-text")

    assert title =~ value

    # The clipboard hook copies the attribute; no inline handler is rendered.
    assert LazyHTML.attribute(buttons, "phx-hook") == List.duplicate("CopyToClipboard", 7)
    assert LazyHTML.attribute(buttons, "onclick") == []
  end

  test "lists the seller NIP under the recipient and leaves it out when the invoice has none" do
    invoice = %{
      seller: "Acme Sp. z o.o.",
      effective_seller_nip: "1234567890",
      effective_seller_address: "ul. Przykładowa 1, 00-001 Warszawa",
      effective_account_number: "PL00000000000000000000000000",
      invoice_identifier: "FV/1/2026",
      effective_amount: Money.new(:PLN, "-123.45")
    }

    assert invoice |> copy_fields() |> Enum.take(3) == [
             {"Odbiorca", "Acme Sp. z o.o."},
             {"NIP", "1234567890"},
             {"Adres", "ul. Przykładowa 1, 00-001 Warszawa"}
           ]

    labels =
      invoice |> Map.put(:effective_seller_nip, nil) |> copy_fields() |> Enum.map(&elem(&1, 0))

    assert Enum.take(labels, 2) == ["Odbiorca", "Adres"]
    refute "NIP" in labels
  end

  defp copy_fields(invoice) do
    document =
      BankTransferModal
      |> render_component(%{id: "transfer-test", invoice: invoice})
      |> LazyHTML.from_fragment()

    labels =
      document
      |> LazyHTML.query("label")
      |> Enum.map(&LazyHTML.text/1)
      |> Enum.map(&String.trim/1)

    values =
      document |> LazyHTML.query("[data-copy-text]") |> LazyHTML.attribute("data-copy-text")

    Enum.zip(labels, values)
  end
end
