defmodule Firmowid.Ash.Payroll.Validations.MemberInOrganization do
  @moduledoc "Validates that payroll data references a member of its organization."
  use Ash.Resource.Validation

  alias Firmowid.Ash.Core.Member

  require Ash.Query

  @impl true
  def validate(changeset, _opts, context) do
    member_id = Ash.Changeset.get_attribute(changeset, :member_id)
    opts = Ash.Context.to_opts(context, tenant: changeset.tenant)

    if Member |> Ash.Query.filter(id == ^member_id) |> Ash.exists?(opts) do
      :ok
    else
      {:error, field: :member_id, message: "is invalid"}
    end
  end
end
