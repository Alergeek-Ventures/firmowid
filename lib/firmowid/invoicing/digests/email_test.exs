defmodule Firmowid.Invoicing.Digests.EmailTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias Firmowid.Invoicing.Digests.Email

  describe "KSeF digest email rendering" do
    test "escapes invoice fields and suggestion labels in HTML fragments" do
      invoice =
        invoice_with_sensitive_fields(%{
          seller_display_name: "<script>alert('seller')</script>",
          items_list: [%{name: "<img src=x onerror=alert(1)>", quantity: "<b>2</b>"}]
        })

      html =
        Email.render_html([invoice],
          invoice_summaries: %{
            invoice.id => %{
              top_suggestions: [
                %{
                  booking_date_label: "<svg onload=alert(1)>",
                  score: 0.96
                }
              ]
            }
          }
        )

      assert html =~ "&lt;script&gt;"
      assert html =~ "&lt;img src=x onerror=alert(1)&gt;"
      assert html =~ "&lt;b&gt;2&lt;/b&gt;"
      assert html =~ "&lt;svg onload=alert(1)&gt;"
      refute html =~ "<script>"
      refute html =~ "<img src=x"
      refute html =~ "<svg onload="
    end

    test "single invoice body shows suggestion placeholders without exposing sensitive values" do
      user = %{email: "admin@example.com"}

      invoice = invoice_with_sensitive_fields(%{invoice_identifier: "FV-KSEF-2026-001"})

      assert {:ok, email} =
               Email.deliver_ksef_invoice_digest(user, [invoice],
                 invoice_summaries: %{
                   invoice.id => %{
                     top_suggestions: [
                       %{booking_date_label: "wczoraj", score: 0.96},
                       %{booking_date_label: "7 dni temu", score: 0.84},
                       %{booking_date_label: "10 dni temu", score: 0.70}
                     ],
                     matched?: false
                   }
                 }
               )

      assert email.subject == "Nowa faktura w Firmowidzie"
      assert email.html_body =~ "<!doctype html>"

      bodies = [email.html_body, email.text_body]

      for body <- bodies do
        assert body =~ "Masz nową fakturę z KSeF"
        assert body =~ "Maksimumowy Sprzedawca"
        assert body =~ "Możliwe przelewy"
        assert body =~ "96%"
        assert body =~ "wczoraj"
        assert body =~ "Abonament workspace × 1"

        refute body =~ invoice.invoice_identifier
        refute body =~ invoice.ksef_number
        refute body =~ invoice.seller_nip
        refute body =~ Decimal.to_string(Money.to_decimal(invoice.amount))
      end
    end

    test "renders placeholders when optional values are absent" do
      user = %{email: "admin@example.com"}

      invoice =
        invoice_with_sensitive_fields(%{
          seller_display_name: nil,
          seller: nil,
          invoice_identifier: nil
        })

      assert {:ok, email} = Email.deliver_ksef_invoice_digest(user, [invoice])

      bodies = [email.html_body, email.text_body]

      for body <- bodies do
        assert body =~ "(bez nazwy)"
        refute body =~ invoice.ksef_number
        refute body =~ invoice.seller_nip
        refute body =~ Decimal.to_string(Money.to_decimal(invoice.amount))
      end
    end

    test "list digest caps displayed invoices and keeps useful masked summaries" do
      user = %{email: "admin@example.com"}

      invoices = [
        invoice_with_sensitive_fields(%{
          id: Ash.UUID.generate(),
          invoice_identifier: "FV-KSEF-AAA",
          seller_display_name: "Alpha"
        }),
        invoice_with_sensitive_fields(%{
          id: Ash.UUID.generate(),
          invoice_identifier: "FV-KSEF-BBB",
          seller_display_name: "Beta"
        }),
        invoice_with_sensitive_fields(%{
          id: Ash.UUID.generate(),
          invoice_identifier: "FV-KSEF-CCC",
          seller_display_name: "Gamma",
          ksef_number: "KSEF-999",
          seller_nip: "7777777777"
        }),
        invoice_with_sensitive_fields(%{
          id: Ash.UUID.generate(),
          invoice_identifier: "FV-KSEF-DDD",
          seller_display_name: "Delta"
        })
      ]

      assert {:ok, email} =
               Email.deliver_ksef_invoice_digest(user, invoices,
                 invoice_summaries: %{
                   Enum.at(invoices, 0).id => %{
                     top_suggestions: [
                       %{booking_date_label: "2 dni temu", score: 0.91},
                       %{booking_date_label: "6 dni temu", score: 0.88}
                     ],
                     matched?: false
                   },
                   Enum.at(invoices, 1).id => %{matched?: true},
                   Enum.at(invoices, 2).id => %{
                     top_suggestions: [
                       %{booking_date_label: "dzisiaj", score: 0.94}
                     ],
                     matched?: false
                   },
                   Enum.at(invoices, 3).id => %{
                     top_suggestions: [
                       %{booking_date_label: "3 dni temu", score: 0.78},
                       %{booking_date_label: "8 dni temu", score: 0.74},
                       %{booking_date_label: "12 dni temu", score: 0.69}
                     ],
                     matched?: false
                   }
                 }
               )

      assert email.subject == "4 nowe faktury w Firmowidzie"

      assert email.html_body =~ "Otwórz faktury w Firmowidzie"
      assert email.html_body =~ "Alpha"
      assert email.html_body =~ "Beta"
      assert email.html_body =~ "Gamma"
      refute email.html_body =~ "Delta"

      assert email.html_body =~ "Jeszcze 1 faktura czeka w Firmowidzie"
      assert email.html_body =~ "Możliwy przelew: 2 dni temu (91%), +1 inny"
      assert email.html_body =~ "niedopasowane"
      assert email.html_body =~ "dopasowane"
      assert email.html_body =~ "Możliwy przelew: dzisiaj (94%)"
      assert email.html_body =~ "Abonament workspace × 1"

      assert email.text_body =~ "Masz 4 nowe faktury z KSeF"
      assert email.text_body =~ "Jeszcze 1 faktura czeka w Firmowidzie"
      assert email.text_body =~ "Możliwy przelew:\n- dzisiaj, 94%"
      assert email.text_body =~ "dopasowane"
      refute email.text_body =~ "Delta"

      for invoice <- invoices do
        refute email.html_body =~ invoice.invoice_identifier
        refute email.html_body =~ invoice.ksef_number
        refute email.html_body =~ invoice.seller_nip
        refute email.html_body =~ Decimal.to_string(Money.to_decimal(invoice.amount))

        refute email.text_body =~ invoice.invoice_identifier
        refute email.text_body =~ invoice.ksef_number
        refute email.text_body =~ invoice.seller_nip
        refute email.text_body =~ Decimal.to_string(Money.to_decimal(invoice.amount))
      end
    end
  end

  defp invoice_with_sensitive_fields(overrides) do
    Map.merge(
      %{
        id: Ash.UUID.generate(),
        seller_display_name: "Maksimumowy Sprzedawca",
        seller: "Fallback Seller",
        invoice_identifier: "FV-KSEF-SECRET-987654",
        ksef_number: "KSEF-SECRET-123456",
        seller_nip: "1234567890",
        amount: Money.new!("PLN", "9876.54"),
        items_list: [
          %{name: "Abonament workspace", quantity: 1},
          %{name: "Integracja KSeF", quantity: 2}
        ]
      },
      overrides
    )
  end
end
