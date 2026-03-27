defmodule FirmowidWeb.ResendInboundController do
  use FirmowidWeb, :controller

  alias Firmowid.Accounts
  alias Firmowid.Accounts.Organization
  alias Firmowid.CostInvoices.InboundEmail
  alias Firmowid.CostInvoices.InboundEmailWorker
  alias Firmowid.Repo

  require Logger

  def handle_webhook(conn, %{"type" => "email.received", "data" => data}) do
    with {:ok, org_id} <- extract_org_id_from_recipients(Map.get(data, "to", [])),
         {:ok, _org} <- Accounts.get_organization(org_id),
         attrs = build_inbound_email_attrs(data, org_id),
         {:ok, inbound_email} <- create_inbound_email(attrs, org_id) do
      enqueue_processing(inbound_email, org_id)
      log_success(org_id, data)
      json(conn, %{status: "ok"})
    else
      {:error, :no_valid_recipient} ->
        Logger.warning("Inbound email with no valid recipient address")
        json(conn, %{status: "ok", message: "no valid recipient"})

      {:error, :not_found} ->
        Logger.warning("Inbound email for non-existent organization")
        json(conn, %{status: "ok", message: "organization not found"})

      {:error, %Ecto.Changeset{errors: errors}} ->
        handle_changeset_error(conn, errors, data)
    end
  end

  def handle_webhook(conn, params) do
    Logger.warning("Unknown webhook type received: #{inspect(params)}")
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
        # Look up organization by nickname
        case Repo.get_by(Organization, [inbound_email_nickname: nickname], skip_organization_id: true) do
          nil -> nil
          org -> {:ok, org.id}
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

  defp build_inbound_email_attrs(data, org_id) do
    %{
      organization_id: org_id,
      resend_email_id: Map.get(data, "email_id"),
      sender_email: Map.get(data, "from"),
      subject: Map.get(data, "subject"),
      received_at: parse_timestamp(Map.get(data, "created_at"))
    }
  end

  defp create_inbound_email(attrs, org_id) do
    Repo.put_org_id(org_id)

    %InboundEmail{}
    |> InboundEmail.changeset(attrs)
    |> Repo.insert()
  end

  defp enqueue_processing(inbound_email, org_id) do
    Repo.put_org_id(org_id)

    %{inbound_email_id: inbound_email.id, organization_id: org_id}
    |> InboundEmailWorker.new()
    |> Firmowid.Oban.insert([])
  end

  defp log_success(org_id, data) do
    Logger.info("Inbound email received",
      org_id: org_id,
      sender: Map.get(data, "from"),
      resend_email_id: Map.get(data, "email_id")
    )
  end

  defp handle_changeset_error(conn, errors, data) do
    if Keyword.has_key?(errors, :resend_email_id) do
      Logger.debug("Duplicate webhook received: #{Map.get(data, "email_id")}")
      json(conn, %{status: "ok", message: "already processed"})
    else
      Logger.error("Failed to create inbound_email record: #{inspect(errors)}")
      json(conn, %{status: "error", message: "failed to create record"})
    end
  end
end
