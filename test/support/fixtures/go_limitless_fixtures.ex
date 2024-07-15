defmodule Firmowid.GoLimitlessFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Firmowid.GoLimitless` context.
  """

  @doc """
  Generate a requisition.
  """
  def requisition_fixture(attrs \\ %{}) do
    {:ok, requisition} =
      attrs
      |> Enum.into(%{
        requisition_id: "some requisition_id",
        status: "some status"
      })
      |> Firmowid.GoLimitless.create_requisition()

    requisition
  end
end
