defmodule Firmowid.Timetracker.Actions.NotifyAdminsAboutHoursRecordChange do
  @moduledoc "Delivers submitted hours record change requests to organization administrators."
  use Ash.Resource.Actions.Implementation
  use Gettext, backend: Firmowid.Gettext
  use Phoenix.Component

  import Firmowid.Mailer.Components
  import Swoosh.Email, except: [assign: 3]

  alias Firmowid.Core
  alias Firmowid.Mailer
  alias Firmowid.Scope
  alias Firmowid.SystemActor
  alias Firmowid.Timetracker.HoursRecord
  alias FirmowidWeb.Management.Utilities.Navigation

  @impl true
  def run(%{arguments: %{signal: signal}}, _opts, _context) do
    organization_id = signal.organization_id

    scope = %Scope{
      actor: %SystemActor{org_id: organization_id, role: :hours_record_change_notifier},
      tenant: organization_id
    }

    with {:ok, record} <- HoursRecord.get(signal.hours_record_id, scope: scope),
         {:ok, admins} <- Core.list_users(%{status: :active, role: :admin}, scope: scope),
         {:ok, _email} <- deliver(record, admins) do
      :ok
    end
  end

  defp deliver(_record, []), do: {:error, :no_organization_admins}

  defp deliver(record, admins) do
    Gettext.with_locale(Firmowid.Gettext, "pl", fn ->
      employee = record.member.name || to_string(record.member.user.email)
      employee_email = to_string(record.member.user.email)
      month = Date.new!(record.year, record.month, 1)

      url =
        FirmowidWeb.Core.Endpoint.url() <>
          Navigation.employee_path(record.member.user_id, %{miesiac: month})

      kind =
        case record.change_request_kind do
          :correction -> gettext("Correction")
          :cancellation -> gettext("Cancellation")
        end

      body =
        gettext(
          "Employee: %{employee}\nPeriod: %{month}/%{year}\nRequest: %{kind}\nReason: %{reason}\n\nReview this request in Firmowid: %{url}\nThis email is a notification only. Accept or reject the request in the application.",
          employee: employee,
          month: record.month,
          year: record.year,
          kind: kind,
          reason: record.change_request_reason,
          url: url
        )

      assigns = %{
        headline: headline(record.change_request_kind, employee, month),
        reason: record.change_request_reason,
        employee_email: employee_email,
        url: url
      }

      Swoosh.Email.new()
      |> to(Enum.map(admins, &to_string(&1.email)))
      |> from({"Firmowid", "piotr@firmowid.pl"})
      |> reply_to(employee_email)
      |> subject(gettext("Hours record change request"))
      |> text_body(body)
      |> html_body(to_html(html(assigns)))
      |> Mailer.deliver()
    end)
  end

  defp headline(kind, employee, month) do
    period =
      Firmowid.Cldr.Date.to_string!(month,
        format: "LLLL y",
        locale: Gettext.get_locale(Firmowid.Gettext)
      )

    case kind do
      :correction ->
        gettext("%{employee} asks to correct the hours record for %{period}",
          employee: employee,
          period: period
        )

      :cancellation ->
        gettext("%{employee} asks to cancel the hours record for %{period}",
          employee: employee,
          period: period
        )
    end
  end

  defp html(assigns) do
    ~H"""
    <.email preheader={@reason} figure={:hourglass}>
      <:headline>{@headline}</:headline>
      <.quotation label={gettext("Reason")}>{@reason}</.quotation>
      <.paragraph>
        {gettext("Replies to this email go to %{email}.", email: @employee_email)}
      </.paragraph>
      <.button href={@url}>{gettext("Review the request")}</.button>
      <:footer>
        <.note>
          {gettext("You receive this email as an organization administrator in Firmowid.")}
        </.note>
        <.fallback_link href={@url} />
      </:footer>
    </.email>
    """
  end
end
