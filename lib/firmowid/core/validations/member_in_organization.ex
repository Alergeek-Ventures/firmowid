defmodule Firmowid.Core.Validations.MemberInOrganization do
  @moduledoc "Validates that a record references a member of its own organization (the changeset tenant)."
  use Ash.Resource.Validation

  alias Firmowid.Core.Member

  require Ash.Query

  @impl true
  def validate(changeset, _opts, context) do
    case Ash.Changeset.get_attribute(changeset, :member_id) do
      # A missing member is reported by the attribute's own required check.
      nil -> :ok
      member_id -> validate_member(member_id, changeset, context)
    end
  end

  defp validate_member(member_id, changeset, context) do
    opts = Ash.Context.to_opts(context, tenant: changeset.tenant)

    if Member |> Ash.Query.filter(id == ^member_id) |> Ash.exists?(opts) do
      :ok
    else
      {:error, field: :member_id, message: "is invalid"}
    end
  end
end
