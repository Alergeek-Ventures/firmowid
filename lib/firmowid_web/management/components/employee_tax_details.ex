defmodule FirmowidWeb.Management.Components.EmployeeTaxDetails do
  @moduledoc "Shows effective employee declarations, with separate creation, correction and history views."
  use FirmowidWeb, :live_component

  import FirmowidUI.Components.Button
  import FirmowidWeb.Management.Components.Card

  alias Firmowid.Ash.Payroll
  alias Firmowid.Ash.Payroll.MemberTaxDeclaration
  alias FirmowidWeb.Infrastructure.Utilities.TimeFormatter
  alias Phoenix.LiveView.JS

  @additional_fields [:pit0, :preferential, :copyright_costs]

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:declarations, fn ->
       Payroll.list_tax_declarations!(%{member_id: assigns.member_id}, scope: assigns.scope)
     end)
     |> assign_new(:dialog, fn -> nil end)
     |> assign_new(:form, fn -> nil end)
     |> assign_new(:no_additional, fn -> false end)}
  end

  @impl true
  def render(assigns) do
    current = current_declaration(assigns.declarations)

    assigns =
      assigns
      |> assign(:current, current)
      |> assign(:summary_fields, summary_fields(assigns.contract_type))
      |> assign(:additional_fields, @additional_fields)
      |> assign(:editing?, assigns.dialog == :new or match?({:correction, _}, assigns.dialog))

    ~H"""
    <div id={@id} class="min-w-0">
      <.card class="h-full" dimmed={@archived}>
        <.card_header>
          {gettext("Taxes and insurance")}
          <:actions>
            <.button
              :if={@contract_type in [:uop, :uz, :uod]}
              id="edit-tax-declarations"
              type="button"
              variant="ghost"
              size="small"
              phx-click="new-declaration"
              phx-target={@myself}
              aria-label={gettext("Change declarations")}
              title={gettext("Change declarations")}
            >
              <Lucideicons.square_pen class="size-4" />
            </.button>
          </:actions>
        </.card_header>

        <%= cond do %>
          <% @contract_type == :b2b -> %>
            <p class="text-sm/snug text-grey-600">
              {gettext("B2B contractor taxes are not employee payroll deductions.")}
            </p>
          <% is_nil(@contract_type) -> %>
            <p class="text-sm/snug text-grey-600">
              {gettext("Set the contract in the employee profile.")}
            </p>
          <% @current -> %>
            <p class="text-xs/snug text-grey-600">
              {gettext("Effective from %{date}", date: format_date(@current.applies_from))}
            </p>
            <dl class="grid grid-cols-[minmax(0,1fr)_minmax(0,1fr)] gap-x-4 gap-y-3 text-sm/snug">
              <%= for key <- @summary_fields do %>
                <dt class="text-grey-600">{summary_label(key)}</dt>
                <dd class={[
                  "text-end text-balance",
                  is_nil(Map.fetch!(@current, key)) && "text-grey-400"
                ]}>
                  {display_value(key, Map.fetch!(@current, key))}
                </dd>
              <% end %>
            </dl>
            <p :if={not no_additional?(@current)} class="text-xs/snug text-grey-600">
              {gettext("Other tax preferences need review before calculation.")}
            </p>
          <% true -> %>
            <div class="flex flex-col gap-3">
              <p class="text-sm/snug text-grey-600">
                {gettext("No declarations are effective today.")}
              </p>
              <.button
                type="button"
                variant="outline"
                size="small"
                class="self-start"
                phx-click="new-declaration"
                phx-target={@myself}
              >
                {gettext("Add declarations")}
              </.button>
            </div>
        <% end %>

        <div class="flex flex-wrap items-center justify-between gap-3 border-bs border-grey-200 pbs-4">
          <.button
            type="button"
            variant="ghost"
            size="small"
            phx-click="show-history"
            phx-target={@myself}
            disabled={@declarations == []}
          >
            {gettext("History (%{count})", count: length(@declarations))}
          </.button>
          <.live_component
            :if={@contract_type != :b2b}
            module={FirmowidWeb.Management.Components.EmployeePayoutCalculator}
            id="employee-payout-calculator"
            member_id={@member_id}
            scope={@scope}
            contract_type={@contract_type}
            declarations={@declarations}
            archived={@archived}
          />
        </div>
      </.card>

      <.modal
        :if={@dialog}
        id={"#{@id}-dialog"}
        show
        class="max-w-xl!"
        on_cancel={JS.push("close-tax-dialog", target: @myself)}
      >
        <div class="flex flex-col gap-6">
          <header class="flex flex-col gap-2 pe-5">
            <h2 id={"#{@id}-dialog-title"} class="text-lg/snug font-medium">
              {dialog_title(@dialog)}
            </h2>
            <p id={"#{@id}-dialog-description"} class="text-sm/snug text-grey-600">
              {dialog_description(@dialog)}
            </p>
          </header>

          <%= if @dialog == :history do %>
            <details :for={declaration <- @declarations} class="border-bs border-grey-200 pbs-4">
              <summary class="flex min-h-11 cursor-pointer items-center justify-between gap-3 rounded-sm text-sm/snug outline-offset-4 focus-visible:outline-2 focus-visible:outline-turquoise-700 active:bg-grey-100">
                <span class="font-medium">{format_date(declaration.applies_from)}</span>
                <span class="text-xs/snug text-grey-600">{version_status(declaration, @current)}</span>
              </summary>
              <div class="flex flex-col gap-4 pbs-3">
                <p class="text-xs/snug text-grey-600">
                  {gettext("Received on %{date}", date: format_date(declaration.received_on))}
                </p>
                <dl class="grid grid-cols-[minmax(0,1fr)_minmax(0,1fr)] gap-x-4 gap-y-3 text-sm/snug">
                  <%= for field <- recorded_fields(declaration) do %>
                    <dt class="text-grey-600">{field.label}</dt>
                    <dd class="text-end text-balance">
                      {display_value(field.key, Map.fetch!(declaration, field.key))}
                    </dd>
                  <% end %>
                </dl>
                <.button
                  :if={@contract_type in [:uop, :uz, :uod]}
                  type="button"
                  variant="outline"
                  size="small"
                  class="self-start"
                  phx-click="correct-declaration"
                  phx-value-id={declaration.id}
                  phx-target={@myself}
                >
                  {gettext("Correct this version")}
                </.button>
              </div>
            </details>
          <% end %>

          <.form
            :if={@editing?}
            for={@form}
            id="employee-tax-declaration-form"
            phx-change="validate-tax-declaration"
            phx-submit="save-tax-declaration"
            phx-target={@myself}
            class="flex flex-col gap-5"
          >
            <div class="grid grid-cols-[repeat(auto-fit,minmax(min(100%,12rem),1fr))] gap-4">
              <.declaration_field form={@form} field={definition(:received_on)} />
              <.declaration_field
                form={@form}
                field={definition(:applies_from)}
                readonly={match?({:correction, _}, @dialog)}
              />
            </div>
            <p class="text-xs/snug text-grey-600">
              {gettext("Leave unconfirmed information blank.")}
            </p>
            <.declaration_field
              :for={key <- editor_fields(@contract_type)}
              form={@form}
              field={definition(key)}
            />
            <.declaration_field
              :if={selected?(@form, :student, true) and @contract_type == :uz}
              form={@form}
              field={definition(:student_until)}
            />
            <.declaration_field
              :if={
                @contract_type == :uz and not selected?(@form, :student, true) and
                  not selected?(@form, :other_employment, :at_least_minimum)
              }
              form={@form}
              field={definition(:sickness)}
            />
            <.declaration_field form={@form} field={definition(:ppk)} />
            <.declaration_field
              :if={selected?(@form, :ppk, :participant)}
              form={@form}
              field={definition(:ppk_employee_rate)}
            />

            <div class="border-bs border-grey-200 pbs-4">
              <.input
                id="declaration-no-additional"
                name="declaration_context[no_additional]"
                type="checkbox"
                checked={@no_additional}
                value="true"
                label={gettext("No other tax preferences or copyright costs")}
              />
            </div>
            <details :if={not @no_additional} id="additional-tax-declarations" class="text-sm/snug">
              <summary class="min-h-11 cursor-pointer rounded-sm font-medium outline-offset-4 focus-visible:outline-2 focus-visible:outline-turquoise-700 active:bg-grey-100">
                {gettext("Other declarations (record only)")}
              </summary>
              <div class="flex flex-col gap-5 pbs-3">
                <.declaration_field
                  :for={key <- @additional_fields}
                  form={@form}
                  field={definition(key)}
                />
              </div>
            </details>
            <.declaration_field
              :if={annual_request?(@form)}
              form={@form}
              field={definition(:request_year)}
            />

            <div class="flex flex-wrap justify-end gap-3 border-bs border-grey-200 pbs-5">
              <.button
                type="button"
                variant="ghost"
                size="small"
                phx-click="close-tax-dialog"
                phx-target={@myself}
              >{gettext("Cancel")}</.button>
              <.button size="small" phx-disable-with={gettext("Saving...")}>
                {if @dialog == :new,
                  do: gettext("Save new declaration"),
                  else: gettext("Save correction")}
              </.button>
            </div>
          </.form>
        </div>
      </.modal>
    </div>
    """
  end

  @impl true
  def handle_event("new-declaration", _params, socket), do: {:noreply, open_editor(socket, :new)}

  def handle_event("show-history", _params, socket), do: {:noreply, assign(socket, dialog: :history, form: nil)}

  def handle_event("close-tax-dialog", _params, socket), do: {:noreply, assign(socket, dialog: nil, form: nil)}

  def handle_event("correct-declaration", %{"id" => id}, socket) do
    if Enum.any?(socket.assigns.declarations, &(&1.id == id)) do
      {:noreply, open_editor(socket, {:correction, id})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("validate-tax-declaration", %{"declaration" => params} = event, socket) do
    no_additional = get_in(event, ["declaration_context", "no_additional"]) == "true"
    params = declaration_params(params, no_additional, socket)

    {:noreply,
     assign(socket,
       form: AshPhoenix.Form.validate(socket.assigns.form, params),
       no_additional: no_additional
     )}
  end

  def handle_event("save-tax-declaration", %{"declaration" => params} = event, socket) do
    no_additional = get_in(event, ["declaration_context", "no_additional"]) == "true"
    params = declaration_params(params, no_additional, socket)

    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, _declaration} ->
        declarations =
          Payroll.list_tax_declarations!(%{member_id: socket.assigns.member_id},
            scope: socket.assigns.scope
          )

        {:noreply, assign(socket, declarations: declarations, dialog: nil, form: nil)}

      {:error, form} ->
        {:noreply, assign(socket, form: form, no_additional: no_additional)}
    end
  end

  defp open_editor(socket, dialog) do
    record = editor_record(dialog, socket.assigns.declarations)
    params = record_params(record)

    params =
      if dialog == :new, do: Map.drop(params, ["received_on", "applies_from"]), else: params

    params = Map.put(params, "member_id", socket.assigns.member_id)

    action = if dialog == :new, do: :create_version, else: :save_tax_declaration

    form =
      MemberTaxDeclaration
      |> AshPhoenix.Form.for_create(action,
        scope: socket.assigns.scope,
        as: "declaration",
        params: params,
        post_process_errors: &declaration_form_error/3
      )
      |> to_form()

    assign(socket,
      dialog: dialog,
      form: form,
      no_additional: not is_nil(record) and no_additional?(record)
    )
  end

  defp declaration_params(params, no_additional, socket) do
    record = editor_record(socket.assigns.dialog, socket.assigns.declarations)
    base = record_params(record)

    base =
      if socket.assigns.dialog == :new,
        do: Map.drop(base, ["received_on", "applies_from"]),
        else: base

    params = Map.merge(base, params)

    params =
      cond do
        no_additional ->
          Map.merge(params, %{
            "pit0" => "none",
            "preferential" => "none",
            "copyright_costs" => "false"
          })

        socket.assigns.no_additional ->
          Map.merge(params, %{"pit0" => "", "preferential" => "", "copyright_costs" => ""})

        true ->
          params
      end

    params =
      if match?({:correction, _}, socket.assigns.dialog) do
        Map.put(params, "applies_from", record.applies_from)
      else
        params
      end

    Map.put(params, "member_id", socket.assigns.member_id)
  end

  # Ash attaches the compound member/date uniqueness error to member_id, which
  # is server-owned and has no editable input. The effective date is the conflict.
  defp declaration_form_error(_form, _path, {:member_id, "has already been taken", vars}),
    do: {:applies_from, "has already been taken", vars}

  defp declaration_form_error(_form, _path, error), do: error

  defp record_params(nil), do: %{}

  defp record_params(record) do
    Map.new(definitions(), fn field ->
      {Atom.to_string(field.key), Map.fetch!(record, field.key)}
    end)
  end

  defp editor_record(:new, declarations), do: current_declaration(declarations)
  defp editor_record({:correction, id}, declarations), do: Enum.find(declarations, &(&1.id == id))

  defp current_declaration(declarations),
    do: Enum.find(declarations, &(Date.compare(&1.applies_from, Date.utc_today()) != :gt))

  defp no_additional?(record),
    do: record.pit0 == :none and record.preferential == :none and record.copyright_costs == false

  defp summary_fields(:uop), do: [:tax_residency, :pit2, :employee_costs, :youth_relief, :tax_mode, :ppk]

  defp summary_fields(:uz), do: [:pit2, :youth_relief, :student, :other_employment, :sickness, :ppk]

  defp summary_fields(:uod), do: [:tax_residency, :pit2, :own_employer, :tax_mode]
  defp summary_fields(_type), do: [:tax_residency, :pit2, :ppk]

  defp editor_fields(:uop), do: [:tax_residency, :pit2, :employee_costs, :youth_relief, :tax_mode]

  defp editor_fields(:uz),
    do: [:tax_residency, :pit2, :youth_relief, :tax_mode, :student, :other_employment, :own_employer]

  defp editor_fields(:uod), do: [:tax_residency, :pit2, :tax_mode, :own_employer]
  defp editor_fields(_type), do: [:tax_residency, :pit2]

  defp recorded_fields(record),
    do: Enum.reject(definitions(), &(&1.key in [:received_on, :applies_from] or is_nil(Map.fetch!(record, &1.key))))

  defp annual_request?(form),
    do:
      selected?(form, :tax_mode, :no_advance) or
        Enum.any?([:joint_below, :joint_above, :single_below, :single_above], &selected?(form, :preferential, &1))

  defp selected?(form, field, value), do: form[field].value in [value, to_string(value)]

  defp summary_label(:pit2), do: "PIT-2"
  defp summary_label(:ppk), do: "PPK"
  defp summary_label(:employee_costs), do: gettext("Tax costs")
  defp summary_label(key), do: definition(key).label

  defp display_value(_key, nil), do: gettext("Not established")
  defp display_value(_key, %Date{} = value), do: format_date(value)
  defp display_value(:pit2, :one_twelfth), do: Money.new!(:PLN, 300)
  defp display_value(:pit2, :one_twenty_fourth), do: Money.new!(:PLN, 150)
  defp display_value(:pit2, :one_thirty_sixth), do: Money.new!(:PLN, 100)
  defp display_value(:employee_costs, :standard), do: Money.new!(:PLN, 250)
  defp display_value(:employee_costs, :elevated), do: Money.new!(:PLN, 300)
  defp display_value(:employee_costs, :none), do: gettext("Not applied")
  defp display_value(:youth_relief, :waived), do: gettext("Not applied")
  defp display_value(:youth_relief, :apply), do: gettext("When eligible")
  defp display_value(:tax_mode, :standard), do: gettext("General rules")
  defp display_value(:tax_mode, :higher), do: "32%"
  defp display_value(:tax_mode, :no_advance), do: gettext("Not collected")
  defp display_value(:ppk_employee_rate, value), do: gettext("%{rate}%", rate: to_string(value))
  defp display_value(:request_year, value), do: to_string(value)

  defp display_value(key, value) do
    {label, ^value} =
      Enum.find(definition(key).options, fn {_label, option} -> option == value end)

    label
  end

  defp format_date(date), do: TimeFormatter.format_date(date)

  defp version_status(declaration, %{id: id}) when declaration.id == id, do: gettext("Effective today")

  defp version_status(declaration, _current) do
    if Date.after?(declaration.applies_from, Date.utc_today()),
      do: gettext("Scheduled"),
      else: gettext("Previous version")
  end

  defp dialog_title(:history), do: gettext("Declaration history")
  defp dialog_title(:new), do: gettext("New declaration")
  defp dialog_title({:correction, _id}), do: gettext("Correct declaration")

  defp dialog_description(:history), do: gettext("Open a version to review its recorded information.")

  defp dialog_description(:new), do: gettext("Choose when the changes take effect. Previous versions are kept.")

  defp dialog_description({:correction, _id}),
    do: gettext("This corrects the stored version. Its effective date stays unchanged.")

  attr :form, :any, required: true
  attr :field, :map, required: true
  attr :readonly, :boolean, default: false

  defp declaration_field(assigns) do
    ~H"""
    <.input
      field={@form[@field.key]}
      label={@field.label}
      type={@field.type}
      options={[{gettext("Not established"), ""} | @field.options]}
      readonly={@readonly}
      min={if @field.key == :request_year, do: "2022", else: if(@field.type == "number", do: "0.5")}
      max={if @field.key == :request_year, do: "2100", else: if(@field.type == "number", do: "4")}
      step={if @field.key == :request_year, do: "1", else: if(@field.type == "number", do: "0.01")}
      container_class="min-w-0"
      new
    />
    """
  end

  defp definition(key), do: Enum.find(definitions(), &(&1.key == key))

  defp field(key, label, type, options \\ []), do: %{key: key, label: label, type: type, options: options}

  defp yes_no, do: [{gettext("Yes"), true}, {gettext("No"), false}]

  defp definitions do
    [
      field(:received_on, gettext("Declaration received on"), "date"),
      field(:applies_from, gettext("Apply from"), "date"),
      field(:tax_residency, gettext("Tax residency"), "select", [
        {gettext("Poland"), :poland},
        {gettext("Other country"), :other}
      ]),
      field(:pit2, gettext("Monthly PIT-2 reduction"), "select", [
        {gettext("No reduction"), :none},
        {"300 PLN (1/12)", :one_twelfth},
        {"150 PLN (1/24)", :one_twenty_fourth},
        {"100 PLN (1/36)", :one_thirty_sixth}
      ]),
      field(:employee_costs, gettext("Tax-deductible costs"), "select", [
        {gettext("Do not apply"), :none},
        {gettext("Standard — PLN 250"), :standard},
        {gettext("Elevated — PLN 300"), :elevated}
      ]),
      field(:youth_relief, gettext("Youth tax relief"), "select", [
        {gettext("Apply when eligible"), :apply},
        {gettext("Do not apply"), :waived}
      ]),
      field(:tax_mode, gettext("Tax advances"), "select", [
        {gettext("Standard withholding"), :standard},
        {gettext("Higher rate — 32%"), :higher},
        {gettext("No advances (record only)"), :no_advance}
      ]),
      field(:student, gettext("Pupil or student"), "select", yes_no()),
      field(:student_until, gettext("Student status confirmed through"), "date"),
      field(:other_employment, gettext("Other insurance title"), "select", [
        {gettext("No other title"), :none},
        {gettext("Other employment below minimum wage"), :below_minimum},
        {gettext("Other employment at least minimum wage"), :at_least_minimum},
        {gettext("Other situation requiring individual assessment"), :other}
      ]),
      field(:own_employer, gettext("Contract with own employer"), "select", yes_no()),
      field(:sickness, gettext("Voluntary sickness insurance"), "select", yes_no()),
      field(:ppk, gettext("PPK participation"), "select", [
        {gettext("Not participating"), :none},
        {gettext("Participating"), :participant}
      ]),
      field(:ppk_employee_rate, gettext("Employee PPK rate (%)"), "number"),
      field(:pit0, gettext("Other PIT-0 exemption declaration"), "select", [
        {gettext("None"), :none},
        {gettext("Return to Poland"), :returning},
        {gettext("Families with four or more children"), :family},
        {gettext("Working seniors"), :senior}
      ]),
      field(:preferential, gettext("Preferential advance calculation declaration"), "select", [
        {gettext("None"), :none},
        {gettext("Joint — own income up to PLN 120,000"), :joint_below},
        {gettext("Joint — own income above PLN 120,000"), :joint_above},
        {gettext("Single parent — own income up to PLN 120,000"), :single_below},
        {gettext("Single parent — own income above PLN 120,000"), :single_above}
      ]),
      field(:copyright_costs, gettext("Apply 50% copyright costs"), "select", yes_no()),
      field(:request_year, gettext("Tax year of the annual request"), "number")
    ]
  end
end
