defmodule Firmowid.Core.ApiKeyTest do
  use Firmowid.DataCase, async: true

  import Firmowid.AccountsFixtures

  alias Firmowid.Core

  test "a member sees their own keys, an admin also the company's" do
    admin = admin_fixture()
    organization_id = admin.member.organization_id
    employee = user_in_org_fixture(organization_id)

    personal = Core.create_api_key!(%{name: "Skrypt"}, actor: employee, tenant: organization_id)

    company =
      Core.create_company_api_key!(%{name: "Sklep", role: :accountant},
        actor: admin,
        tenant: organization_id
      )

    assert "firmowid_" <> _rest = personal.__metadata__.plaintext_api_key
    assert "firmowid_org_" <> _rest = company.__metadata__.plaintext_api_key

    assert [%{id: personal_id}] = Core.list_api_keys!(actor: employee, tenant: organization_id)
    assert personal_id == personal.id

    assert [listed] = Core.list_api_keys!(actor: admin, tenant: organization_id)
    assert listed.id == company.id
    assert listed.service_account.role == :accountant
    refute Map.has_key?(listed.__metadata__, :plaintext_api_key)
  end

  test "only an admin creates and revokes company keys" do
    admin = admin_fixture()
    organization_id = admin.member.organization_id
    employee = user_in_org_fixture(organization_id, %{role: :accountant})
    attrs = %{name: "Sklep", role: :accountant}

    assert {:error, %Ash.Error.Forbidden{}} =
             Core.create_company_api_key(attrs, actor: employee, tenant: organization_id)

    key = Core.create_company_api_key!(attrs, actor: admin, tenant: organization_id)

    assert {:error, _forbidden} =
             Core.revoke_api_key(key, actor: employee, tenant: organization_id)

    Core.revoke_api_key!(key, actor: admin, tenant: organization_id)

    assert {:error, %Ash.Error.Invalid{}} =
             Core.get_service_account(key.service_account_id,
               actor: admin,
               tenant: organization_id
             )
  end
end
