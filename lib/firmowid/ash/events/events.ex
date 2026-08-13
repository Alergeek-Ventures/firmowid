defmodule Firmowid.Ash.Events do
  @moduledoc """
  Ash domain for the centralized event log.

  Currently used by BankAccount for sync status derivation.
  Other resources can opt into event tracking later.
  """
  use Ash.Domain

  import Ash.Expr

  alias Firmowid.Ash.Events.Event

  require Ash.Query

  @doc """
  Returns the timestamp of the latest successful sync event for a given record.

  This API intentionally lives in the Events domain so callers don't rely on
  event-log internals (resource/action/date filters).
  """
  @spec last_successful_sync_at(
          %{
            __struct__: module(),
            organization_id: Ecto.UUID.t(),
            id: Ecto.UUID.t()
          },
          keyword()
        ) :: {:ok, DateTime.t() | nil} | {:error, term()}
  def last_successful_sync_at(%{__struct__: resource, organization_id: organization_id, id: record_id}, opts) do
    read_opts = Keyword.delete(opts, :before)

    query =
      organization_id
      |> Event.query_to_latest_successful_sync(record_id, resource, read_opts)
      |> apply_sync_before_filter(Keyword.get(opts, :before))
      |> Ash.Query.limit(1)

    case Ash.read_one(query, read_opts) do
      {:ok, %Event{occurred_at: occurred_at}} -> {:ok, occurred_at}
      {:ok, nil} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  def last_successful_sync_at(_record, _opts), do: {:ok, nil}

  defp apply_sync_before_filter(query, nil), do: query

  defp apply_sync_before_filter(query, before) do
    Ash.Query.filter(query, expr(occurred_at < ^before))
  end

  resources do
    resource Event do
      define :list_events, action: :read

      define :latest_successful_sync,
        action: :latest_successful_sync,
        args: [:organization_id, :record_id, :resource]
    end
  end

  authorization do
    authorize :by_default
    require_actor? true
  end
end
