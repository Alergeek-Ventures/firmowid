defmodule Firmowid.Ash.Invoicing.KsefInvoiceDigestTest do
  @moduledoc false
  use Firmowid.DataCase

  import Firmowid.AccountsFixtures
  import Swoosh.TestAssertions

  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.KsefInvoiceDigest
  alias Firmowid.Ash.Invoicing.Workers.SendKsefInvoiceDigestWorker
  alias Firmowid.Ash.Ksef.Credential
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor
  alias Firmowid.Repo

  test "send_digest marks persisted digest as delivered when active admins exist" do
    admin = admin_fixture()
    organization_id = admin.organization_id

    drain_swoosh_email_messages()

    invoice =
      insert_cost_invoice!(organization_id, %{
        invoice_identifier: "CI-KSEF-SEND-1",
        ksef_number: "KSEF-#{System.unique_integer([:positive])}"
      })

    assert {:ok, digest} =
             KsefInvoiceDigest.create_digest(
               %{cost_invoice_ids: [invoice.id]},
               scope: digest_scope(organization_id)
             )

    assert digest.delivered_at == nil

    assert {:ok, sent_digest} =
             KsefInvoiceDigest.send_digest(digest, %{}, scope: digest_scope(organization_id))

    assert %DateTime{} = sent_digest.delivered_at

    assert_email_sent(subject: "Nowa faktura w Firmowidzie", to: [to_string(admin.email)])
  end

  test "send_digest fails when there are no active admin recipients" do
    employee = user_fixture()
    organization_id = employee.organization_id

    drain_swoosh_email_messages()

    invoice =
      insert_cost_invoice!(organization_id, %{
        invoice_identifier: "CI-KSEF-NO-ADMIN",
        ksef_number: "KSEF-#{System.unique_integer([:positive])}"
      })

    assert {:ok, digest} =
             KsefInvoiceDigest.create_digest(
               %{cost_invoice_ids: [invoice.id]},
               scope: digest_scope(organization_id)
             )

    assert {:error, error} =
             KsefInvoiceDigest.send_digest(digest, %{}, scope: digest_scope(organization_id))

    assert_has_error_message(error, "cannot send KSeF digest without recipients")

    assert_no_email_sent()
  end

  test "send_digest fails when there are no persisted invoices" do
    admin = admin_fixture()
    organization_id = admin.organization_id

    drain_swoosh_email_messages()

    digest =
      Ash.Seed.seed!(KsefInvoiceDigest, %{organization_id: organization_id})

    assert {:error, error} =
             KsefInvoiceDigest.send_digest(digest, %{}, scope: digest_scope(organization_id))

    assert_has_error_message(error, "cannot send KSeF digest without persisted invoices")

    assert_no_email_sent()
  end

  test "selects only undigested KSeF invoices before run cutoff" do
    user = user_fixture()
    organization_id = user.organization_id

    seed_ksef_credential!(organization_id)

    now = DateTime.utc_now()

    included_invoice =
      insert_cost_invoice!(organization_id, %{
        invoice_identifier: "CI-KSEF-INCLUDED-1",
        ksef_number: "KSEF-#{System.unique_integer([:positive])}",
        inserted_at: DateTime.shift(now, minute: -20)
      })

    _future_invoice =
      insert_cost_invoice!(organization_id, %{
        invoice_identifier: "CI-KSEF-FUTURE-1",
        ksef_number: "KSEF-#{System.unique_integer([:positive])}",
        inserted_at: DateTime.shift(now, minute: 10)
      })

    _manual_invoice =
      insert_cost_invoice!(organization_id, %{
        invoice_identifier: "CI-MANUAL-1",
        ksef_number: nil,
        ksef_permanent_storage_date: nil,
        ksef_downloaded_at: nil
      })

    assert {:ok, 1} =
             KsefInvoiceDigest.create_scheduled_digests(
               %{
                 organization_ids: [organization_id],
                 enqueue_send?: false
               },
               actor: digest_actor(organization_id)
             )

    digest = latest_digest!(organization_id)

    loaded_digest =
      Ash.load!(digest, [:cost_invoices], scope: digest_scope(organization_id))

    included_ids = Enum.map(loaded_digest.cost_invoices, & &1.id)
    assert included_invoice.id in included_ids
    assert length(included_ids) == 1

    undigested =
      Invoicing.list_cost_invoices!(
        %{source: :ksef, in_digest: :yes},
        scope: digest_scope(organization_id)
      )

    assert length(undigested) == 1
    assert hd(undigested).id == included_invoice.id
  end

  test "excludes previously digested invoices on subsequent scheduled runs" do
    user = user_fixture()
    organization_id = user.organization_id

    seed_ksef_credential!(organization_id)

    now = DateTime.utc_now()

    invoice_a =
      insert_cost_invoice!(organization_id, %{
        invoice_identifier: "CI-KSEF-R1",
        ksef_number: "KSEF-#{System.unique_integer([:positive])}",
        inserted_at: DateTime.shift(now, second: -4_000)
      })

    invoice_b =
      insert_cost_invoice!(organization_id, %{
        invoice_identifier: "CI-KSEF-R1-B",
        ksef_number: "KSEF-#{System.unique_integer([:positive])}",
        inserted_at: DateTime.shift(now, minute: -65)
      })

    assert {:ok, 1} =
             KsefInvoiceDigest.create_scheduled_digests(
               %{
                 organization_ids: [organization_id],
                 enqueue_send?: false
               },
               actor: digest_actor(organization_id)
             )

    second_invoice =
      insert_cost_invoice!(organization_id, %{
        invoice_identifier: "CI-KSEF-R2",
        ksef_number: "KSEF-#{System.unique_integer([:positive])}",
        inserted_at: DateTime.shift(now, second: -700)
      })

    assert {:ok, 1} =
             KsefInvoiceDigest.create_scheduled_digests(
               %{
                 organization_ids: [organization_id],
                 enqueue_send?: false
               },
               actor: digest_actor(organization_id)
             )

    assert digest_item_count_for_invoice(invoice_a.id, organization_id) == 1
    assert digest_item_count_for_invoice(invoice_b.id, organization_id) == 1
    assert digest_item_count_for_invoice(second_invoice.id, organization_id) == 1

    loaded_second_digest = digest_with_invoice!(organization_id, second_invoice.id)

    second_ids = Enum.map(loaded_second_digest.cost_invoices, & &1.id)

    assert second_invoice.id in second_ids
    refute invoice_a.id in second_ids
    refute invoice_b.id in second_ids
  end

  test "prevents reusing already digested invoices across digest creation attempts" do
    user = user_fixture()
    organization_id = user.organization_id

    seed_ksef_credential!(organization_id)

    now = DateTime.utc_now()

    invoice =
      insert_cost_invoice!(organization_id, %{
        invoice_identifier: "CI-KSEF-DUP",
        ksef_number: "KSEF-#{System.unique_integer([:positive])}",
        inserted_at: DateTime.shift(now, second: -3_500)
      })

    assert {:ok, 1} =
             KsefInvoiceDigest.create_scheduled_digests(
               %{
                 organization_ids: [organization_id],
                 enqueue_send?: false
               },
               actor: digest_actor(organization_id)
             )

    assert {:error, _} =
             KsefInvoiceDigest.create_digest(
               %{cost_invoice_ids: [invoice.id]},
               scope: digest_scope(organization_id)
             )

    assert digest_item_count_for_invoice(invoice.id, organization_id) == 1
  end

  test "skips organizations without credentials and only creates digests for credentialed orgs" do
    no_credentials_user = user_fixture()
    with_credentials_user = user_fixture()

    seed_ksef_credential!(with_credentials_user.organization_id)

    now = DateTime.utc_now()

    with_credentials_org_id = with_credentials_user.organization_id
    without_credentials_org_id = no_credentials_user.organization_id

    with_credentials_invoice =
      insert_cost_invoice!(with_credentials_org_id, %{
        invoice_identifier: "CI-KSEF-WITH-CRED",
        ksef_number: "KSEF-#{System.unique_integer([:positive])}",
        inserted_at: DateTime.shift(now, minute: -50)
      })

    _without_credentials_invoice =
      insert_cost_invoice!(without_credentials_org_id, %{
        invoice_identifier: "CI-KSEF-WITHOUT-CRED",
        ksef_number: "KSEF-#{System.unique_integer([:positive])}",
        inserted_at: DateTime.shift(now, minute: -50)
      })

    assert {:ok, 1} =
             KsefInvoiceDigest.create_scheduled_digests(
               %{
                 organization_ids: [with_credentials_org_id, without_credentials_org_id],
                 enqueue_send?: false
               },
               actor: digest_actor(with_credentials_org_id)
             )

    digest = latest_digest!(with_credentials_org_id)

    digest =
      Ash.load!(digest, [:cost_invoices], scope: digest_scope(with_credentials_org_id))

    included_ids = Enum.map(digest.cost_invoices, & &1.id)

    assert with_credentials_invoice.id in included_ids

    assert [] == list_digests(without_credentials_org_id)
  end

  test "does not create digest when organization list includes only uncredentialed orgs" do
    no_credentials_user = user_fixture()

    now = DateTime.utc_now()

    without_credentials_org_id = no_credentials_user.organization_id

    insert_cost_invoice!(without_credentials_org_id, %{
      invoice_identifier: "CI-KSEF-NO-CRED-ONLY",
      ksef_number: "KSEF-#{System.unique_integer([:positive])}",
      inserted_at: DateTime.shift(now, minute: -15)
    })

    assert {:ok, 0} =
             KsefInvoiceDigest.create_scheduled_digests(
               %{
                 organization_ids: [without_credentials_org_id],
                 enqueue_send?: false
               },
               actor: digest_actor(without_credentials_org_id)
             )

    assert [] == list_digests(without_credentials_org_id)
  end

  test "dedicated send worker delivers a persisted digest after creation" do
    admin = admin_fixture()
    organization_id = admin.organization_id

    seed_ksef_credential!(organization_id)
    drain_swoosh_email_messages()

    now = DateTime.utc_now()

    invoice =
      insert_cost_invoice!(organization_id, %{
        invoice_identifier: "CI-KSEF-ENQUEUE",
        ksef_number: "KSEF-#{System.unique_integer([:positive])}",
        inserted_at: DateTime.shift(now, minute: -5)
      })

    assert {:ok, 1} =
             KsefInvoiceDigest.create_scheduled_digests(
               %{
                 organization_ids: [organization_id],
                 enqueue_send?: true
               },
               actor: digest_actor(organization_id)
             )

    digest = latest_digest!(organization_id)

    assert :ok =
             perform_job(SendKsefInvoiceDigestWorker, %{
               "digest_id" => digest.id,
               "organization_id" => organization_id
             })

    reloaded = Repo.get!(KsefInvoiceDigest, digest.id)
    assert %DateTime{} = reloaded.delivered_at
    assert_email_sent(subject: "Nowa faktura w Firmowidzie", to: [to_string(admin.email)])

    assert digest_item_count_for_invoice(invoice.id, organization_id) == 1
  end

  defp seed_ksef_credential!(organization_id) do
    Ash.Seed.seed!(Credential, %{
      organization_id: organization_id,
      status: :working,
      auth_type: :token,
      credentials: "token-#{System.unique_integer([:positive])}"
    })
  end

  defp drain_swoosh_email_messages do
    receive do
      {:email, _} ->
        drain_swoosh_email_messages()
    after
      0 -> :ok
    end
  end

  defp assert_has_error_message(%Ash.Error.Invalid{errors: errors}, expected_fragment) do
    assert Enum.any?(errors, fn error ->
             error
             |> Exception.message()
             |> String.contains?(expected_fragment)
           end)
  end

  defp latest_digest!(organization_id) do
    organization_id
    |> list_digests()
    |> List.first()
    |> case do
      nil -> raise "expected at least one digest for organization #{organization_id}"
      digest -> digest
    end
  end

  defp digest_with_invoice!(organization_id, invoice_id) do
    organization_id
    |> list_digests()
    |> Enum.map(fn digest ->
      Ash.load!(digest, [:cost_invoices], scope: digest_scope(organization_id))
    end)
    |> Enum.find(fn digest ->
      Enum.any?(digest.cost_invoices, &(&1.id == invoice_id))
    end)
    |> case do
      nil -> raise "expected a digest containing invoice #{invoice_id}"
      digest -> digest
    end
  end

  defp list_digests(organization_id) do
    KsefInvoiceDigest
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read!(scope: digest_scope(organization_id))
  end

  defp digest_scope(organization_id) do
    %Scope{actor: digest_actor(organization_id), tenant: organization_id}
  end

  defp digest_actor(organization_id) do
    %SystemActor{org_id: organization_id, role: :ksef_digest}
  end

  defp insert_cost_invoice!(organization_id, attrs) do
    {inserted_at, attrs} = Map.pop(attrs, :inserted_at)

    invoice =
      Ash.Seed.seed!(CostInvoice, map_invoice_attrs(organization_id, attrs))

    if inserted_at do
      {:ok, invoice_id_bin} = Ecto.UUID.dump(invoice.id)

      Repo.update_all(
        from(ci in "cost_invoices",
          where: ci.id == ^invoice_id_bin,
          update: [set: [inserted_at: ^inserted_at]]
        ),
        []
      )
    end

    invoice
  end

  defp map_invoice_attrs(organization_id, attrs) do
    base_attrs =
      Map.new(
        seller: "KSeF Supplier",
        seller_display_name: "KSeF Supplier",
        seller_address: "ul. KSeF 1, 00-001 Warszawa",
        sale_date: ~D[2026-01-01],
        issue_date: ~D[2026-01-01],
        due_date: ~D[2026-01-30],
        total_amount: Decimal.new("-100.00"),
        currency: "PLN",
        description: "Invoice for scheduled KSeF digest tests",
        invoice_identifier: attrs[:invoice_identifier] || "CI-KSEF-#{System.unique_integer([:positive])}",
        skip_invoicing: false,
        organization_id: organization_id,
        ksef_number: nil,
        ksef_permanent_storage_date: ~N[2026-01-01 12:00:00],
        ksef_downloaded_at: DateTime.utc_now()
      )

    Map.merge(base_attrs, attrs)
  end

  defp digest_item_count_for_invoice(invoice_id, organization_id) do
    {:ok, invoice_id_bin} = Ecto.UUID.dump(invoice_id)
    {:ok, organization_id_bin} = Ecto.UUID.dump(organization_id)

    Repo.one!(
      from(item in "ksef_invoice_digest_items",
        where: item.cost_invoice_id == ^invoice_id_bin,
        where: item.organization_id == ^organization_id_bin,
        select: count(item.id)
      )
    )
  end
end
