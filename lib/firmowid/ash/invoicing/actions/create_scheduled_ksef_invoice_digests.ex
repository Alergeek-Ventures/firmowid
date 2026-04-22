defmodule Firmowid.Ash.Invoicing.Actions.CreateScheduledKsefInvoiceDigests do
  @moduledoc """
  Builds KSeF invoice digests for all currently eligible undigested invoices.
  """
  use Ash.Resource.Actions.Implementation

  alias Firmowid.Ash.Core.Organization
  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.KsefInvoiceDigest
  alias Firmowid.Ash.Invoicing.Workers.SendKsefInvoiceDigestWorker
  alias Firmowid.Ash.Ksef
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor
  alias Firmowid.Oban

  require Logger

  @doc false
  @impl true
  def run(input, _opts, _context) do
    run_started_at = DateTime.utc_now()
    organization_ids = input.arguments[:organization_ids]
    enqueue_send? = Map.get(input.arguments, :enqueue_send?, true)

    Logger.info(
      "Building KSeF digests up to #{DateTime.to_iso8601(run_started_at)} " <>
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
               run_started_at,
               enqueue_send?
             ) do
          :created -> acc + 1
          :skipped -> acc
        end
      end)

    {:ok, created_count}
  end

  defp create_digest_for_organization(organization, run_started_at, enqueue_send?) do
    actor = %SystemActor{org_id: organization.id, role: :ksef_digest}

    if has_ksef_credential?(organization.id) do
      invoice_ids = invoice_ids_for_window(organization, run_started_at, actor)

      Logger.info(
        "KSeF digest candidate organization_id=#{organization.id} organization_name=#{organization.name} " <>
          "invoice_count=#{length(invoice_ids)}"
      )

      if invoice_ids == [] do
        Logger.info(
          "Skipping KSeF digest for organization_id=#{organization.id} organization_name=#{organization.name}: no eligible invoices"
        )

        :skipped
      else
        case create_digest_for_invoices(
               organization,
               invoice_ids,
               actor
             ) do
          {:ok, %KsefInvoiceDigest{} = digest} ->
            maybe_enqueue_send(digest, enqueue_send?, actor)
            :created

          {:ok, %KsefInvoiceDigest{} = digest, _notifications} ->
            maybe_enqueue_send(digest, enqueue_send?, actor)
            :created

          {:error, error} ->
            Logger.error("Failed to create KSeF digest for organization_id=#{organization.id}: #{inspect(error)}")

            :skipped
        end
      end
    else
      Logger.info(
        "Skipping KSeF digest for organization_id=#{organization.id} organization_name=#{organization.name}: " <>
          "organization has no KSeF credentials"
      )

      :skipped
    end
  end

  defp maybe_enqueue_send(%KsefInvoiceDigest{} = digest, true, actor) do
    %{
      "digest_id" => digest.id,
      "organization_id" => actor.org_id
    }
    |> SendKsefInvoiceDigestWorker.new()
    |> Oban.insert!(skip_organization_id: true)
  end

  defp maybe_enqueue_send(_digest, false, _actor), do: :ok

  defp create_digest_for_invoices(organization, invoice_ids, actor) do
    KsefInvoiceDigest.create_digest(
      %{cost_invoice_ids: invoice_ids},
      tenant: organization.id,
      actor: actor
    )
  end

  defp has_ksef_credential?(organization_id) do
    scope = %Scope{
      tenant: organization_id,
      actor: %SystemActor{org_id: organization_id, role: :ksef_session}
    }

    case Ksef.get_credential(scope) do
      nil -> false
      _ -> true
    end
  end

  defp filter_organizations(organizations, nil), do: organizations

  defp filter_organizations(organizations, organization_ids) do
    Enum.filter(organizations, &(&1.id in organization_ids))
  end

  defp invoice_ids_for_window(organization, inserted_to, actor) do
    %{
      inserted_to: inserted_to,
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
