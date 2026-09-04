defmodule Firmowid.Ash.Finances.Institution do
  @moduledoc """
  Banking institution (bank) available through GoCardless.

  No data layer — wraps the GoCardless institutions API via a ManualRead action.
  Used to present available banks when creating a requisition.
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Finances,
    authorizers: [Ash.Policy.Authorizer]

  actions do
    read :for_country do
      description "List GoCardless institutions available for a given country code."
      argument :country, :string, allow_nil?: false

      manual Firmowid.Ash.Finances.Institution.ForCountry
    end
  end

  policies do
    policy action(:for_country) do
      authorize_if actor_attribute_equals(:role, :admin)
    end
  end

  attributes do
    attribute :id, :string, primary_key?: true, public?: true, writable?: false, allow_nil?: false
    attribute :name, :string, public?: true, writable?: false
    attribute :logo, :string, public?: true, writable?: false
    attribute :dominant_color_rgb, :string, public?: true, writable?: false
    attribute :bic, :string, public?: true, writable?: false
    attribute :countries, {:array, :string}, public?: true, writable?: false
    attribute :transaction_total_days, :string, public?: true, writable?: false
  end
end
