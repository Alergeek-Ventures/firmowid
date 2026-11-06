defmodule Firmowid.Delegations.Delegation.PendingOrderActions do
  @moduledoc "Corrections to business trip orders before the employer signs them."

  use Spark.Dsl.Fragment, of: Ash.Resource
  use Gettext, backend: Firmowid.Gettext

  alias Firmowid.Invoicing.Changes.ValidateCountryCode

  actions do
    update :update_pending do
      description "Correct an existing business trip order before employer signature."
      require_atomic? false

      accept [
        :billing_month,
        :command_date,
        :destination,
        :destination_country,
        :transport_types,
        :purpose,
        :expected_cost,
        :start_date,
        :end_date
      ]

      validate attribute_equals(:status, :pending)
      # Checks the stored state too, so a stale form cannot edit an approved order.
      change filter(
               expr(
                 status == :pending and is_nil(signed_command_blob_id) and
                   organization_id == ^actor([:member, :organization_id])
               )
             )

      change atomic_update(:title, expr(^atomic_ref(:purpose)))
      change {ValidateCountryCode, field: :destination_country}

      validate compare(:end_date, greater_than_or_equal_to: :start_date),
        message: gettext_noop("cannot be earlier than the departure date")

      validate compare(:expected_cost, greater_than_or_equal_to: Money.new(:PLN, 0)),
        message: gettext_noop("must be greater than or equal to 0 PLN")
    end

    update :prepare_command do
      description "Set the advance amount used in a pending business trip order."
      require_atomic? false
      accept [:advance_amount]
      validate attribute_equals(:status, :pending)
      change filter(expr(status == :pending and is_nil(signed_command_blob_id)))

      validate compare(:advance_amount, greater_than_or_equal_to: Money.new(:PLN, 0)),
        message: gettext_noop("must be greater than or equal to 0 PLN")
    end

    update :update_billing_month do
      description "Set the billing month for a pending business trip delegation."
      require_atomic? false
      accept [:billing_month]
      validate attribute_equals(:status, :pending)
      change filter(expr(status == :pending and is_nil(signed_command_blob_id)))
    end
  end
end
