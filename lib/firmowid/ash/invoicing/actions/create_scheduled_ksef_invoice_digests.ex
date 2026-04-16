defmodule Firmowid.Ash.Invoicing.Actions.CreateScheduledKsefInvoiceDigests do
  @moduledoc """
  Builds KSeF invoice digests for the most recently closed business window.
  """
  use Ash.Resource.Actions.Implementation

  alias Firmowid.Ash.Core.Organization
  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.KsefInvoiceDigest
  alias Firmowid.Ash.Invoicing.Services.KsefInvoiceDigestWindow
  alias Firmowid.Ash.SystemActor

  require Logger

  @doc false
  @impl true
  def run(input, _opts, _context) do
    with {:ok, %{window_start: window_start, window_end: window_end}} <- resolve_window(input) do
      organization_ids = input.arguments[:organization_ids]
      enqueue_send? = Map.get(input.arguments, :enqueue_send?, true)

      Logger.info(
        "Building KSeF digests for window #{DateTime.to_iso8601(window_start)} - #{DateTime.to_iso8601(window_end)} " <>
          "organization_ids=#{inspect(organization_ids || :all)} enqueue_send?=#{enqueue_send?}"
      )

      # cross_tenant_reader: enumerate all organizations for scheduled digest creation
      cross_tenant_actor = %SystemActor{org_id: nil, role: :cross_tenant_reader}

      created_count =
        Organization
        |> Ash.read!(actor: cross_tenant_actor)
        |> filter_organizations(organization_ids)
        |> Enum.reduce(0, fn organization, acc ->
          case create_digest_for_organization(
                 organization,
                 window_start,
                 window_end,
                 enqueue_send?
               ) do
            :created -> acc + 1
            :skipped -> acc
          end
        end)

      {:ok, created_count}
    end
  end

  defp create_digest_for_organization(organization, window_start, window_end, enqueue_send?) do
    actor = %SystemActor{org_id: organization.id, role: :ksef_digest}
    invoice_ids = invoice_ids_for_window(organization, window_start, window_end, actor)

    Logger.info(
      "KSeF digest candidate organization_id=#{organization.id} organization_name=#{organization.name} " <>
        "invoice_count=#{length(invoice_ids)}"
    )

    cond do
      digest_exists?(organization.id, window_start, window_end, actor) ->
        Logger.info(
          "Skipping KSeF digest for organization_id=#{organization.id} organization_name=#{organization.name}: " <>
            "digest already exists for window"
        )

        :skipped

      invoice_ids == [] ->
        Logger.info(
          "Skipping KSeF digest for organization_id=#{organization.id} organization_name=#{organization.name}: " <>
            "no invoices in window"
        )

        :skipped

      true ->
        case KsefInvoiceDigest.create_digest(
               %{
                 window_start: window_start,
                 window_end: window_end,
                 cost_invoice_ids: invoice_ids,
                 enqueue_send?: enqueue_send?
               },
               tenant: organization.id,
               actor: actor
             ) do
          {:ok, %KsefInvoiceDigest{}} -> :created
          {:ok, %KsefInvoiceDigest{}, _notifications} -> :created
          {:error, _error} -> :skipped
        end
    end
  end

  defp resolve_window(input) do
    case {input.arguments[:window_start], input.arguments[:window_end]} do
      {nil, nil} ->
        {:ok, KsefInvoiceDigestWindow.previous_window()}

      {window_start, window_end} when not is_nil(window_start) and not is_nil(window_end) ->
        {:ok, %{window_start: window_start, window_end: window_end}}

      _ ->
        {:error, "window_start and window_end must be provided together"}
    end
  end

  defp filter_organizations(organizations, nil), do: organizations

  defp filter_organizations(organizations, organization_ids) do
    Enum.filter(organizations, &(&1.id in organization_ids))
  end

  defp digest_exists?(organization_id, window_start, window_end, actor) do
    case KsefInvoiceDigest.by_window(
           %{window_start: window_start, window_end: window_end},
           tenant: organization_id,
           actor: actor
         ) do
      {:ok, %KsefInvoiceDigest{}} -> true
      _ -> false
    end
  end

  defp invoice_ids_for_window(organization, window_start, window_end, actor) do
    %{
      inserted_from: window_start,
      inserted_to: window_end,
      source: :ksef,
      in_digest: :no
    }
    |> Invoicing.list_cost_invoices!(
      tenant: organization.id,
      actor: actor
    )
    |> Enum.map(& &1.id)
  end
end
