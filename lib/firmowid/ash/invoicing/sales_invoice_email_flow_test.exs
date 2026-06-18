defmodule Firmowid.Ash.Invoicing.SalesInvoiceEmailFlowTest do
  @moduledoc false
  use Firmowid.DataCase

  import Firmowid.AccountsFixtures
  import Firmowid.Test.Support.SalesInvoiceEmailTestHelpers
  import Swoosh.TestAssertions

  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.SalesInvoice.Dispatchers.Communication
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor

  setup_all do
    configure_test_adapters()
  end

  describe "first invoice email flow" do
    test "KSeF-confirmed invoice flow sends a basic email to a valid counterparty" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        admin = admin_fixture()
        processor_scope = processor_scope(admin.organization_id)
        counterparty = valid_counterparty_fixture!(admin)

        invoice =
          sales_invoice_fixture!(admin, %{
            counterparty_id: counterparty.id,
            should_send_emails: true
          })

        drain_swoosh_email_messages()

        confirmed_invoice = confirm_invoice_in_ksef!(invoice, processor_scope)

        assert {:ok, :dispatched} =
                 Communication.dispatch(confirmed_invoice, :ksef_confirmed, processor_scope)

        assert_enqueued_email_job(confirmed_invoice, :basic)

        assert :ok = perform_sales_invoice_email_job(confirmed_invoice, :basic)

        [delivery] = email_deliveries_for(confirmed_invoice, processor_scope)

        assert_sent_delivery(delivery, %{
          sales_invoice_id: confirmed_invoice.id,
          delivery_type: :basic,
          recipient_email: counterparty.email
        })

        assert_email_sent(to: [counterparty.email])
      end)
    end

    test "KSeF-confirmed invoice flow does not send an email when sending is disabled" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        admin = admin_fixture()
        processor_scope = processor_scope(admin.organization_id)
        counterparty = valid_counterparty_fixture!(admin)

        drain_swoosh_email_messages()

        invoice =
          sales_invoice_fixture!(admin, %{
            counterparty_id: counterparty.id,
            should_send_emails: false
          })

        confirmed_invoice = confirm_invoice_in_ksef!(invoice, processor_scope)

        assert {:ok, :skipped} =
                 Communication.dispatch(confirmed_invoice, :ksef_confirmed, processor_scope)

        refute_enqueued_email_job(confirmed_invoice, :basic)
        assert [] == email_deliveries_for(confirmed_invoice, processor_scope)
        assert_no_email_sent()
      end)
    end
  end

  describe "invoice correction email flow" do
    test "email enabled initially and enabled on correction flow sends basic then correction emails" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        admin = admin_fixture()
        processor_scope = processor_scope(admin.organization_id)
        counterparty = valid_counterparty_fixture!(admin)

        original =
          admin
          |> sales_invoice_fixture!(%{counterparty_id: counterparty.id, should_send_emails: true})
          |> confirm_invoice_in_ksef!(processor_scope)

        assert {:ok, :dispatched} =
                 Communication.dispatch(original, :ksef_confirmed, processor_scope)

        assert :ok = perform_sales_invoice_email_job(original, :basic)

        correction =
          admin
          |> sales_invoice_correction_fixture!(original, %{should_send_emails: true})
          |> confirm_invoice_in_ksef!(processor_scope)

        assert {:ok, :dispatched} =
                 Communication.dispatch(correction, :ksef_confirmed, processor_scope)

        assert :ok = perform_sales_invoice_email_job(correction, :invoice_correction)

        assert [:basic] == delivery_types_for(original, processor_scope)
        assert [:invoice_correction] == delivery_types_for(correction, processor_scope)

        [original_delivery] = email_deliveries_for(original, processor_scope)
        [correction_delivery] = email_deliveries_for(correction, processor_scope)

        assert_sent_delivery(original_delivery, %{
          sales_invoice_id: original.id,
          delivery_type: :basic,
          recipient_email: counterparty.email
        })

        assert_sent_delivery(correction_delivery, %{
          sales_invoice_id: correction.id,
          delivery_type: :invoice_correction,
          recipient_email: counterparty.email
        })
      end)
    end

    test "email enabled initially but disabled on correction flow sends only initial basic email" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        admin = admin_fixture()
        processor_scope = processor_scope(admin.organization_id)
        counterparty = valid_counterparty_fixture!(admin)

        original =
          admin
          |> sales_invoice_fixture!(%{counterparty_id: counterparty.id, should_send_emails: true})
          |> confirm_invoice_in_ksef!(processor_scope)

        assert {:ok, :dispatched} =
                 Communication.dispatch(original, :ksef_confirmed, processor_scope)

        assert :ok = perform_sales_invoice_email_job(original, :basic)

        correction =
          admin
          |> sales_invoice_correction_fixture!(original, %{should_send_emails: false})
          |> confirm_invoice_in_ksef!(processor_scope)

        assert {:ok, :skipped} =
                 Communication.dispatch(correction, :ksef_confirmed, processor_scope)

        assert [:basic] == delivery_types_for(original, processor_scope)
        assert [] == delivery_types_for(correction, processor_scope)
      end)
    end

    test "email disabled initially but enabled on correction flow sends only correction email" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        admin = admin_fixture()
        processor_scope = processor_scope(admin.organization_id)
        counterparty = valid_counterparty_fixture!(admin)

        original =
          admin
          |> sales_invoice_fixture!(%{
            counterparty_id: counterparty.id,
            should_send_emails: false
          })
          |> confirm_invoice_in_ksef!(processor_scope)

        assert {:ok, :skipped} =
                 Communication.dispatch(original, :ksef_confirmed, processor_scope)

        correction =
          admin
          |> sales_invoice_correction_fixture!(original, %{should_send_emails: true})
          |> confirm_invoice_in_ksef!(processor_scope)

        assert {:ok, :dispatched} =
                 Communication.dispatch(correction, :ksef_confirmed, processor_scope)

        assert :ok = perform_sales_invoice_email_job(correction, :invoice_correction)

        assert [] == delivery_types_for(original, processor_scope)
        assert [:invoice_correction] == delivery_types_for(correction, processor_scope)

        [correction_delivery] = email_deliveries_for(correction, processor_scope)

        assert_sent_delivery(correction_delivery, %{
          sales_invoice_id: correction.id,
          delivery_type: :invoice_correction,
          recipient_email: counterparty.email
        })
      end)
    end

    test "email disabled initially and disabled on correction flow sends no emails" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        admin = admin_fixture()
        processor_scope = processor_scope(admin.organization_id)
        counterparty = valid_counterparty_fixture!(admin)

        original =
          admin
          |> sales_invoice_fixture!(%{
            counterparty_id: counterparty.id,
            should_send_emails: false
          })
          |> confirm_invoice_in_ksef!(processor_scope)

        assert {:ok, :skipped} =
                 Communication.dispatch(original, :ksef_confirmed, processor_scope)

        correction =
          admin
          |> sales_invoice_correction_fixture!(original, %{should_send_emails: false})
          |> confirm_invoice_in_ksef!(processor_scope)

        assert {:ok, :skipped} =
                 Communication.dispatch(correction, :ksef_confirmed, processor_scope)

        assert [] == delivery_types_for(original, processor_scope)
        assert [] == delivery_types_for(correction, processor_scope)
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
    invoice = Invoicing.create_sales_invoice!(attrs, scope: scope_for(user))
    Ash.load!(invoice, [:sales_invoice_items], scope: scope_for(user))
  end

  defp sales_invoice_correction_fixture!(user, original, attrs) do
    attrs =
      Map.merge(
        %{
          original_invoice_id: original.id,
          invoice_number: "FK/#{System.unique_integer([:positive])}",
          issue_date: Date.utc_today(),
          sale_date: Date.utc_today(),
          due_date: Date.add(Date.utc_today(), 14),
          correction_reason: "Business flow test correction",
          sales_invoice_items: [base_item_attrs(%{name: "Corrected service"})]
        },
        attrs
      )

    invoice = Invoicing.create_sales_invoice_correction!(attrs, scope: scope_for(user))
    Ash.load!(invoice, [:sales_invoice_items], scope: scope_for(user))
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

  defp drain_swoosh_email_messages do
    receive do
      {:email, _} -> drain_swoosh_email_messages()
    after
      0 -> :ok
    end
  end
end
