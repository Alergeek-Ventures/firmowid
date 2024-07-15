defmodule Firmowid.GoLimitlessTest do
  use Firmowid.DataCase

  alias Firmowid.GoLimitless

  describe "requisitions" do
    alias Firmowid.GoLimitless.Requisition

    import Firmowid.GoLimitlessFixtures

    @invalid_attrs %{status: nil, requisition_id: nil}

    test "list_requisitions/0 returns all requisitions" do
      requisition = requisition_fixture()
      assert GoLimitless.list_requisitions() == [requisition]
    end

    test "get_requisition!/1 returns the requisition with given id" do
      requisition = requisition_fixture()
      assert GoLimitless.get_requisition!(requisition.id) == requisition
    end

    test "create_requisition/1 with valid data creates a requisition" do
      valid_attrs = %{status: "some status", requisition_id: "some requisition_id"}

      assert {:ok, %Requisition{} = requisition} = GoLimitless.create_requisition(valid_attrs)
      assert requisition.status == "some status"
      assert requisition.requisition_id == "some requisition_id"
    end

    test "create_requisition/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = GoLimitless.create_requisition(@invalid_attrs)
    end

    test "update_requisition/2 with valid data updates the requisition" do
      requisition = requisition_fixture()
      update_attrs = %{status: "some updated status", requisition_id: "some updated requisition_id"}

      assert {:ok, %Requisition{} = requisition} = GoLimitless.update_requisition(requisition, update_attrs)
      assert requisition.status == "some updated status"
      assert requisition.requisition_id == "some updated requisition_id"
    end

    test "update_requisition/2 with invalid data returns error changeset" do
      requisition = requisition_fixture()
      assert {:error, %Ecto.Changeset{}} = GoLimitless.update_requisition(requisition, @invalid_attrs)
      assert requisition == GoLimitless.get_requisition!(requisition.id)
    end

    test "delete_requisition/1 deletes the requisition" do
      requisition = requisition_fixture()
      assert {:ok, %Requisition{}} = GoLimitless.delete_requisition(requisition)
      assert_raise Ecto.NoResultsError, fn -> GoLimitless.get_requisition!(requisition.id) end
    end

    test "change_requisition/1 returns a requisition changeset" do
      requisition = requisition_fixture()
      assert %Ecto.Changeset{} = GoLimitless.change_requisition(requisition)
    end
  end
end
