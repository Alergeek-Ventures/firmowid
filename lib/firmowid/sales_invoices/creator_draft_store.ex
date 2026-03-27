defmodule Firmowid.SalesInvoices.CreatorDraftStore do
  @moduledoc """
  In-memory storage for sales invoice creator wizard state using Cachex.

  Creator drafts are keyed by {organization_id, creator_draft_id} and store the wizard state
  including current step and form data. Creator drafts are automatically cleared on
  application restart/redeploy.

  This is distinct from "draft invoices" (szkic) which are persisted invoices
  without an invoice number. Creator drafts are ephemeral wizard state only.

  Creator draft structure:
  %{
    step: integer(),
    data: map(),
    created_at: DateTime.t()
  }
  """

  @cache :creator_drafts

  @type creator_draft_id :: String.t()
  @type organization_id :: String.t()
  @type creator_draft :: %{
          step: non_neg_integer(),
          data: map(),
          created_at: DateTime.t()
        }

  @doc """
  Creates a new creator draft with a generated UUID.
  Returns {:ok, creator_draft_id, creator_draft} on success.
  """
  @spec create(organization_id(), map()) :: {:ok, creator_draft_id(), creator_draft()}
  def create(organization_id, initial_data \\ %{}) do
    creator_draft_id = Ecto.UUID.generate()

    creator_draft = %{
      step: 0,
      data: initial_data,
      created_at: DateTime.utc_now()
    }

    {:ok, true} = Cachex.put(@cache, key(organization_id, creator_draft_id), creator_draft)
    {:ok, creator_draft_id, creator_draft}
  end

  @doc """
  Retrieves a creator draft by organization_id and creator_draft_id.
  Returns {:ok, creator_draft} if found, {:error, :not_found} otherwise.
  """
  @spec get(organization_id(), creator_draft_id()) :: {:ok, creator_draft()} | {:error, :not_found}
  def get(organization_id, creator_draft_id) do
    case Cachex.get(@cache, key(organization_id, creator_draft_id)) do
      {:ok, nil} -> {:error, :not_found}
      {:ok, creator_draft} -> {:ok, creator_draft}
    end
  end

  @doc """
  Updates a creator draft's step and/or data.
  Returns {:ok, creator_draft} on success, {:error, :not_found} if creator draft doesn't exist.
  """
  @spec put(organization_id(), creator_draft_id(), map()) ::
          {:ok, creator_draft()} | {:error, :not_found}
  def put(organization_id, creator_draft_id, updates) do
    case get(organization_id, creator_draft_id) do
      {:ok, creator_draft} ->
        updated_creator_draft = Map.merge(creator_draft, updates)
        {:ok, true} = Cachex.put(@cache, key(organization_id, creator_draft_id), updated_creator_draft)
        {:ok, updated_creator_draft}

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  @doc """
  Deletes a creator draft.
  Returns :ok regardless of whether the creator draft existed.
  """
  @spec delete(organization_id(), creator_draft_id()) :: :ok
  def delete(organization_id, creator_draft_id) do
    Cachex.del(@cache, key(organization_id, creator_draft_id))
    :ok
  end

  @doc """
  Checks if a creator draft exists.
  """
  @spec exists?(organization_id(), creator_draft_id()) :: boolean()
  def exists?(organization_id, creator_draft_id) do
    {:ok, exists} = Cachex.exists?(@cache, key(organization_id, creator_draft_id))
    exists
  end

  defp key(organization_id, creator_draft_id), do: {organization_id, creator_draft_id}
end
