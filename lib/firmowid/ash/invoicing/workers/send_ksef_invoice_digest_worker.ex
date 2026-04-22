defmodule Firmowid.Ash.Invoicing.Workers.SendKsefInvoiceDigestWorker do
  @moduledoc """
  Sends a persisted KSeF invoice digest after it has been committed.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3

  alias Firmowid.Ash.Invoicing.KsefInvoiceDigest
  alias Firmowid.Ash.SystemActor

  require Ash.Query
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"digest_id" => digest_id, "organization_id" => organization_id}}) do
    actor = %SystemActor{org_id: organization_id, role: :ksef_digest}

    digest =
      KsefInvoiceDigest
      |> Ash.Query.for_read(:read_for_delivery, %{}, tenant: organization_id, actor: actor)
      |> Ash.Query.filter(id == ^digest_id)
      |> Ash.read_one(tenant: organization_id, actor: actor)

    case digest do
      {:ok, nil} ->
        Logger.warning("KSeF digest #{digest_id} not found for organization #{organization_id}")
        {:cancel, :digest_not_found}

      {:ok, %KsefInvoiceDigest{delivered_at: delivered_at}} when not is_nil(delivered_at) ->
        Logger.info("KSeF digest #{digest_id} already delivered for organization #{organization_id}")

        :ok

      {:ok, %KsefInvoiceDigest{} = digest} ->
        case KsefInvoiceDigest.send_digest(digest, %{}, tenant: organization_id, actor: actor) do
          {:ok, _digest} ->
            :ok

          {:error, error} ->
            Logger.error("Failed to send KSeF digest #{digest_id} for organization #{organization_id}: #{inspect(error)}")

            {:error, inspect(error)}
        end

      {:error, error} ->
        Logger.error("Failed to load KSeF digest #{digest_id} for organization #{organization_id}: #{inspect(error)}")

        {:error, inspect(error)}
    end
  end
end
