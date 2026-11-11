defmodule Firmowid.Invoicing.Workers.VatIdCheckWorkerTest do
  @moduledoc false
  use Firmowid.DataCase

  import Firmowid.AccountsFixtures

  alias Firmowid.Invoicing
  alias Firmowid.Invoicing.Counterparty
  alias Firmowid.Invoicing.Workers.VatIdCheckWorker
  alias Firmowid.Scope
  alias FirmowidWeb.Inbox.Utilities.Queue

  # Synthetic numbers; Firmowid.Test.Support.ViesApiStub decides the VIES answers.
  defp counterparty!(org_id, country, tax_id) do
    Ash.Seed.seed!(Counterparty, %{
      organization_id: org_id,
      type: :company,
      full_name: "Test #{country} #{tax_id}",
      country: country,
      tax_id: tax_id,
      normalized_tax_id: tax_id
    })
  end

  test "stores each EU VAT number's status and lists the rejected ones in the inbox" do
    admin = admin_fixture()
    org_id = admin.member.organization_id
    scope = %Scope{actor: admin, tenant: org_id}

    org_number_only = counterparty!(org_id, "SE", "1234567897")
    active = counterparty!(org_id, "DE", "123456789")
    inactive = counterparty!(org_id, "NL", "999999999B01")
    vies_down = counterparty!(org_id, "DE", "000000000")
    polish = counterparty!(org_id, "PL", "5260250995")

    assert :ok = perform_job(VatIdCheckWorker, %{organization_id: org_id})

    statuses =
      Map.new([org_number_only, active, inactive, vies_down, polish], fn counterparty ->
        {counterparty.id, Invoicing.get_counterparty!(counterparty.id, scope: scope).vat_id_status}
      end)

    assert statuses == %{
             org_number_only.id => :invalid,
             active.id => :active,
             inactive.id => :inactive,
             vies_down.id => nil,
             polish.id => nil
           }

    inbox_ids = scope |> Queue.attention_items() |> Enum.map(& &1.id)
    assert "vat-id-#{org_number_only.id}" in inbox_ids
    assert "vat-id-#{inactive.id}" in inbox_ids
    refute "vat-id-#{active.id}" in inbox_ids

    fixed =
      Invoicing.update_counterparty!(
        Invoicing.get_counterparty!(inactive.id, scope: scope),
        %{tax_id: "123456789B01"},
        scope: scope
      )

    assert is_nil(fixed.vat_id_status)
  end

  test "the daily run queues a check for every organization" do
    admin = admin_fixture()

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert :ok = perform_job(VatIdCheckWorker, %{})

      assert_enqueued(
        worker: VatIdCheckWorker,
        args: %{organization_id: admin.member.organization_id}
      )
    end)
  end
end
