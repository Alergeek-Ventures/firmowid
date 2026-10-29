defmodule Firmowid.Payroll.MemberPayrollInput.ImportFromDocument do
  @moduledoc "Imports known monthly payroll facts while retaining previously sourced values."

  use Ash.Resource.Actions.Implementation

  alias Firmowid.Payroll.MemberPayrollInput
  alias Firmowid.Scope

  @fact_fields [
    :payout_date,
    :payout_date_basis,
    :gross,
    :prior_taxable_income,
    :prior_social_base,
    :prior_exempt_income,
    :employer_ppk_income,
    :employer_ppk_date,
    :single_payment,
    :standard_pay,
    :insurance_unchanged,
    :source_blob_id
  ]

  @impl true
  def run(input, _opts, context) do
    with %{member_id: raw_member_id, salary_month: %Date{day: 1} = salary_month} <-
           input.arguments.attributes,
         {:ok, member_id} when is_binary(member_id) <- Ash.Type.cast_input(:uuid, raw_member_id) do
      import(member_id, salary_month, input.arguments.attributes, context)
    else
      _ -> {:error, field: :attributes, message: "is invalid"}
    end
  end

  defp import(member_id, salary_month, attributes, context) do
    scope = Scope.new!(context.actor, context.tenant)

    incoming =
      attributes
      |> Map.take(@fact_fields)
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    identity = %{member_id: member_id, salary_month: salary_month}

    case MemberPayrollInput.list(identity, scope: scope) do
      {:ok, []} ->
        MemberPayrollInput.create(Map.merge(identity, incoming), scope: scope)

      {:ok, [existing]} ->
        MemberPayrollInput.update(existing, incoming, scope: scope)

      {:error, reason} ->
        {:error, reason}
    end
  end
end
