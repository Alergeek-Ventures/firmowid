defmodule Firmowid.Ash.Invoicing.Digests.EmailTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias Firmowid.Ash.Invoicing.Digests.Email

  describe "KSeF digest email rendering" do
    test "single invoice body shows suggestion placeholders without exposing sensitive values" do
      user = %{email: "admin@example.com"}
      digest = %{}

      invoice = invoice_with_sensitive_fields(%{invoice_identifier: "FV-KSEF-2026-001"})

      assert {:ok, email} =
               Email.deliver_ksef_invoice_digest(user, digest, [invoice],
                 invoice_summaries: %{
                   invoice.id => %{
                     suggestions_count: 3,
                     top_prediction_score: 0.86,
                     top_suggestions: [
                       %{booking_date_label: "wczoraj", score: 0.96, avatar_color: "#D9E7F7"},
                       %{booking_date_label: "7 dni temu", score: 0.84, avatar_color: "#D9E7F7"},
                       %{booking_date_label: "10 dni temu", score: 0.70, avatar_color: "#D9E7F7"}
                     ],
                     amount_placeholder: "•••• zł",
                     matched?: false
                   }
                 }
               )

      assert email.subject == "Nowa faktura w Firmowidzie"
      assert email.html_body =~ "<!doctype html>"
      assert email.html_body =~ "alt=\"Firmowid\""
      assert email.html_body =~ "Pozdrawiamy,<br>Zespół Firmowid"

      bodies = [email.html_body, email.text_body]

      for body <- bodies do
        assert body =~ "Masz nową fakturę z KSeF"
        assert body =~ "Maksimumowy Sprzedawca"
        assert body =~ "Firmowid znalazł 3 możliwe dopasowania transakcji"
        assert body =~ "96% pewności"
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
      digest = %{}

      invoice =
        invoice_with_sensitive_fields(%{
          seller_display_name: nil,
          seller: nil,
          invoice_identifier: nil
        })

      assert {:ok, email} = Email.deliver_ksef_invoice_digest(user, digest, [invoice])

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
      digest = %{}

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
               Email.deliver_ksef_invoice_digest(user, digest, invoices,
                 invoice_summaries: %{
                   Enum.at(invoices, 0).id => %{
                     suggestions_count: 2,
                     top_prediction_score: 0.89,
                     top_suggestions: [
                       %{booking_date_label: "2 dni temu", score: 0.91, avatar_color: "#E6D8F5"},
                       %{booking_date_label: "6 dni temu", score: 0.88, avatar_color: "#E6D8F5"}
                     ],
                     amount_placeholder: "•••• zł",
                     matched?: false
                   },
                   Enum.at(invoices, 1).id => %{matched?: true},
                   Enum.at(invoices, 2).id => %{
                     suggestions_count: 1,
                     top_prediction_score: 0.94,
                     top_suggestions: [
                       %{booking_date_label: "dzisiaj", score: 0.94, avatar_color: "#D6ECE7"}
                     ],
                     amount_placeholder: "•••• EUR",
                     matched?: false
                   },
                   Enum.at(invoices, 3).id => %{
                     suggestions_count: 5,
                     top_prediction_score: 0.78,
                     top_suggestions: [
                       %{booking_date_label: "3 dni temu", score: 0.78, avatar_color: "#F4E7C6"},
                       %{booking_date_label: "8 dni temu", score: 0.74, avatar_color: "#F4E7C6"},
                       %{booking_date_label: "12 dni temu", score: 0.69, avatar_color: "#F4E7C6"}
                     ],
                     amount_placeholder: "•••• zł",
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

      assert email.html_body =~ "+ 1 faktura więcej czeka w Firmowidzie"
      assert email.html_body =~ "Firmowid znalazł 2 możliwe dopasowania transakcji"
      assert email.html_body =~ "niedopasowane"
      assert email.html_body =~ "dopasowane"
      assert email.html_body =~ "91% pewności"
      assert email.html_body =~ "dzisiaj"
      assert email.html_body =~ "Abonament workspace × 1"

      assert email.text_body =~ "Masz 4 nowe faktury z KSeF"
      assert email.text_body =~ "+ 1 faktura więcej czeka w Firmowidzie"
      assert email.text_body =~ "Firmowid znalazł 1 możliwe dopasowanie transakcji"
      assert email.text_body =~ "💳 dzisiaj — 94% pewności"
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
