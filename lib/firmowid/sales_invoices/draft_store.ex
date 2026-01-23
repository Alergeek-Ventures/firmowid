defmodule Firmowid.SalesInvoices.DraftStore do
  @moduledoc """
  In-memory storage for sales invoice wizard drafts using Cachex.

  Drafts are keyed by {organization_id, draft_id} and store the wizard state
  including current step and form data. Drafts are automatically cleared on
  application restart/redeploy.

  Draft structure:
  %{
    step: integer(),
    data: map(),
    created_at: DateTime.t()
  }
  """

  @cache :invoice_drafts

  @type draft_id :: String.t()
  @type organization_id :: String.t()
  @type draft :: %{
          step: non_neg_integer(),
          data: map(),
          created_at: DateTime.t()
        }

  @doc """
  Creates a new draft with a generated UUID.
  Returns {:ok, draft_id, draft} on success.
  """
  @spec create(organization_id(), map()) :: {:ok, draft_id(), draft()}
  def create(organization_id, initial_data \\ %{}) do
    draft_id = Ecto.UUID.generate()

    draft = %{
      step: 0,
      data: initial_data,
      created_at: DateTime.utc_now()
    }

    {:ok, true} = Cachex.put(@cache, key(organization_id, draft_id), draft)
    {:ok, draft_id, draft}
  end

  @doc """
  Retrieves a draft by organization_id and draft_id.
  Returns {:ok, draft} if found, {:error, :not_found} otherwise.
  """
  @spec get(organization_id(), draft_id()) :: {:ok, draft()} | {:error, :not_found}
  def get(organization_id, draft_id) do
    case Cachex.get(@cache, key(organization_id, draft_id)) do
      {:ok, nil} -> {:error, :not_found}
      {:ok, draft} -> {:ok, draft}
    end
  end

  @doc """
  Updates a draft's step and/or data.
  Returns {:ok, draft} on success, {:error, :not_found} if draft doesn't exist.
  """
  @spec put(organization_id(), draft_id(), map()) ::
          {:ok, draft()} | {:error, :not_found}
  def put(organization_id, draft_id, updates) do
    case get(organization_id, draft_id) do
      {:ok, draft} ->
        updated_draft = Map.merge(draft, updates)
        {:ok, true} = Cachex.put(@cache, key(organization_id, draft_id), updated_draft)
        {:ok, updated_draft}

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  @doc """
  Deletes a draft.
  Returns :ok regardless of whether the draft existed.
  """
  @spec delete(organization_id(), draft_id()) :: :ok
  def delete(organization_id, draft_id) do
    Cachex.del(@cache, key(organization_id, draft_id))
    :ok
  end

  @doc """
  Checks if a draft exists.
  """
  @spec exists?(organization_id(), draft_id()) :: boolean()
  def exists?(organization_id, draft_id) do
    {:ok, exists} = Cachex.exists?(@cache, key(organization_id, draft_id))
    exists
  end

  defp key(organization_id, draft_id), do: {organization_id, draft_id}
end
