defmodule Firmowid.Ash.Core.OrganizationPoliciesTest do
  @moduledoc false
  use Firmowid.DataCase, async: true

  import Firmowid.AccountsFixtures

  alias Ash.Error.Forbidden
  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Scope

  describe "update_billing_plan policy" do
    test "organization admin cannot update the billing plan" do
      admin = admin_fixture()
      organization = Core.get_organization!(admin.organization_id, authorize?: false)

      assert {:error, %Forbidden{}} =
               Core.update_organization_billing_plan(
                 organization,
                 %{billing_plan: :firma},
                 scope: admin_scope(admin)
               )
    end

    test "superuser can update the billing plan" do
      admin = admin_fixture()
      organization = Core.get_organization!(admin.organization_id, authorize?: false)

      assert {:ok, updated_organization} =
               Core.update_organization_billing_plan(
                 organization,
                 %{billing_plan: :firma},
                 scope: superuser_scope(admin)
               )

      assert updated_organization.billing_plan == :firma
    end
  end

  defp admin_scope(admin), do: %Scope{actor: admin, tenant: admin.organization_id}

  defp superuser_scope(admin) do
    %Scope{actor: %{admin | system_role: :superuser}, tenant: admin.organization_id}
  end
end
