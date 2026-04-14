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

  @doc false
  @impl true
  def run(_input, _opts, _context) do
    %{window_start: window_start, window_end: window_end} =
      KsefInvoiceDigestWindow.previous_window()

    # cross_tenant_reader: enumerate all organizations for scheduled digest creation
    cross_tenant_actor = %SystemActor{org_id: nil, role: :cross_tenant_reader}

    created_count =
      Organization
      |> Ash.read!(actor: cross_tenant_actor)
      |> Enum.reduce(0, fn organization, acc ->
        case create_digest_for_organization(organization.id, window_start, window_end) do
          :created -> acc + 1
          :skipped -> acc
        end
      end)

    {:ok, created_count}
  end

  defp create_digest_for_organization(organization_id, window_start, window_end) do
    actor = %SystemActor{org_id: organization_id, role: :ksef_digest}

    if digest_exists?(organization_id, window_start, window_end, actor) do
      :skipped
    else
      case invoice_ids_for_window(organization_id, window_start, window_end, actor) do
        [] ->
          :skipped

        invoice_ids ->
          case KsefInvoiceDigest.create_digest(
                 %{
                   window_start: window_start,
                   window_end: window_end,
                   cost_invoice_ids: invoice_ids
                 },
                 tenant: organization_id,
                 actor: actor
               ) do
            {:ok, %KsefInvoiceDigest{}} -> :created
            {:ok, %KsefInvoiceDigest{}, _notifications} -> :created
            {:error, _error} -> :skipped
          end
      end
    end
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

  defp invoice_ids_for_window(organization_id, window_start, window_end, actor) do
    %{
      inserted_from: window_start,
      inserted_to: window_end,
      source: :ksef,
      in_digest: :no
    }
    |> Invoicing.list_cost_invoices!(
      tenant: organization_id,
      actor: actor
    )
    |> Enum.map(& &1.id)
  end
end
