defmodule Firmowid.Ash.Delegations.Changes.AssignReference do
  @moduledoc "Assigns a unique, monthly delegation reference before creation."

  use Ash.Resource.Change

  alias Firmowid.Ash.Delegations.DelegationReferenceCounter

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      billing_month = Ash.Changeset.get_attribute(changeset, :billing_month)
      initials = initials(context.actor)
      calendar_month = Date.beginning_of_month(billing_month)

      case Ash.create(
             DelegationReferenceCounter,
             %{billing_month: calendar_month, initials: initials},
             action: :next,
             actor: context.actor,
             tenant: context.tenant
           ) do
        {:ok, counter} ->
          reference =
            "#{initials}-#{Calendar.strftime(calendar_month, "%Y-%m")}-#{counter.last_number}"

          Ash.Changeset.force_change_attribute(changeset, :reference, reference)

        {:error, error} ->
          Ash.Changeset.add_error(changeset, error)
      end
    end)
  end

  defp initials(%{name: name, id: id}) do
    case name
         |> to_string()
         |> String.split()
         |> Enum.map_join(&String.first/1)
         |> String.upcase() do
      "" -> "U#{id |> to_string() |> String.slice(0, 8) |> String.upcase()}"
      initials -> initials
    end
  end
end
