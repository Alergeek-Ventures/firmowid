defmodule Firmowid.Core.ApiKeyTest do
  use Firmowid.DataCase, async: true

  import Firmowid.AccountsFixtures

  alias Ash.Error.Invalid
  alias Firmowid.Core

  test "shows the key once and lists only the organization's keys" do
    admin = admin_fixture()
    organization_id = admin.member.organization_id
    other_admin = admin_fixture()

    key =
      Core.create_api_key!(%{name: "Sklep", scopes: [:sales_invoices]},
        actor: admin,
        tenant: organization_id
      )

    assert "firmowid_" <> _rest = key.__metadata__.plaintext_api_key
    assert key.user_id == admin.id
    assert key.scopes == [:sales_invoices]

    assert [listed] = Core.list_api_keys!(actor: admin, tenant: organization_id)
    assert listed.id == key.id
    refute Map.has_key?(listed.__metadata__, :plaintext_api_key)

    assert Core.list_api_keys!(actor: other_admin, tenant: other_admin.member.organization_id) ==
             []
  end

  test "only an admin creates keys" do
    organization_id = admin_fixture().member.organization_id
    employee = user_in_org_fixture(organization_id)

    assert {:error, %Ash.Error.Forbidden{}} =
             Core.create_api_key(%{name: "Sklep", scopes: [:sales_invoices]},
               actor: employee,
               tenant: organization_id
             )
  end

  test "a key opens at least one known scope" do
    admin = admin_fixture()
    opts = [actor: admin, tenant: admin.member.organization_id]

    assert {:error, %Invalid{}} =
             Core.create_api_key(%{name: "Sklep", scopes: []}, opts)

    assert {:error, %Invalid{}} = Core.create_api_key(%{name: "Sklep"}, opts)

    assert {:error, %Invalid{}} =
             Core.create_api_key(%{name: "Sklep", scopes: [:payroll]}, opts)
  end
end
