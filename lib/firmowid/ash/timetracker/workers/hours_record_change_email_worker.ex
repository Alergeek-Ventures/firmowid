defmodule Firmowid.Ash.Timetracker.Workers.HoursRecordChangeEmailWorker do
  @moduledoc "Delivers submitted hours record change requests to organization administrators."
  use Oban.Worker, queue: :default, max_attempts: 3
  use Gettext, backend: FirmowidWeb.Core.Gettext

  import Swoosh.Email, except: [new: 0, new: 1]

  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor
  alias Firmowid.Ash.Timetracker.HoursRecord
  alias Firmowid.Mailer
  alias FirmowidWeb.Management.Utilities.Navigation

  @doc "Queues a notification in the same transaction as the saved request."
  @spec enqueue(Ash.UUID.t(), Ash.UUID.t()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue(record_id, organization_id) do
    %{record_id: record_id, organization_id: organization_id}
    |> new()
    |> Firmowid.Oban.insert(organization_id: organization_id)
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"record_id" => id, "organization_id" => organization_id}}) do
    scope = %Scope{
      actor: %SystemActor{org_id: organization_id, role: :hours_record_change_notifier},
      tenant: organization_id
    }

    with {:ok, record} <- HoursRecord.get(id, scope: scope),
         {:ok, admins} <- Core.list_users(%{status: :active, role: :admin}, scope: scope) do
      deliver(record, admins)
    end
  end

  defp deliver(_record, []), do: {:error, :no_organization_admins}

  defp deliver(record, admins) do
    Gettext.with_locale(FirmowidWeb.Core.Gettext, "pl", fn ->
      kind =
        case record.change_request_kind do
          :correction -> gettext("Correction")
          :cancellation -> gettext("Cancellation")
        end

      body =
        gettext(
          "Employee: %{employee}\nPeriod: %{month}/%{year}\nRequest: %{kind}\nReason: %{reason}\n\nReview this request in Firmowid: %{url}\nThis email is a notification only. Accept or reject the request in the application.",
          employee: record.user.name || to_string(record.user.email),
          month: record.month,
          year: record.year,
          kind: kind,
          reason: record.change_request_reason,
          url:
            FirmowidWeb.Core.Endpoint.url() <>
              Navigation.employee_path(record.user_id, %{
                miesiac: Date.new!(record.year, record.month, 1)
              })
        )

      Swoosh.Email.new()
      |> to(Enum.map(admins, &to_string(&1.email)))
      |> from({"Firmowid", "piotr@firmowid.pl"})
      |> reply_to(to_string(record.user.email))
      |> subject(gettext("Hours record change request"))
      |> text_body(body)
      |> Mailer.deliver()
    end)
  end
end
