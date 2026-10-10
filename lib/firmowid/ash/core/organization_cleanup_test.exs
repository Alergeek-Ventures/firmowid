defmodule Firmowid.Ash.Core.OrganizationCleanupTest do
  @moduledoc "Checks account-scoped OAuth cleanup after the read/list split."
  use Firmowid.DataCase, async: true

  import Firmowid.AccountsFixtures

  alias Firmowid.Ash.Core.OauthAuthorizationCode
  alias Firmowid.Ash.Core.OauthConsent
  alias Firmowid.Ash.Core.OauthRefreshToken
  alias Firmowid.Ash.Core.OrganizationCleanup
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor

  test "account cleanup lists and deletes only its user's OAuth records" do
    owner = user_fixture()
    other = user_in_org_fixture(owner.organization_id)
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
