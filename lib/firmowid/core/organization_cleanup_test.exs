defmodule Firmowid.Core.OrganizationCleanupTest do
  @moduledoc "Checks account-scoped OAuth cleanup after the read/list split."
  use Firmowid.DataCase, async: true

  import ExUnit.CaptureLog
  import Firmowid.AccountsFixtures
  import Firmowid.FinancesFixtures
  import Firmowid.TimetrackerFixtures

  alias Firmowid.Core
  alias Firmowid.Core.Member
  alias Firmowid.Core.OauthAuthorizationCode
  alias Firmowid.Core.OauthConsent
  alias Firmowid.Core.OauthRefreshToken
  alias Firmowid.Core.Organization
  alias Firmowid.Core.OrganizationCleanup
  alias Firmowid.Delegations.DelegationReferenceCounter
  alias Firmowid.Finances.Requisition
  alias Firmowid.Finances.Transaction
  alias Firmowid.Invoicing.CostInvoice
  alias Firmowid.Invoicing.CounterpartyProposal
  alias Firmowid.Invoicing.SkippedCounterpartySuggestion
  alias Firmowid.Ksef.Credential
  alias Firmowid.Scope
  alias Firmowid.SystemActor
  alias Phoenix.Socket.Broadcast

  test "membership disconnect is delivered after its surrounding Ash transaction" do
    owner = admin_fixture()
    user = user_in_org_fixture(owner.member.organization_id, %{role: :accountant})
    {:ok, %{"jti" => jti}} = AshAuthentication.Jwt.peek(user.__metadata__.token)
    topic = "users_sessions:#{jti}"
    :ok = FirmowidWeb.Core.Endpoint.subscribe(topic)
    scope = %Scope{actor: owner, tenant: owner.member.organization_id}

    ExUnit.CaptureLog.capture_log(fn ->
      assert {:ok, :ok} =
               Ash.transact([Member], fn ->
                 assert {:ok, _member} =
                          Core.update_member_role(user.member, %{role: :employee}, scope: scope)

                 refute_received %Broadcast{topic: ^topic, event: "disconnect"}
                 :ok
               end)
    end)

    assert_received %Broadcast{topic: ^topic, event: "disconnect"}

    assert {:error, rollback_error} =
             Ash.transact([Member], fn ->
               Core.update_member_role!(user.member, %{role: :admin}, scope: scope)
               refute_received %Broadcast{topic: ^topic, event: "disconnect"}
               {:error, :rollback}
             end)

    assert Exception.message(rollback_error) =~ "rollback"
    refute_received %Broadcast{topic: ^topic, event: "disconnect"}
  end

  test "an organization with a project and another member's recorded time can be deleted" do
    owner = admin_fixture()
    organization_id = owner.member.organization_id
    employee = user_in_org_fixture(organization_id)
    project = project_fixture(%{organization_id: organization_id})

    session_fixture(%{
      user_id: employee.id,
      project_id: project.id,
      organization_id: organization_id
    })

    scope = %Scope{actor: owner, tenant: organization_id}
    organization = Core.get_organization!(organization_id, scope: scope)

    assert :ok = Core.destroy_organization(organization, scope: scope)
  end

  test "an organization with a cost invoice imported from KSeF can be deleted" do
    owner = admin_fixture()
    organization_id = owner.member.organization_id
    invoice = seed_ksef_cost_invoice!(organization_id)

    # Records that reference only the organization go with it.
    Ash.Seed.seed!(CounterpartyProposal, %{
      group_key: "acme",
      source_hash: "hash",
      organization_id: organization_id
    })

    Ash.Seed.seed!(SkippedCounterpartySuggestion, %{
      group_key: "acme",
      skipped_on: ~D[2026-02-01],
      organization_id: organization_id
    })

    Ash.Seed.seed!(DelegationReferenceCounter, %{
      billing_month: ~D[2026-02-01],
      initials: "JK",
      last_number: 1,
      organization_id: organization_id
    })

    scope = %Scope{actor: owner, tenant: organization_id}
    organization = Core.get_organization!(organization_id, scope: scope)

    assert :ok = Core.destroy_organization(organization, scope: scope)

    assert Firmowid.Repo.get(CostInvoice, invoice.id) == nil
  end

  test "a KSeF cost invoice cannot be deleted outside of an organization deletion" do
    owner = admin_fixture()
    invoice = seed_ksef_cost_invoice!(owner.member.organization_id)

    assert_raise Postgrex.Error, ~r/Cannot delete a KSeF-imported cost invoice/, fn ->
      Firmowid.Repo.query!("DELETE FROM cost_invoices WHERE id = $1", [
        Ecto.UUID.dump!(invoice.id)
      ])
    end
  end

  describe "remote cleanup" do
    setup do
      owner = admin_fixture()
      organization_id = owner.member.organization_id

      requisition =
        Ash.Seed.seed!(Requisition, %{id: Ecto.UUID.generate(), organization_id: organization_id})

      parent = self()

      # The stub runs in the test process: record whether the organization still exists at each call.
      Req.Test.stub(:bank_data_requisition, fn conn ->
        send(
          parent,
          {:gocardless, conn.method, conn.request_path, Firmowid.Repo.get(Organization, organization_id) != nil}
        )

        Req.Test.json(conn, %{"agreement" => Ecto.UUID.generate()})
      end)

      scope = %Scope{actor: owner, tenant: organization_id}
      organization = Core.get_organization!(organization_id, scope: scope)

      %{organization: organization, requisition: requisition, scope: scope, owner: owner}
    end

    test "runs with the captured requisitions only after the deletion committed", ctx do
      capture_log(fn ->
        assert :ok = Core.destroy_organization(ctx.organization, scope: ctx.scope)
      end)

      assert_received {:gocardless, "DELETE", path, false}
      assert path =~ ctx.requisition.id
    end

    test "does not run when the deletion fails", ctx do
      # Rolled back with the test's transaction, like everything else.
      Firmowid.Repo.query!("""
      CREATE FUNCTION fail_requisition_delete() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN RAISE EXCEPTION 'simulated deletion failure'; END $$
      """)

      Firmowid.Repo.query!("""
      CREATE TRIGGER fail_requisition_delete BEFORE DELETE ON requisitions
      FOR EACH ROW EXECUTE FUNCTION fail_requisition_delete()
      """)

      capture_log(fn ->
        assert {:error, _error} = Core.destroy_organization(ctx.organization, scope: ctx.scope)
      end)

      refute_received {:gocardless, _method, _path, _exists}
      assert Firmowid.Repo.get(Organization, ctx.organization.id)
    end

    test "revokes the KSeF session captured before its credential was deleted", ctx do
      organization_id = ctx.organization.id
      parent = self()

      Ash.Seed.seed!(Credential, %{
        organization_id: organization_id,
        status: :working,
        auth_type: :token,
        credentials: "token-#{System.unique_integer([:positive])}"
      })

      Cachex.put(
        :ksef,
        {:access_token, organization_id},
        Firmowid.Ksef.KsefTestHelpers.jwt(3_600)
      )

      Req.Test.stub(:ksef_api, fn conn ->
        send(
          parent,
          {:ksef, conn.method, conn.request_path, Firmowid.Repo.get(Organization, organization_id) != nil}
        )

        Plug.Conn.send_resp(conn, 204, "")
      end)

      capture_log(fn ->
        assert :ok = Core.destroy_organization(ctx.organization, scope: ctx.scope)
      end)

      assert_received {:ksef, "DELETE", "/v2/auth/sessions/current", false}
    end
  end

  test "a user paid a salary in another organization can delete their account" do
    owner = admin_fixture()
    organization_id = owner.member.organization_id
    employee = user_in_org_fixture(organization_id)

    bank_account = bank_account_fixture!(owner)

    transaction =
      Ash.Seed.seed!(Transaction, %{
        organization_id: organization_id,
        bank_account_id: bank_account.id,
        debtor_account: bank_account.iban,
        creditor_account: "PL999",
        amount: Money.new!(:PLN, -100),
        booking_date: ~D[2026-01-10],
        value_date: ~D[2026-01-10],
        salary_user_id: employee.id,
        salary_month: ~D[2025-12-01]
      })

    capture_log(fn ->
      assert :ok = Core.destroy_user(employee, actor: with_session_claims(employee))
    end)

    scope = %Scope{actor: owner, tenant: organization_id}

    persisted =
      Firmowid.Finances.get_transaction!(transaction.id, load: [:has_salary?], scope: scope)

    assert persisted.has_salary?
    assert persisted.salary_month == ~D[2025-12-01]
    assert is_nil(persisted.salary_user_id)
  end

  test "account cleanup lists and deletes only its user's OAuth records" do
    owner = user_fixture()
    other = user_in_org_fixture(owner.member.organization_id)
    own_records = seed_oauth_records(owner.id)
    other_records = seed_oauth_records(other.id)
    scope = cleanup_scope(owner.id)

    for own_record <- own_records do
      resource = own_record.__struct__
      assert [listed] = resource.list!(scope: scope)
      assert listed.id == own_record.id
      assert [] == resource.list!(%{user_id: other.id}, scope: scope)
      assert [read] = resource.read!(scope: scope)
      assert read.id == own_record.id
      assert [] == resource.read!(actor: owner)
      assert [] == resource.list!(actor: owner)
    end

    assert :ok = OrganizationCleanup.remove_account_oauth_dependents(scope)

    for own_record <- own_records do
      resource = own_record.__struct__
      assert [] == resource.list!(scope: scope)
    end

    for other_record <- other_records do
      resource = other_record.__struct__
      assert [remaining] = resource.list!(scope: cleanup_scope(other.id))

      assert remaining.id == other_record.id
    end
  end

  defp seed_ksef_cost_invoice!(organization_id) do
    Ash.Seed.seed!(CostInvoice, %{
      seller: "Acme Sp. z o.o.",
      seller_display_name: "Acme",
      seller_address: "ul. Przykładowa 1, 00-001 Warszawa",
      sale_date: ~D[2026-02-01],
      issue_date: ~D[2026-02-01],
      due_date: ~D[2026-02-14],
      amount: Money.new!("PLN", Decimal.new("-123.45")),
      description: "Import z KSeF",
      invoice_identifier: "FV/2026/02/001",
      skip_invoicing: false,
      organization_id: organization_id,
      ksef_number: "KSEF-2026-TEST-#{System.unique_integer([:positive])}",
      ksef_permanent_storage_date: ~N[2026-02-01 12:00:00],
      ksef_downloaded_at: DateTime.utc_now()
    })
  end

  defp cleanup_scope(user_id) do
    %Scope{
      actor: %SystemActor{org_id: nil, role: :account_cleanup, user_id: user_id},
      tenant: nil
    }
  end

  defp seed_oauth_records(user_id) do
    attrs = %{
      client_id: Ash.UUIDv7.generate(),
      user_id: user_id,
      scope: "mcp",
      resource_uri: "https://example.com/mcp",
      expires_at: DateTime.shift(DateTime.utc_now(), minute: 5)
    }

    code =
      Ash.Seed.seed!(
        OauthAuthorizationCode,
        Map.merge(attrs, %{
          redirect_uri: "https://example.com/callback",
          code_challenge: "test-challenge"
        })
      )

    consent =
      Ash.Seed.seed!(
        OauthConsent,
        attrs
        |> Map.take([:client_id, :user_id, :scope])
        |> Map.put(:granted_at, DateTime.utc_now())
      )

    refresh =
      Ash.Seed.seed!(
        OauthRefreshToken,
        Map.merge(attrs, %{
          token_hash: Ash.UUIDv7.generate(),
          chain_id: Ash.UUIDv7.generate()
        })
      )

    [code, consent, refresh]
  end
end
