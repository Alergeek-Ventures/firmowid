defmodule Firmowid.Invoicing.Workers.VatIdCheckWorkerTest do
  @moduledoc false
  use Firmowid.DataCase

  import Firmowid.AccountsFixtures

  alias Firmowid.Core
  alias Firmowid.Invoicing
  alias Firmowid.Invoicing.Counterparty
  alias Firmowid.Invoicing.Workers.VatIdCheckWorker
  alias Firmowid.Scope
  alias FirmowidWeb.Inbox.Utilities.Queue

  # Synthetic numbers; ViesApiStub and VatStatusApiStub decide the registers' answers.
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

  test "stores each tax ID's status and lists the rejected ones in the inbox" do
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
             polish.id => :active
           }

    organization = Core.get_organization!(org_id, scope: scope)
    inbox_ids = scope |> Queue.attention_items(organization) |> Enum.map(& &1.id)
    assert "vat-id-#{org_number_only.id}-invalid" in inbox_ids
    assert "vat-id-#{inactive.id}-inactive" in inbox_ids
    refute Enum.any?(inbox_ids, &String.starts_with?(&1, "vat-id-#{active.id}-"))

    Invoicing.update_counterparty!(
      Invoicing.get_counterparty!(inactive.id, scope: scope),
      %{tax_id: "123456789B01"},
      scope: scope
    )

    # Saving a new number checks it right away (Oban runs inline in tests).
    assert %{vat_id_status: :active, vat_id_checked_at: %DateTime{}} =
             Invoicing.get_counterparty!(inactive.id, scope: scope)
  end

  test "keeps each register's answer and raises only what a register states" do
    admin = admin_fixture()
    org_id = admin.member.organization_id
    scope = %Scope{actor: admin, tenant: org_id}

    # VatStatusApiStub: 1111111111 is outside the VAT register, the others were removed from it.
    outside_vat = counterparty!(org_id, "PL", "1111111111")
    struck_off = counterparty!(org_id, "PL", "2222222222")
    in_krs = counterparty!(org_id, "PL", "3333333333")

    Req.Test.stub(:nip_api, fn conn ->
      nip = List.last(conn.path_info)

      Req.Test.json(conn, %{
        "result" => %{"subject" => %{"nip" => nip, "krs" => "000000000" <> String.first(nip)}}
      })
    end)

    Req.Test.stub(:krs_api, fn conn ->
      case List.last(conn.path_info) do
        "0000000002" ->
          Plug.Conn.send_resp(conn, 204, "")

        "0000000003" ->
          Req.Test.json(conn, %{
            "odpis" => %{
              "dane" => %{
                "dzial1" => %{"danePodmiotu" => %{"identyfikatory" => %{"nip" => "3333333333"}}}
              }
            }
          })
      end
    end)

    assert :ok = perform_job(VatIdCheckWorker, %{organization_id: org_id})

    # Neither register searchable by NIP lists it, as for any KRS company outside VAT.
    assert %{
             vat_id_status: :unconfirmed,
             nip_registers: %{white_list: :absent, krs: nil, ceidg: :absent}
           } =
             Invoicing.get_counterparty!(outside_vat.id, scope: scope)

    assert %{
             vat_id_status: :closed,
             nip_registers: %{
               white_list: :not_registered,
               krs_number: "0000000002",
               krs: :struck_off,
               ceidg: nil
             }
           } = Invoicing.get_counterparty!(struck_off.id, scope: scope)

    assert %{
             vat_id_status: :no_vat,
             nip_registers: %{krs_number: "0000000003", krs: :entered, ceidg: nil}
           } =
             Invoicing.get_counterparty!(in_krs.id, scope: scope)

    organization = Core.get_organization!(org_id, scope: scope)
    inbox = Queue.attention_items(scope, organization)
    inbox_ids = Enum.map(inbox, & &1.id)

    # The inbox names KRS, not CEIDG, as the register that struck the company off.
    assert Enum.find(inbox, &(&1.id == "vat-id-#{struck_off.id}-closed")).context =~ "KRS"

    refute Enum.any?(inbox_ids, &String.starts_with?(&1, "vat-id-#{outside_vat.id}-"))
    refute Enum.any?(inbox_ids, &String.starts_with?(&1, "vat-id-#{in_krs.id}-"))
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
