defmodule Firmowid.Core.OrganizationPoliciesTest do
  @moduledoc false
  use Firmowid.DataCase, async: true

  import Firmowid.AccountsFixtures

  alias Ash.Error.Forbidden
  alias Firmowid.Core
  alias Firmowid.Scope
  alias Firmowid.SystemActor

  describe "update_billing_plan policy" do
    test "organization admin cannot update the billing plan" do
      admin = admin_fixture()
      organization = Core.get_organization!(admin.member.organization_id, authorize?: false)

      assert {:error, %Forbidden{}} =
               Core.update_organization_billing_plan(
                 organization,
                 %{billing_plan: :firma},
                 scope: admin_scope(admin)
               )
    end

    test "superuser can update the billing plan" do
      admin = admin_fixture()
      organization = Core.get_organization!(admin.member.organization_id, authorize?: false)

      assert {:ok, updated_organization} =
               Core.update_organization_billing_plan(
                 organization,
                 %{billing_plan: :firma},
                 scope: superuser_scope(admin)
               )

      assert updated_organization.billing_plan == :firma
    end
  end

  describe "tenant isolation" do
    test "an admin cannot read or update another organization" do
      admin = admin_fixture()
      other_admin = admin_fixture()

      other_organization =
        Core.get_organization!(other_admin.member.organization_id, authorize?: false)

      assert {:error, _} = Core.get_organization(other_organization.id, scope: admin_scope(admin))

      assert {:error, %Forbidden{}} =
               Core.update_organization(other_organization, %{name: "Przejęta organizacja"}, scope: admin_scope(admin))
    end
  end

  test "KSeF and billing system actors read only their own organization" do
    organization_id = admin_fixture().member.organization_id
    other_organization_id = admin_fixture().member.organization_id

    for role <- [:ksef_session, :billing_snapshotter] do
      scope = %Scope{
        actor: %SystemActor{org_id: organization_id, role: role},
        tenant: organization_id
      }

      assert {:ok, _} = Core.get_organization(organization_id, scope: scope)
      assert {:error, _} = Core.get_organization(other_organization_id, scope: scope)
    end
  end

  defp admin_scope(admin), do: %Scope{actor: admin, tenant: admin.member.organization_id}

  defp superuser_scope(admin) do
    %Scope{actor: %{admin | system_role: :superuser}, tenant: admin.member.organization_id}
  end
end
