defmodule Firmowid.Ash.ScopeTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor

  test "rejects a scope whose system actor belongs to another organization" do
    assert {:error, :actor_tenant_mismatch} =
             Scope.new(%SystemActor{org_id: "organization-a", role: :bank_sync}, "organization-b")
  end

  test "accepts a scope whose system actor belongs to its tenant" do
    actor = %SystemActor{org_id: "organization-a", role: :bank_sync}

    assert {:ok, %Scope{actor: ^actor, tenant: "organization-a"}} =
             Scope.new(actor, "organization-a")
  end
end
