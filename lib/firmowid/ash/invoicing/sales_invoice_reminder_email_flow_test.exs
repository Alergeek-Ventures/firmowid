defmodule Firmowid.Ash.Invoicing.SalesInvoiceReminderEmailFlowTest do
  @moduledoc false
  use Firmowid.DataCase

  import Firmowid.AccountsFixtures
  import Firmowid.Test.Support.SalesInvoiceEmailTestHelpers

  alias Firmowid.Ash.Finances.BankAccount
  alias Firmowid.Ash.Finances.Transaction
  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoiceTransaction
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor

  setup_all do
    configure_test_adapters()
  end

  describe "sales invoice reminder email flow" do
    test "overdue unpaid latest invoice flow sends the first reminder" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        admin = admin_fixture()
        processor_scope = processor_scope(admin.organization_id)
        counterparty = valid_counterparty_fixture!(admin)

        invoice =
          confirmed_sales_invoice_fixture!(admin, processor_scope, %{
            counterparty_id: counterparty.id,
            should_send_emails: true,
            due_date: Date.add(Date.utc_today(), -1)
          })

        assert 1 == run_reminder_scan!(processor_scope)
        assert_enqueued_email_job(invoice, :reminder)
        assert :ok = perform_sales_invoice_email_job(invoice, :reminder)

        [delivery] = email_deliveries_for(invoice, processor_scope)

        assert_sent_delivery(delivery, %{
          sales_invoice_id: invoice.id,
          delivery_type: :reminder,
          recipient_email: counterparty.email
        })
      end)
    end

    test "invoice due today or later flow does not send a reminder" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        admin = admin_fixture()
        processor_scope = processor_scope(admin.organization_id)
        counterparty = valid_counterparty_fixture!(admin)

        due_today =
          confirmed_sales_invoice_fixture!(admin, processor_scope, %{
            counterparty_id: counterparty.id,
            should_send_emails: true,
            due_date: Date.utc_today()
          })

        due_later =
          confirmed_sales_invoice_fixture!(admin, processor_scope, %{
            counterparty_id: counterparty.id,
            should_send_emails: true,
            due_date: Date.add(Date.utc_today(), 1)
          })

        assert 0 == run_reminder_scan!(processor_scope)
        refute_enqueued_email_job(due_today, :reminder)
        refute_enqueued_email_job(due_later, :reminder)
        assert [] == email_deliveries_for(due_today, processor_scope)
        assert [] == email_deliveries_for(due_later, processor_scope)
      end)
    end

    test "sent reminder cadence flow waits seven days before sending another reminder" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        admin = admin_fixture()
        processor_scope = processor_scope(admin.organization_id)
        counterparty = valid_counterparty_fixture!(admin)

        recent_invoice =
          confirmed_sales_invoice_fixture!(admin, processor_scope, %{
            counterparty_id: counterparty.id,
            should_send_emails: true,
            due_date: Date.add(Date.utc_today(), -10)
          })

        due_invoice =
          confirmed_sales_invoice_fixture!(admin, processor_scope, %{
            counterparty_id: counterparty.id,
            should_send_emails: true,
            due_date: Date.add(Date.utc_today(), -10)
          })

        seed_sent_reminder!(recent_invoice, DateTime.shift(DateTime.utc_now(:second), day: -6))
        seed_sent_reminder!(due_invoice, DateTime.shift(DateTime.utc_now(:second), week: -1))

        assert 1 == run_reminder_scan!(processor_scope)
        refute_enqueued_email_job(recent_invoice, :reminder)
        assert_enqueued_email_job(due_invoice, :reminder)
        assert :ok = perform_sales_invoice_email_job(due_invoice, :reminder)

        assert [:reminder] == delivery_types_for(recent_invoice, processor_scope)
        assert [:reminder, :reminder] == delivery_types_for(due_invoice, processor_scope)
      end)
    end

    test "paid invoice flow does not send a reminder" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        admin = admin_fixture()
        processor_scope = processor_scope(admin.organization_id)
        counterparty = valid_counterparty_fixture!(admin)

        invoice =
          confirmed_sales_invoice_fixture!(admin, processor_scope, %{
            counterparty_id: counterparty.id,
            should_send_emails: true,
            due_date: Date.add(Date.utc_today(), -1)
          })

        paid_transaction_fixture!(admin, invoice)

        assert 0 == run_reminder_scan!(processor_scope)
        refute_enqueued_email_job(invoice, :reminder)
        assert [] == email_deliveries_for(invoice, processor_scope)
      end)
    end

    test "invoice without KSeF number flow does not send a reminder" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        admin = admin_fixture()
        processor_scope = processor_scope(admin.organization_id)
        counterparty = valid_counterparty_fixture!(admin)

        invoice =
          sales_invoice_fixture!(admin, %{
            counterparty_id: counterparty.id,
            should_send_emails: true,
            due_date: Date.add(Date.utc_today(), -1)
          })

        assert 0 == run_reminder_scan!(processor_scope)
        refute_enqueued_email_job(invoice, :reminder)
        assert [] == email_deliveries_for(invoice, processor_scope)
      end)
    end

    test "skipped invoice flow does not send a reminder" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        admin = admin_fixture()
        processor_scope = processor_scope(admin.organization_id)
        counterparty = valid_counterparty_fixture!(admin)

        invoice =
          confirmed_sales_invoice_fixture!(admin, processor_scope, %{
            counterparty_id: counterparty.id,
            should_send_emails: true,
            due_date: Date.add(Date.utc_today(), -1),
            skip_invoicing: true
          })

        assert 0 == run_reminder_scan!(processor_scope)
        refute_enqueued_email_job(invoice, :reminder)
        assert [] == email_deliveries_for(invoice, processor_scope)
      end)
    end

    test "correction chain flow sends reminder only for latest invoice" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        admin = admin_fixture()
        processor_scope = processor_scope(admin.organization_id)
        counterparty = valid_counterparty_fixture!(admin)

        original =
          confirmed_sales_invoice_fixture!(admin, processor_scope, %{
            counterparty_id: counterparty.id,
            should_send_emails: true,
            due_date: Date.add(Date.utc_today(), -10)
          })

        correction =
          admin
          |> sales_invoice_correction_fixture!(original, %{
            should_send_emails: true,
            due_date: Date.add(Date.utc_today(), -1)
          })
          |> confirm_invoice_in_ksef!(processor_scope, correction_locked_at())

        assert 1 == run_reminder_scan!(processor_scope)
        refute_enqueued_email_job(original, :reminder)
        assert_enqueued_email_job(correction, :reminder)
        assert :ok = perform_sales_invoice_email_job(correction, :reminder)

        assert [] == delivery_types_for(original, processor_scope)
        assert [:reminder] == delivery_types_for(correction, processor_scope)
      end)
    end

    test "correction flow resets reminder cadence from the original invoice" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        admin = admin_fixture()
        processor_scope = processor_scope(admin.organization_id)
        counterparty = valid_counterparty_fixture!(admin)

        original =
          confirmed_sales_invoice_fixture!(admin, processor_scope, %{
            counterparty_id: counterparty.id,
            should_send_emails: true,
            due_date: Date.add(Date.utc_today(), -10)
          })

        seed_sent_reminder!(original, DateTime.shift(DateTime.utc_now(:second), day: -1))

        correction =
          admin
          |> sales_invoice_correction_fixture!(original, %{
            should_send_emails: true,
            due_date: Date.add(Date.utc_today(), -1)
          })
          |> confirm_invoice_in_ksef!(processor_scope, correction_locked_at())

        assert 1 == run_reminder_scan!(processor_scope)
        refute_enqueued_email_job(original, :reminder)
        assert_enqueued_email_job(correction, :reminder)
        assert :ok = perform_sales_invoice_email_job(correction, :reminder)

        assert [:reminder] == delivery_types_for(original, processor_scope)
        assert [:reminder] == delivery_types_for(correction, processor_scope)
      end)
    end

    test "latest failed delivery flow blocks reminder email" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        admin = admin_fixture()
        processor_scope = processor_scope(admin.organization_id)
        counterparty = valid_counterparty_fixture!(admin)

        invoice =
          confirmed_sales_invoice_fixture!(admin, processor_scope, %{
            counterparty_id: counterparty.id,
            should_send_emails: true,
            due_date: Date.add(Date.utc_today(), -1)
          })

        seed_email_delivery!(invoice, %{
          delivery_type: :basic,
          status: :failed,
          recipient_email: counterparty.email,
          error_message: "Previous delivery failed",
          failed_at: DateTime.utc_now(:second)
        })

        assert 0 == run_reminder_scan!(processor_scope)
        refute_enqueued_email_job(invoice, :reminder)
        assert [:basic] == delivery_types_for(invoice, processor_scope)
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

  defp sales_invoice_fixture!(user, attrs) do
    attrs = Map.merge(base_invoice_attrs(), attrs)
    Invoicing.create_sales_invoice!(attrs, scope: scope_for(user))
  end

  defp confirmed_sales_invoice_fixture!(user, processor_scope, attrs) do
    user
    |> sales_invoice_fixture!(attrs)
    |> confirm_invoice_in_ksef!(processor_scope)
  end

  defp sales_invoice_correction_fixture!(user, original, attrs) do
    attrs =
      Map.merge(
        %{
          original_invoice_id: original.id,
          invoice_number: "FK/#{System.unique_integer([:positive])}",
          issue_date: Date.utc_today(),
          sale_date: Date.utc_today(),
          due_date: Date.add(Date.utc_today(), -1),
          correction_reason: "Reminder flow test correction",
          sales_invoice_items: [base_item_attrs(%{name: "Corrected service"})]
        },
        attrs
      )

    Invoicing.create_sales_invoice_correction!(attrs, scope: scope_for(user))
  end

  defp confirm_invoice_in_ksef!(invoice, scope, locked_at \\ DateTime.utc_now(:second)) do
    Invoicing.update_sales_invoice_ksef_fields!(
      invoice,
      %{
        ksef_number: "KSEF-#{System.unique_integer([:positive])}",
        ksef_invoice_checksum: "verified-hash-#{System.unique_integer([:positive])}",
        locked_at: locked_at
      },
      scope: scope
    )
  end

  defp correction_locked_at do
    DateTime.shift(DateTime.utc_now(:second), second: 10)
  end

  defp run_reminder_scan!(scope) do
    SalesInvoice.dispatch_overdue_sales_invoice_reminders!(scope: scope)
  end

  defp seed_sent_reminder!(invoice, sent_at) do
    seed_email_delivery!(invoice, %{
      delivery_type: :reminder,
      status: :sent,
      recipient_email: "billing@example.com",
      resend_email_id: "resend-#{System.unique_integer([:positive])}",
      sent_at: sent_at
    })
  end

  defp paid_transaction_fixture!(user, invoice) do
    bank_account =
      Ash.Seed.seed!(BankAccount, %{
        organization_id: user.organization_id,
        iban: "PL#{[:positive] |> System.unique_integer() |> Integer.to_string() |> String.pad_leading(26, "0")}",
        institution_name: "Manual",
        owner_name: "Test Owner",
        currency: invoice.currency,
        name: "Payment account #{System.unique_integer([:positive])}",
        is_default: false
      })

    transaction =
      Ash.Seed.seed!(Transaction, %{
        organization_id: user.organization_id,
        bank_account_id: bank_account.id,
        transaction_id: "tx-#{System.unique_integer([:positive])}",
        internal_transaction_id: "internal-tx-#{System.unique_integer([:positive])}",
        creditor_name: invoice.seller_display_name,
        creditor_account: invoice.seller_account_number,
        debtor_name: invoice.buyer_full_name,
        debtor_account: "DE00123456781234567812",
        amount: Money.new!(invoice.currency, Decimal.new("100.00")),
        booking_date: Date.utc_today(),
        value_date: Date.utc_today(),
        remittance_information_unstructured: invoice.invoice_number,
        skip_invoicing: false
      })

    Ash.Seed.seed!(SalesInvoiceTransaction, %{
      organization_id: user.organization_id,
      sales_invoice_id: invoice.id,
      transaction_id: transaction.id
    })
  end
end
