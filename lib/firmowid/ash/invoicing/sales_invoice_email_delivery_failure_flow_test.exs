defmodule Firmowid.Ash.Invoicing.SalesInvoiceEmailDeliveryFailureFlowTest do
  @moduledoc false
  use Firmowid.DataCase

  import Firmowid.AccountsFixtures
  import Firmowid.Test.Support.SalesInvoiceEmailTestHelpers

  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.SalesInvoice.Dispatchers.Communication
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor

  setup_all do
    configure_test_adapters()
  end

  describe "email delivery failure flow" do
    test "email job failure flow before final retry does not persist failed delivery" do
      admin = admin_fixture()
      processor_scope = processor_scope(admin.organization_id)
      counterparty = invalid_email_counterparty_fixture!(admin)

      invoice =
        sales_invoice_fixture!(admin, %{
          counterparty_id: counterparty.id,
          should_send_emails: true
        })

      assert {:error, _reason} =
               perform_sales_invoice_email_job(invoice, :basic, attempt: 1, max_attempts: 2)

      assert [] == email_deliveries_for(invoice, processor_scope)
    end

    test "final email job failure flow persists a complete failed delivery" do
      admin = admin_fixture()
      processor_scope = processor_scope(admin.organization_id)
      counterparty = invalid_email_counterparty_fixture!(admin)

      invoice =
        sales_invoice_fixture!(admin, %{
          counterparty_id: counterparty.id,
          should_send_emails: true
        })

      assert {:cancel, _reason} =
               perform_sales_invoice_email_job(invoice, :basic, attempt: 2, max_attempts: 2)

      [delivery] = email_deliveries_for(invoice, processor_scope)

      assert_failed_delivery(delivery, %{
        sales_invoice_id: invoice.id,
        delivery_type: :basic,
        recipient_email: counterparty.email
      })
    end

    test "failed delivery flow does not block non-reminder invoice emails" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        admin = admin_fixture()
        processor_scope = processor_scope(admin.organization_id)
        counterparty = valid_counterparty_fixture!(admin)

        invoice =
          sales_invoice_fixture!(admin, %{
            counterparty_id: counterparty.id,
            should_send_emails: true
          })

        failed_at = DateTime.shift(DateTime.utc_now(:second), minute: -1)

        seed_email_delivery!(invoice, %{
          delivery_type: :reminder,
          status: :failed,
          recipient_email: counterparty.email,
          error_message: "Previous reminder failed",
          failed_at: failed_at
        })

        confirmed_invoice = confirm_invoice_in_ksef!(invoice, processor_scope)

        assert {:ok, :dispatched} =
                 Communication.dispatch(confirmed_invoice, :ksef_confirmed, processor_scope)

        assert_enqueued_email_job(confirmed_invoice, :basic)
        assert :ok = perform_sales_invoice_email_job(confirmed_invoice, :basic)

        [failed_delivery, sent_delivery] =
          email_deliveries_for(confirmed_invoice, processor_scope)

        assert_failed_delivery(failed_delivery, %{
          sales_invoice_id: confirmed_invoice.id,
          delivery_type: :reminder,
          recipient_email: counterparty.email
        })

        assert_sent_delivery(sent_delivery, %{
          sales_invoice_id: confirmed_invoice.id,
          delivery_type: :basic,
          recipient_email: counterparty.email
        })
      end)
    end
  end

  defp scope_for(user), do: %Scope{actor: user, tenant: user.organization_id}

  defp processor_scope(organization_id) do
    %Scope{
      actor: %SystemActor{org_id: organization_id, role: :sales_invoice_processor},
      tenant: organization_id
    }
  end

  defp invalid_email_counterparty_fixture!(user, attrs \\ %{}) do
    valid_counterparty_fixture!(user, Map.merge(%{email: "invalid-email"}, attrs))
  end

  defp sales_invoice_fixture!(user, attrs) do
    attrs = Map.merge(base_invoice_attrs(), attrs)
    Invoicing.create_sales_invoice!(attrs, scope: scope_for(user))
  end

  defp confirm_invoice_in_ksef!(invoice, scope) do
    Invoicing.update_sales_invoice_ksef_fields!(
      invoice,
      %{
        ksef_number: "KSEF-#{System.unique_integer([:positive])}",
        ksef_invoice_checksum: "verified-hash-#{System.unique_integer([:positive])}",
        locked_at: DateTime.utc_now(:second)
      },
      scope: scope
    )
  end

  defp assert_failed_delivery(delivery, expected) do
    assert delivery.sales_invoice_id == expected.sales_invoice_id
    assert delivery.delivery_type == expected.delivery_type
    assert delivery.recipient_email == expected.recipient_email
    assert delivery.status == :failed
    assert %DateTime{} = delivery.failed_at
    assert is_nil(delivery.sent_at)
    assert is_nil(delivery.resend_email_id)
    assert is_binary(delivery.error_message)
    assert delivery.error_message != ""
  end
end
