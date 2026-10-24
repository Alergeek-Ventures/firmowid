defmodule Firmowid.Ash.Core.OrganizationExternalCleanup do
  @moduledoc """
  Best-effort cleanup of organization-owned remote data before local deletion.

  Reports only stable failure categories and identifiers for manual recovery;
  never sends remote responses, object keys or credential material to Sentry.
  """

  alias Ash.Error.Forbidden
  alias Ash.Error.Framework
  alias Ash.Error.Invalid
  alias Ash.Error.Unknown
  alias Firmowid.Ash.Finances.GoCardless.ApiClient
  alias Firmowid.Ash.Ksef
  alias Firmowid.Ash.Ksef.CredentialMetadata
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor
  alias Firmowid.ErrorKind
  alias Firmowid.Sentry

  require Logger

  @doc "Attempt each remote cleanup independently and report failures."
  @spec run(String.t(), [String.t()]) :: :ok
  def run(organization_id, requisition_ids) do
    # The caller has authorized organization deletion. Use this tenant-bound
    # system role only for KSeF, not for parent authorization or other cleanup.
    ksef_scope = %Scope{
      actor: %SystemActor{org_id: organization_id, role: :ksef_session},
      tenant: organization_id
    }

    # Capture the recovery identifier before cleanup can erase credentials.
    ksef_identifiers = ksef_identifiers(organization_id, ksef_scope)

    attempt(organization_id, "s3", "delete_objects", %{}, fn ->
      Firmowid.S3Client.delete_organization_objects(organization_id)
    end)

    Enum.each(requisition_ids, fn requisition_id ->
      attempt(
        organization_id,
        "gocardless",
        "delete_requisition",
        %{requisition_id: requisition_id},
        fn ->
          ApiClient.delete_requisition_detailed(requisition_id)
        end
      )
    end)

    attempt(organization_id, "ksef", "unauthenticate", ksef_identifiers, fn ->
      Ksef.unauthenticate(ksef_scope)
    end)

    :ok
  end

  defp ksef_identifiers(organization_id, scope) do
    case Ksef.get_credential(scope: scope) do
      {:ok, %{auth_type: :generated_certificate} = credential} ->
        serial = CredentialMetadata.certificate_serial_number(credential)

        if Regex.match?(~r/\A[0-9A-F]{16,40}\z/, serial) do
          %{certificate_serial_number: serial}
        else
          report(
            organization_id,
            "ksef",
            "read_certificate_metadata",
            %{},
            :invalid_certificate_serial
          )

          %{}
        end

      {:ok, _credential} ->
        %{}

      {:error, reason} ->
        report(organization_id, "ksef", "read_certificate_metadata", %{}, reason)
        %{}
    end
  rescue
    error ->
      report(organization_id, "ksef", "read_certificate_metadata", %{}, error)
      %{}
  catch
    kind, _reason ->
      report(organization_id, "ksef", "read_certificate_metadata", %{}, kind)
      %{}
  end

  @doc "Log safe failure categories and send a sanitized failure report to Sentry."
  @spec report_local_failure(String.t(), String.t(), term()) :: :ok
  def report_local_failure(organization_id, step, reason) do
    Logger.error("Organization deletion failed",
      organization_id: organization_id,
      stage: step,
      error_kind: ErrorKind.classify(reason)
    )

    report(organization_id, "database", step, %{}, reason)
  end

  defp attempt(organization_id, service, step, identifiers, operation) do
    handle_result(operation.(), organization_id, service, step, identifiers)
  rescue
    error -> report(organization_id, service, step, identifiers, error)
  catch
    kind, _reason -> report(organization_id, service, step, identifiers, kind)
  end

  defp handle_result(:ok, _id, _service, _step, _identifiers), do: :ok
  defp handle_result({:ok, _}, _id, _service, _step, _identifiers), do: :ok
  defp handle_result({:error, :not_connected}, _id, "ksef", _step, _identifiers), do: :ok
  defp handle_result({:error, :not_found}, _id, "gocardless", _step, _identifiers), do: :ok
  defp handle_result({:error, :expired_eua}, _id, "gocardless", _step, _identifiers), do: :ok

  defp handle_result({:error, {:delete_failed, count}}, id, "s3", step, _identifiers) when is_integer(count),
    do: report(id, "s3", step, %{failed_count: count}, :delete_failed)

  defp handle_result({:error, {failure_step, agreement_id, reason}}, id, service, _step, identifiers)
       when failure_step in [:agreement_deletion_failed, :requisition_deletion_failed] do
    identifiers =
      case Ecto.UUID.cast(agreement_id) do
        {:ok, safe_id} -> Map.put(identifiers, :agreement_id, safe_id)
        :error -> identifiers
      end

    report(id, service, Atom.to_string(failure_step), identifiers, reason)
  end

  defp handle_result({:error, reason}, id, service, step, identifiers), do: report(id, service, step, identifiers, reason)

  defp report(organization_id, service, step, identifiers, reason) do
    extra =
      reason
      |> failure_context()
      |> Map.merge(%{
        organization_id: organization_id,
        service: service,
        step: step,
        error_kind: ErrorKind.classify(reason)
      })
      |> Map.merge(identifiers)

    case Sentry.capture_exception(RuntimeError.exception("Organization deletion cleanup failed"),
           stacktrace: failure_stacktrace(reason),
           tags: %{source: "organization_deletion", service: service},
           extra: extra
         ) do
      {:ok, _} -> :ok
      _ -> warn_capture_failed(organization_id, service, step, identifiers)
    end
  rescue
    _error -> warn_capture_failed(organization_id, service, step, identifiers)
  catch
    _kind, _reason -> warn_capture_failed(organization_id, service, step, identifiers)
  end

  defp failure_context(%module{} = reason) when module in [Invalid, Unknown, Forbidden, Framework] do
    operation_context(reason.changeset || reason.query || reason.action_input)
  end

  defp failure_context(_reason), do: %{}

  defp failure_stacktrace(%module{errors: errors} = reason) when module in [Invalid, Unknown, Forbidden, Framework] do
    Enum.find_value(errors, error_stacktrace(reason) || [], &error_stacktrace/1)
  end

  defp failure_stacktrace(reason), do: error_stacktrace(reason) || []

  defp error_stacktrace(%{stacktrace: %Splode.Stacktrace{stacktrace: [_ | _] = stacktrace}}), do: stacktrace

  defp error_stacktrace(_reason), do: nil

  defp operation_context(%module{resource: resource, action: action})
       when module in [Ash.Changeset, Ash.Query, Ash.ActionInput] do
    Map.reject(
      %{resource: Atom.to_string(resource), action: action && Atom.to_string(action.name)},
      fn {_key, value} ->
        is_nil(value)
      end
    )
  end

  defp operation_context(_operation), do: %{}

  defp warn_capture_failed(organization_id, service, step, identifiers) do
    metadata =
      identifiers
      |> Map.take([:requisition_id, :agreement_id, :certificate_serial_number])
      |> Map.merge(%{organization_id: organization_id, service: service, stage: step})
      |> Map.to_list()

    Logger.error("Failed to report organization deletion error to Sentry", metadata)
    :ok
  end
end
