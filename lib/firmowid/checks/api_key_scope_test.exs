defmodule Firmowid.Checks.ApiKeyScopeTest do
  @moduledoc false
  use Firmowid.DataCase, async: true

  import Firmowid.AccountsFixtures

  alias Firmowid.Checks.ApiKeyScope
  alias Firmowid.Core

  test "matches only an actor signed in with a key that has the scope" do
    admin = admin_fixture()

    key =
      Core.create_api_key!(%{name: "Sklep", scopes: [:sales_invoices]},
        actor: admin,
        tenant: admin.member.organization_id
      )

    # Signing in with the key puts it in the actor's metadata.
    signed_in = Ash.Resource.put_metadata(admin, :api_key, key)

    assert {:ok, true} = ApiKeyScope.match?(signed_in, %{}, scope: :sales_invoices)
    assert {:ok, false} = ApiKeyScope.match?(signed_in, %{}, scope: :payroll)
    assert {:ok, false} = ApiKeyScope.match?(admin, %{}, scope: :sales_invoices)
  end
end
