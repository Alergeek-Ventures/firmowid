defmodule Firmowid.Ash.Timetracker.Actions.NotifyAdminsAboutHoursRecordChange do
  @moduledoc "Delivers submitted hours record change requests to organization administrators."
  use Ash.Resource.Actions.Implementation
  use Gettext, backend: Firmowid.Gettext

  import Swoosh.Email

  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor
  alias Firmowid.Ash.Timetracker.HoursRecord
  alias Firmowid.Mailer
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
      kind =
        case record.change_request_kind do
          :correction -> gettext("Correction")
          :cancellation -> gettext("Cancellation")
        end

      body =
        gettext(
          "Employee: %{employee}\nPeriod: %{month}/%{year}\nRequest: %{kind}\nReason: %{reason}\n\nReview this request in Firmowid: %{url}\nThis email is a notification only. Accept or reject the request in the application.",
          employee: record.member.name || to_string(record.member.user.email),
          month: record.month,
          year: record.year,
          kind: kind,
          reason: record.change_request_reason,
          url:
            FirmowidWeb.Core.Endpoint.url() <>
              Navigation.employee_path(record.member.user_id, %{
                miesiac: Date.new!(record.year, record.month, 1)
              })
        )

      Swoosh.Email.new()
      |> to(Enum.map(admins, &to_string(&1.email)))
      |> from({"Firmowid", "piotr@firmowid.pl"})
      |> reply_to(to_string(record.member.user.email))
      |> subject(gettext("Hours record change request"))
      |> text_body(body)
      |> Mailer.deliver()
    end)
  end
end
