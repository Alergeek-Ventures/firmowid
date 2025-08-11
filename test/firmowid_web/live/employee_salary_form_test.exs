defmodule FirmowidWeb.Project.Index.EmployeeSalaryFormTest do
  use FirmowidWeb.ConnCase, async: true

  import Ecto.Changeset, only: [get_field: 2]

  alias FirmowidWeb.Project.Index.EmployeeSalaryForm

  describe "EmployeeSalaryForm changeset" do
    test "creates changeset with default values" do
      changeset = EmployeeSalaryForm.changeset()

      assert changeset.valid?
      assert get_field(changeset, :salary_type) == nil
      assert get_field(changeset, :hourly_rate) == nil
      assert get_field(changeset, :fixed_salary) == nil
    end

    test "creates changeset with provided attributes" do
      attrs = %{
        "salary_type" => "hourly",
        "hourly_rate" => "45.50"
      }

      changeset = EmployeeSalaryForm.changeset(attrs)

      assert changeset.valid?
      assert get_field(changeset, :salary_type) == "hourly"
      assert get_field(changeset, :hourly_rate) == "45.50"
    end

    test "calculates fixed salary from hourly rate" do
      attrs = %{
        "salary_type" => "hourly",
        "hourly_rate" => "50.00"
      }

      changeset = EmployeeSalaryForm.changeset(attrs)

      assert changeset.valid?
      assert get_field(changeset, :hourly_rate) == "50.00"
      # 50.00 * 168 = 8400.00
      assert get_field(changeset, :fixed_salary) == "8400.00"
    end

    test "calculates hourly rate from fixed salary" do
      attrs = %{
        "salary_type" => "fixed",
        "fixed_salary" => "8400.00"
      }

      changeset = EmployeeSalaryForm.changeset(attrs)

      assert changeset.valid?
      assert get_field(changeset, :fixed_salary) == "8400.00"
      # 8400.00 / 168 = 50.00
      assert get_field(changeset, :hourly_rate) == "50.00"
    end

    test "handles decimal calculations correctly" do
      attrs = %{
        "salary_type" => "fixed",
        "fixed_salary" => "5000.00"
      }

      changeset = EmployeeSalaryForm.changeset(attrs)

      assert changeset.valid?
      # 5000.00 / 168 = 29.76 (rounded to 2 decimal places)
      assert get_field(changeset, :hourly_rate) == "29.76"
    end

    test "handles hourly rate with many decimal places" do
      attrs = %{
        "salary_type" => "hourly",
        "hourly_rate" => "33.333333"
      }

      changeset = EmployeeSalaryForm.changeset(attrs)

      assert changeset.valid?
      # 33.333333 * 168 = 5600.00 (rounded to 2 decimal places)
      assert get_field(changeset, :fixed_salary) == "5600.00"
    end

    test "ignores calculation when salary_type is not set" do
      attrs = %{
        "hourly_rate" => "50.00",
        "fixed_salary" => "8400.00"
      }

      changeset = EmployeeSalaryForm.changeset(attrs)

      assert changeset.valid?
      assert get_field(changeset, :hourly_rate) == "50.00"
      assert get_field(changeset, :fixed_salary) == "8400.00"
    end

    test "handles empty string values" do
      attrs = %{
        "salary_type" => "hourly",
        "hourly_rate" => ""
      }

      changeset = EmployeeSalaryForm.changeset(attrs)

      assert changeset.valid?
      assert get_field(changeset, :hourly_rate) == nil
      assert get_field(changeset, :fixed_salary) == nil
    end

    test "handles nil values" do
      attrs = %{
        "salary_type" => "fixed",
        "fixed_salary" => nil
      }

      changeset = EmployeeSalaryForm.changeset(attrs)

      assert changeset.valid?
      assert get_field(changeset, :fixed_salary) == nil
      assert get_field(changeset, :hourly_rate) == nil
    end

    test "handles invalid number formats" do
      attrs = %{
        "salary_type" => "hourly",
        "hourly_rate" => "not_a_number"
      }

      changeset = EmployeeSalaryForm.changeset(attrs)

      assert changeset.valid?
      assert get_field(changeset, :hourly_rate) == "not_a_number"
      assert get_field(changeset, :fixed_salary) == nil
    end

    test "updating existing changeset with new values" do
      # Start with hourly rate
      initial_attrs = %{
        "salary_type" => "hourly",
        "hourly_rate" => "40.00"
      }

      initial_changeset = EmployeeSalaryForm.changeset(initial_attrs)
      assert get_field(initial_changeset, :fixed_salary) == "6720.00"

      # Update to fixed salary
      update_attrs = %{
        "salary_type" => "fixed",
        "fixed_salary" => "10000.00"
      }

      updated_changeset = EmployeeSalaryForm.changeset(initial_changeset.data, update_attrs)

      assert get_field(updated_changeset, :fixed_salary) == "10000.00"
      # 10000.00 / 168 = 59.52
      assert get_field(updated_changeset, :hourly_rate) == "59.52"
    end

    test "zero values calculate correctly" do
      attrs = %{
        "salary_type" => "hourly",
        "hourly_rate" => "0.00"
      }

      changeset = EmployeeSalaryForm.changeset(attrs)

      assert changeset.valid?
      assert get_field(changeset, :hourly_rate) == "0.00"
      assert get_field(changeset, :fixed_salary) == "0.00"
    end

    test "very small hourly rates calculate correctly" do
      attrs = %{
        "salary_type" => "hourly",
        "hourly_rate" => "0.01"
      }

      changeset = EmployeeSalaryForm.changeset(attrs)

      assert changeset.valid?
      assert get_field(changeset, :hourly_rate) == "0.01"
      # 0.01 * 168 = 1.68
      assert get_field(changeset, :fixed_salary) == "1.68"
    end

    test "very large salary values calculate correctly" do
      attrs = %{
        "salary_type" => "fixed",
        "fixed_salary" => "100000.00"
      }

      changeset = EmployeeSalaryForm.changeset(attrs)

      assert changeset.valid?
      assert get_field(changeset, :fixed_salary) == "100000.00"
      # 100000.00 / 168 = 595.24
      assert get_field(changeset, :hourly_rate) == "595.24"
    end
  end
end
