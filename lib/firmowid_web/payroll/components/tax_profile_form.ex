defmodule FirmowidWeb.Payroll.Components.TaxProfileForm do
  @moduledoc """
  Net forecast assumptions of a member, edited by the member in settings and by
  an administrator in the employee profile.

  The member has one current profile, not one per contract. The form shows and
  submits only the assumptions the current contract type reads, and saving
  replaces the whole profile, which clears the others. Until it is saved again,
  assumptions saved under a previous contract type still apply where the current
  type reads them too, such as the monthly tax reduction or the costs shared by
  UZ and UOD. An empty value means not confirmed, never zero.
  """
  use FirmowidWeb, :html

  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Core.Member
  alias Firmowid.Ash.Scope
  alias Phoenix.HTML.Form
  alias Phoenix.LiveView.Rendered

  @doc "Builds the form replacing the member's net forecast assumptions."
  @spec form(Member.t(), Scope.t()) :: Form.t()
  def form(member, scope) do
    member
    |> AshPhoenix.Form.for_update(:update_tax_profile, domain: Core, scope: scope, as: "member")
    |> to_form()
  end

  @doc """
  Lists the assumptions the payout estimate reads for a contract type, none for
  B2B or without a contract. Mirrors the profile clauses of
  `Firmowid.Ash.Payroll.UserSalary.Calculations.PayoutEstimates`.
  """
  @spec fields(atom() | nil) :: [atom()]
  def fields(:uop), do: [:monthly_tax_reduction, :employment_costs, :youth_relief]
  def fields(:uz), do: [:monthly_tax_reduction, :mandate_insurance, :civil_costs, :youth_relief]
  def fields(:uod), do: [:monthly_tax_reduction, :civil_costs]
  def fields(_contract_type), do: []

  @doc "Returns the label of an assumption."
  @spec field_label(atom()) :: String.t()
  def field_label(:monthly_tax_reduction), do: gettext("Monthly tax reduction")

  def field_label(field) when field in [:employment_costs, :civil_costs], do: gettext("Tax-deductible costs")

  def field_label(:mandate_insurance), do: gettext("Insurance contributions")
  def field_label(:youth_relief), do: gettext("Youth tax relief")

  @doc "Returns the id of an assumption's select, for its label."
  @spec input_id(Form.t(), atom()) :: String.t()
  def input_id(form, field), do: "#{form.id}_tax_profile_#{field}"

  @doc "Explains what the assumptions are for; the forecast explains its own limits."
  @spec notice() :: String.t()
  def notice do
    gettext(
      "Used only for the net forecast, not as a PIT-2 declaration or payroll. Until all assumptions are confirmed, the forecast shows hypothetical variants."
    )
  end

  attr :form, Form, required: true
  attr :field, :atom, required: true

  @doc "Shows the saved value of an assumption, or that it is not confirmed."
  @spec saved_value(map()) :: Rendered.t()
  def saved_value(assigns) do
    assigns = assign(assigns, :value, selected(assigns.form.data.tax_profile, assigns.field))

    ~H"""
    <span class={[@value == "" && "text-grey-500"]}>{option_label(@field, @value)}</span>
    """
  end

  attr :form, Form, required: true
  attr :field, :atom, required: true

  @doc "Renders the select of an assumption with its current form value."
  @spec select(map()) :: Rendered.t()
  def select(assigns) do
    assigns = assign(assigns, :value, selected(assigns.form[:tax_profile].value, assigns.field))

    ~H"""
    <div class="flex w-full min-w-0 flex-col gap-1">
      <%!-- An empty value is the "Not confirmed" choice, not the shared select's placeholder. --%>
      <.input
        type="select"
        id={input_id(@form, @field)}
        name={"#{@form.name}[tax_profile][#{@field}]"}
        value={@value}
        options={options(@field)}
        input_class={[@value == "" && "text-grey-600!"]}
      />
      <p :if={hint(@field)} class="text-xs/snug text-grey-600">{hint(@field)}</p>
    </div>
    """
  end

  # Saved and validated profiles hold atoms and integers; invalid submitted
  # params stay strings.
  defp selected(nil, _field), do: ""
  defp selected(profile, field), do: to_string(Map.get(profile, field, profile[to_string(field)]))

  defp option_label(field, value) do
    Enum.find_value(options(field), fn {label, option} -> option == value && label end)
  end

  defp options(field), do: [{gettext("Not confirmed"), ""} | choices(field)]

  defp choices(:monthly_tax_reduction) do
    [
      {gettext("None (PLN 0)"), "0"},
      {gettext("PLN 100 (1/36)"), "100"},
      {gettext("PLN 150 (1/24)"), "150"},
      {gettext("PLN 300 (1/12)"), "300"}
    ]
  end

  defp choices(:employment_costs) do
    [
      {gettext("None (PLN 0)"), "none"},
      {gettext("Standard (PLN 250)"), "standard"},
      {gettext("Increased (PLN 300)"), "increased"}
    ]
  end

  defp choices(:mandate_insurance) do
    [
      {gettext("Student under 26 — no contributions"), "student"},
      {gettext("Health insurance only"), "health"},
      {gettext("Social and health insurance"), "social"},
      {gettext("Social with sickness and health insurance"), "social_with_sickness"}
    ]
  end

  defp choices(:civil_costs) do
    [
      {gettext("Standard (20%)"), "standard_20"},
      {gettext("Copyright (50%)"), "copyright_50"}
    ]
  end

  defp choices(:youth_relief) do
    [
      {gettext("Apply until age 26"), "automatic"},
      {gettext("Opted out"), "disabled"}
    ]
  end

  defp hint(:mandate_insurance),
    do: gettext("Student only with confirmed student status — age alone does not confirm it.")

  defp hint(:youth_relief), do: gettext("Applying it requires a date of birth in account settings.")

  defp hint(_field), do: nil
end
