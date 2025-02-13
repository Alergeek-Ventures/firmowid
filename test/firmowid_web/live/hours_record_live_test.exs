defmodule FirmowidWeb.HoursRecordLiveTest do
  use FirmowidWeb.ConnCase

  import Phoenix.LiveViewTest
  import Firmowid.TimetrackerFixtures

  @create_attrs %{month: 42, year: 42, number_of_hours: 42}
  @update_attrs %{month: 43, year: 43, number_of_hours: 43}
  @invalid_attrs %{month: nil, year: nil, number_of_hours: nil}

  defp create_hours_record(_) do
    hours_record = hours_record_fixture()
    %{hours_record: hours_record}
  end

  describe "Index" do
    setup [:create_hours_record]

    test "lists all hours_records", %{conn: conn} do
      {:ok, _index_live, html} = live(conn, ~p"/hours_records")

      assert html =~ "Listing Hours records"
    end

    test "saves new hours_record", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/hours_records")

      assert index_live |> element("a", "New Hours record") |> render_click() =~
               "New Hours record"

      assert_patch(index_live, ~p"/hours_records/new")

      assert index_live
             |> form("#hours_record-form", hours_record: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#hours_record-form", hours_record: @create_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/hours_records")

      html = render(index_live)
      assert html =~ "Hours record created successfully"
    end

    test "updates hours_record in listing", %{conn: conn, hours_record: hours_record} do
      {:ok, index_live, _html} = live(conn, ~p"/hours_records")

      assert index_live |> element("#hours_records-#{hours_record.id} a", "Edit") |> render_click() =~
               "Edit Hours record"

      assert_patch(index_live, ~p"/hours_records/#{hours_record}/edit")

      assert index_live
             |> form("#hours_record-form", hours_record: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#hours_record-form", hours_record: @update_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/hours_records")

      html = render(index_live)
      assert html =~ "Hours record updated successfully"
    end

    test "deletes hours_record in listing", %{conn: conn, hours_record: hours_record} do
      {:ok, index_live, _html} = live(conn, ~p"/hours_records")

      assert index_live |> element("#hours_records-#{hours_record.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#hours_records-#{hours_record.id}")
    end
  end

  describe "Show" do
    setup [:create_hours_record]

    test "displays hours_record", %{conn: conn, hours_record: hours_record} do
      {:ok, _show_live, html} = live(conn, ~p"/hours_records/#{hours_record}")

      assert html =~ "Show Hours record"
    end

    test "updates hours_record within modal", %{conn: conn, hours_record: hours_record} do
      {:ok, show_live, _html} = live(conn, ~p"/hours_records/#{hours_record}")

      assert show_live |> element("a", "Edit") |> render_click() =~
               "Edit Hours record"

      assert_patch(show_live, ~p"/hours_records/#{hours_record}/show/edit")

      assert show_live
             |> form("#hours_record-form", hours_record: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert show_live
             |> form("#hours_record-form", hours_record: @update_attrs)
             |> render_submit()

      assert_patch(show_live, ~p"/hours_records/#{hours_record}")

      html = render(show_live)
      assert html =~ "Hours record updated successfully"
    end
  end
end
