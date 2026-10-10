defmodule Firmowid.Ash.ReadListContractTest do
  @moduledoc "Guards the separation between framework reads and application listing."
  use ExUnit.Case, async: true

  alias Firmowid.Ash.Billing.Snapshot
  alias Firmowid.Ash.Core.OauthAuthorizationCode
  alias Firmowid.Ash.Core.OauthConsent
  alias Firmowid.Ash.Core.OauthRefreshToken
  alias Firmowid.Ash.Finances.Requisition
  alias Firmowid.Ash.Invoicing.KsefInvoiceDigest
  alias Firmowid.Ash.Invoicing.SalesInvoiceEmailDelivery
  alias Firmowid.Ash.SystemActor

  test "primary reads do not inherit application arguments, filters or preparations" do
    resources =
      :firmowid
      |> Ash.Info.domains_and_resources()
      |> Map.values()
      |> List.flatten()
      |> Enum.uniq()

    for resource <- resources,
        action = Ash.Resource.Info.primary_action(resource, :read),
        not is_nil(action) do
      assert action.name == :read, inspect(resource)
      assert action.arguments == [], inspect(resource)
      assert action.filter in [nil, []], inspect(resource)
      assert action.preparations == [], inspect(resource)
    end
  end

  test "optional list filters remain separate from the default read" do
    user_id = Ash.UUIDv7.generate()
    actor = %SystemActor{org_id: Ash.UUIDv7.generate(), role: :organization_cleanup}
    options = [actor: actor, tenant: actor.org_id]

    cases = [
      {Snapshot, %{start_month: ~D[2026-01-01], end_month: ~D[2026-03-01]}},
      {OauthAuthorizationCode, %{user_id: user_id}},
      {OauthConsent, %{user_id: user_id}},
      {OauthRefreshToken, %{user_id: user_id}},
      {Requisition, %{remote_deleted?: false}},
      {KsefInvoiceDigest, %{ids: [Ash.UUIDv7.generate()], delivered?: false}},
      {SalesInvoiceEmailDelivery, %{sales_invoice_id: Ash.UUIDv7.generate(), delivery_type: :basic, status: :sent}}
    ]

    for {resource, arguments} <- cases do
      filtered = resource.query_to_list(arguments, options)
      unfiltered = resource.query_to_list(%{}, options)

      assert filtered.valid?, inspect(resource)
      assert filtered.action.name == :list
      refute filtered.action.primary?
      assert filtered.filter != nil, inspect(resource)
      assert unfiltered.valid?, inspect(resource)
      assert unfiltered.filter == nil, inspect(resource)
    end
  end
end
