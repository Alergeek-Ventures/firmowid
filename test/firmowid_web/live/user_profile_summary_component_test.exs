defmodule FirmowidWeb.Components.Timetracker.UserProfileSummaryTest do
  use FirmowidWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Firmowid.AccountsFixtures
  import Firmowid.TimetrackerFixtures

  alias FirmowidWeb.Components.Timetracker.UserProfileSummary

  describe "UserProfileSummary component" do
    setup do
      user = user_fixture(%{name: "Test User"})
      %{user: user}
    end

    test "renders component with user without salary", %{user: user} do
      # 2 hours in seconds
      user_hours = %{time_worked: 7200}
      # Add current_salary: nil to simulate a user without salary
      user_without_salary = Map.put(user, :current_salary, nil)

      html =
        render_component(UserProfileSummary, %{
          id: "test_summary",
          user: user_without_salary,
          user_hours: user_hours
        })

      assert html =~ "Łączny czas"
      assert html =~ "2 h"
      assert html =~ "Stawka"
      assert html =~ "Brak stawki"
      assert html =~ "Wynagrodzenie"
      assert html =~ "Brak stawki"
    end

    test "renders component with user with salary", %{user: user} do
      user_salary = user_salary_fixture(%{user_id: user.id, hourly_rate: Decimal.new("45.50")})
      user_with_salary = Map.put(user, :current_salary, user_salary)
      # 2 hours in seconds
      user_hours = %{time_worked: 7200}

      html =
        render_component(UserProfileSummary, %{
          id: "test_summary",
          user: user_with_salary,
          user_hours: user_hours
        })

      assert html =~ "Łączny czas"
      assert html =~ "2 h"
      assert html =~ "Stawka"
      assert html =~ "45.50 PLN/h"
      assert html =~ "Wynagrodzenie"
      assert html =~ "91.00 PLN"
    end

    test "calculates salary correctly with ceiling for partial hours", %{user: user} do
      user_salary = user_salary_fixture(%{user_id: user.id, hourly_rate: Decimal.new("50.00")})
      user_with_salary = Map.put(user, :current_salary, user_salary)
      # 1.5 hours in seconds
      user_hours = %{time_worked: 5400}

      html =
        render_component(UserProfileSummary, %{
          id: "test_summary",
          user: user_with_salary,
          user_hours: user_hours
        })

      # ceiling of 1.5 = 2
      assert html =~ "2 h"
      # Payment for 2 hours (ceiling)
      assert html =~ "100.00 PLN"
    end

    test "renders zero hours correctly", %{user: user} do
      user_salary = user_salary_fixture(%{user_id: user.id, hourly_rate: Decimal.new("40.00")})
      user_with_salary = Map.put(user, :current_salary, user_salary)
      user_hours = %{time_worked: 0}

      html =
        render_component(UserProfileSummary, %{
          id: "test_summary",
          user: user_with_salary,
          user_hours: user_hours
        })

      assert html =~ "0 h"
      assert html =~ "0.00 PLN"
    end

    test "handles nil user_hours", %{user: user} do
      user_salary = user_salary_fixture(%{user_id: user.id, hourly_rate: Decimal.new("30.00")})
      user_with_salary = Map.put(user, :current_salary, user_salary)

      html =
        render_component(UserProfileSummary, %{
          id: "test_summary",
          user: user_with_salary,
          user_hours: nil
        })

      assert html =~ "0 h"
      assert html =~ "0 PLN"
    end

    test "displays very large hour values correctly", %{user: user} do
      user_salary = user_salary_fixture(%{user_id: user.id, hourly_rate: Decimal.new("25.75")})
      user_with_salary = Map.put(user, :current_salary, user_salary)
      user_hours = %{time_worked: 144_000}

      html =
        render_component(UserProfileSummary, %{
          id: "test_summary",
          user: user_with_salary,
          user_hours: user_hours
        })

      assert html =~ "40 h"
      assert html =~ "1030.00 PLN"
    end

    test "handles decimal salary rates correctly", %{user: user} do
      user_salary = user_salary_fixture(%{user_id: user.id, hourly_rate: Decimal.new("33.33")})
      user_with_salary = Map.put(user, :current_salary, user_salary)
      user_hours = %{time_worked: 10800}

      html =
        render_component(UserProfileSummary, %{
          id: "test_summary",
          user: user_with_salary,
          user_hours: user_hours
        })

      assert html =~ "3 h"
      assert html =~ "33.33 PLN/h"
      assert html =~ "99.99 PLN"
    end
  end
end
