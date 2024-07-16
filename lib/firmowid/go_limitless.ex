defmodule Firmowid.GoLimitless do
  @moduledoc """
  The GoLimitless context.
  """

  import Ecto.Query, warn: false
  alias Firmowid.GoLimitless
  alias Firmowid.Repo

  alias Firmowid.GoLimitless.Requisition
  alias Firmowid.GoLimitless.ApiClient

  @doc """
  Returns the list of requisitions.

  ## Examples

      iex> list_requisitions()
      [%Requisition{}, ...]

  """
  def list_requisitions do
    Repo.all(Requisition)
    |> Enum.map(
      &Map.merge(
        &1,
        %{accounts: ApiClient.get_accounts_for_requisition(&1.requisition_id)}
      )
    )
  end

  @doc """
  Gets a single requisition.

  Raises `Ecto.NoResultsError` if the Requisition does not exist.

  ## Examples

      iex> get_requisition!(123)
      %Requisition{}

      iex> get_requisition!(456)
      ** (Ecto.NoResultsError)

  """
  def get_requisition!(id), do: Repo.get!(Requisition, id)

  def get_accounts_for_requisition(requisition_id) do
    GoLimitless.ApiClient.get_accounts_for_requisition(requisition_id)
  end

  @doc """
  Creates a requisition.

  ## Examples

      iex> create_requisition(%{field: value})
      {:ok, %Requisition{}}

      iex> create_requisition(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_requisition(attrs \\ %{}) do
    %Requisition{}
    |> Requisition.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a requisition.

  ## Examples

      iex> update_requisition(requisition, %{field: new_value})
      {:ok, %Requisition{}}

      iex> update_requisition(requisition, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_requisition(%Requisition{} = requisition, attrs) do
    requisition
    |> Requisition.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a requisition.

  ## Examples

      iex> delete_requisition(requisition)
      {:ok, %Requisition{}}

      iex> delete_requisition(requisition)
      {:error, %Ecto.Changeset{}}

  """
  def delete_requisition(%Requisition{} = requisition) do
    Repo.delete(requisition)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking requisition changes.

  ## Examples

      iex> change_requisition(requisition)
      %Ecto.Changeset{data: %Requisition{}}

  """
  def change_requisition(%Requisition{} = requisition, attrs \\ %{}) do
    Requisition.changeset(requisition, attrs)
  end
end
