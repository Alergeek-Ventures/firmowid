defmodule FirmowidWeb.RequisitionLiveTest do
  use FirmowidWeb.ConnCase

  import Phoenix.LiveViewTest
  import Firmowid.GoLimitlessFixtures

  @create_attrs %{status: "some status", requisition_id: "some requisition_id"}
  @update_attrs %{status: "some updated status", requisition_id: "some updated requisition_id"}
  @invalid_attrs %{status: nil, requisition_id: nil}

  defp create_requisition(_) do
    requisition = requisition_fixture()
    %{requisition: requisition}
  end

  describe "Index" do
    setup [:create_requisition]

    test "lists all requisitions", %{conn: conn, requisition: requisition} do
      {:ok, _index_live, html} = live(conn, ~p"/requisitions")

      assert html =~ "Listing Requisitions"
      assert html =~ requisition.status
    end

    test "saves new requisition", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/requisitions")

      assert index_live |> element("a", "New Requisition") |> render_click() =~
               "New Requisition"

      assert_patch(index_live, ~p"/requisitions/new")

      assert index_live
             |> form("#requisition-form", requisition: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#requisition-form", requisition: @create_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/requisitions")

      html = render(index_live)
      assert html =~ "Requisition created successfully"
      assert html =~ "some status"
    end

    test "updates requisition in listing", %{conn: conn, requisition: requisition} do
      {:ok, index_live, _html} = live(conn, ~p"/requisitions")

      assert index_live |> element("#requisitions-#{requisition.id} a", "Edit") |> render_click() =~
               "Edit Requisition"

      assert_patch(index_live, ~p"/requisitions/#{requisition}/edit")

      assert index_live
             |> form("#requisition-form", requisition: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#requisition-form", requisition: @update_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/requisitions")

      html = render(index_live)
      assert html =~ "Requisition updated successfully"
      assert html =~ "some updated status"
    end

    test "deletes requisition in listing", %{conn: conn, requisition: requisition} do
      {:ok, index_live, _html} = live(conn, ~p"/requisitions")

      assert index_live |> element("#requisitions-#{requisition.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#requisitions-#{requisition.id}")
    end
  end

  describe "Show" do
    setup [:create_requisition]

    test "displays requisition", %{conn: conn, requisition: requisition} do
      {:ok, _show_live, html} = live(conn, ~p"/requisitions/#{requisition}")

      assert html =~ "Show Requisition"
      assert html =~ requisition.status
    end

    test "updates requisition within modal", %{conn: conn, requisition: requisition} do
      {:ok, show_live, _html} = live(conn, ~p"/requisitions/#{requisition}")

      assert show_live |> element("a", "Edit") |> render_click() =~
               "Edit Requisition"

      assert_patch(show_live, ~p"/requisitions/#{requisition}/show/edit")

      assert show_live
             |> form("#requisition-form", requisition: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert show_live
             |> form("#requisition-form", requisition: @update_attrs)
             |> render_submit()

      assert_patch(show_live, ~p"/requisitions/#{requisition}")

      html = render(show_live)
      assert html =~ "Requisition updated successfully"
      assert html =~ "some updated status"
    end
  end
end
