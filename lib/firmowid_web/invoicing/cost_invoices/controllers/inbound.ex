defmodule FirmowidWeb.Invoicing.CostInvoices.Controllers.Inbound do
  @moduledoc false
  use FirmowidWeb, :controller

  alias Ash.Error.Invalid
  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Invoicing.InboundEmail
  alias Firmowid.Ash.Invoicing.Workers.InboundEmailWorker
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor
  alias Firmowid.ErrorKind

  require Logger

  def handle_webhook(conn, %{"type" => "email.received", "data" => data}) do
    with {:ok, org_id} <- extract_org_id_from_recipients(Map.get(data, "to", [])),
         _org = Core.get_organization!(org_id),
         attrs = build_inbound_email_attrs(data, org_id),
         {:ok, inbound_email} <- create_inbound_email(attrs, org_id) do
      enqueue_processing(inbound_email, org_id)
      log_success(org_id, inbound_email, data)
      json(conn, %{status: "ok"})
    else
      {:error, :no_valid_recipient} ->
        Logger.warning("Inbound email with no valid recipient address")
        json(conn, %{status: "ok", message: "no valid recipient"})

      {:error, :not_found} ->
        Logger.warning("Inbound email for non-existent organization")
        json(conn, %{status: "ok", message: "organization not found"})

      {:error, %Invalid{} = error} ->
        handle_ash_error(conn, error, data)
    end
  end

  def handle_webhook(conn, params) do
    key_count = if(is_map(params), do: map_size(params), else: 0)
    Logger.warning("Unknown webhook type received: key_count=#{key_count}")
    json(conn, %{status: "ok", message: "unknown type"})
  end

  # Extract org_id from recipient email (format: {nickname}@firmowid.pl)
  defp extract_org_id_from_recipients(to_addresses) when is_list(to_addresses) do
    to_addresses
    |> Enum.find_value(&parse_recipient_email/1)
    |> case do
      nil -> {:error, :no_valid_recipient}
      result -> result
    end
  end

  defp extract_org_id_from_recipients(_), do: {:error, :no_valid_recipient}

  defp parse_recipient_email(email) do
    case String.split(email, "@") do
      [nickname, "firmowid.pl"] ->
        case Core.get_organization_by_nickname(nickname) do
          {:ok, nil} -> nil
          {:ok, org} -> {:ok, org.id}
          {:error, _} -> nil
        end

      _ ->
        nil
    end
  end

  defp parse_timestamp(nil), do: DateTime.utc_now()

  defp parse_timestamp(timestamp_string) when is_binary(timestamp_string) do
    case DateTime.from_iso8601(timestamp_string) do
      {:ok, datetime, _offset} -> datetime
      {:error, _} -> DateTime.utc_now()
    end
  end

  defp parse_timestamp(_), do: DateTime.utc_now()

  defp build_inbound_email_attrs(data, _org_id) do
    %{
      resend_email_id: Map.get(data, "email_id"),
      sender_email: Map.get(data, "from"),
      subject: Map.get(data, "subject"),
      received_at: parse_timestamp(Map.get(data, "created_at"))
    }
  end

  defp create_inbound_email(attrs, org_id) do
    InboundEmail.create(attrs, scope: inbound_email_scope(org_id))
  end

  defp inbound_email_scope(org_id) do
    %Scope{actor: %SystemActor{org_id: org_id, role: :cost_invoice_processor}, tenant: org_id}
  end

  defp enqueue_processing(inbound_email, org_id) do
    %{inbound_email_id: inbound_email.id, organization_id: org_id}
    |> InboundEmailWorker.new()
    |> Firmowid.Oban.insert(skip_organization_id: true)
  end

  defp log_success(org_id, inbound_email, data) do
    Logger.info("Inbound email received",
      organization_id: org_id,
      inbound_email_id: inbound_email.id,
      attachment_count: attachment_count(data)
    )
  end

  defp attachment_count(data) do
    case Map.get(data, "attachments", []) do
      attachments when is_list(attachments) -> length(attachments)
      _other -> 0
    end
  end

  defp handle_ash_error(conn, error, _data) do
    if duplicate_resend_email?(error) do
      Logger.debug("Duplicate inbound email webhook received")
      json(conn, %{status: "ok", message: "already processed"})
    else
      Logger.error("Failed to create inbound_email record: error_kind=#{ErrorKind.classify(error)}")

      json(conn, %{status: "error", message: "failed to create record"})
    end
  end

  defp duplicate_resend_email?(%Invalid{errors: errors}) do
    Enum.any?(errors, fn
      %Ash.Error.Changes.InvalidChanges{fields: fields} ->
        :resend_email_id in fields

      _ ->
        false
    end)
  end

  defp duplicate_resend_email?(_), do: false
end
