defmodule Firmowid.Payroll.DeclarationImportTest do
  @moduledoc "Checks employee document import, partial facts and tenant isolation."
  use Firmowid.DataCase, async: false

  import Firmowid.AccountsFixtures

  alias Firmowid.Blobs.Blob
  alias Firmowid.Blobs.Utils.ProcessEmploymentContractBlob
  alias Firmowid.Payroll
  alias Firmowid.Payroll.MemberPayrollInput
  alias Firmowid.Payroll.MemberTaxDeclaration
  alias Firmowid.Scope
  alias Firmowid.SystemActor

  setup do
    previous_config = Application.get_env(:firmowid, :reducto_api_client)
    previous_client = Application.get_env(:firmowid, :reducto_api_client_module)
    previous_s3 = Application.get_env(:firmowid, :s3)
    Application.delete_env(:firmowid, :reducto_api_client_module)
    Application.put_env(:firmowid, :s3, host: "s3.example.com")
    Application.put_env(:firmowid, :reducto_api_client, extract: [plug: {Req.Test, __MODULE__}])

    on_exit(fn ->
      restore_env(:reducto_api_client, previous_config)
      restore_env(:reducto_api_client_module, previous_client)
      restore_env(:s3, previous_s3)
    end)

    admin = admin_fixture()
    employee = user_in_org_fixture(admin.member.organization_id)
    org_id = admin.member.organization_id

    %{
      admin: admin,
      employee: employee,
      org_id: org_id,
      admin_scope: scope(admin),
      processor_scope: processor_scope(org_id)
    }
  end

  test "merges explicit false and non-nil declaration facts by effective date", %{
    employee: employee,
    org_id: org_id,
    processor_scope: scope
  } do
    first_blob = blob_fixture!(org_id, employee.member.id)
    second_blob = blob_fixture!(org_id, employee.member.id)
    applies_from = ~D[2026-01-01]

    assert {:ok, first} =
             MemberTaxDeclaration.import_from_document(
               %{
                 member_id: employee.member.id,
                 source_blob_id: first_blob.id,
                 received_on: ~D[2025-12-20],
                 applies_from: applies_from,
                 pit2: :one_twelfth,
                 student: true
               },
               scope: scope
             )

    assert {:ok, merged} =
             MemberTaxDeclaration.import_from_document(
               %{
                 member_id: employee.member.id,
                 source_blob_id: second_blob.id,
                 applies_from: applies_from,
                 student: false,
                 ppk_employee_rate: Decimal.new("2")
               },
               scope: scope
             )

    assert merged.id == first.id
    assert merged.pit2 == :one_twelfth
    assert merged.student == false
    assert Decimal.equal?(merged.ppk_employee_rate, Decimal.new("2"))
    assert merged.received_on == ~D[2025-12-20]
    assert merged.source_blob_id == second_blob.id

    assert {:ok, same_record} =
             MemberTaxDeclaration.import_from_document(
               %{
                 member_id: employee.member.id,
                 source_blob_id: second_blob.id,
                 applies_from: applies_from,
                 student: false
               },
               scope: scope
             )

    assert same_record.id == merged.id

    next_blob = blob_fixture!(org_id, employee.member.id)

    assert {:ok, next_version} =
             MemberTaxDeclaration.import_from_document(
               %{
                 member_id: employee.member.id,
                 source_blob_id: next_blob.id,
                 received_on: ~D[2026-01-20],
                 applies_from: ~D[2026-02-01],
                 ppk: :participant
               },
               scope: scope
             )

    assert next_version.id != merged.id
    assert next_version.pit2 == :one_twelfth
    assert next_version.student == false
    assert next_version.ppk == :participant
    assert Decimal.equal?(next_version.ppk_employee_rate, Decimal.new("2"))
  end

  test "keeps declarations without dates as non-effective drafts and allows completing them", %{
    employee: employee,
    org_id: org_id,
    admin_scope: admin_scope,
    processor_scope: processor_scope
  } do
    blob = blob_fixture!(org_id, employee.member.id)

    assert {:ok, draft} =
             MemberTaxDeclaration.import_from_document(
               %{
                 member_id: employee.member.id,
                 source_blob_id: blob.id,
                 pit2: :one_twelfth
               },
               scope: processor_scope
             )

    assert is_nil(draft.received_on)
    assert is_nil(draft.applies_from)

    assert {:ok, []} =
             Payroll.list_tax_declarations(
               %{member_id: employee.member.id, as_of: ~D[2026-01-01]},
               scope: admin_scope
             )

    assert {:ok, [listed_draft]} =
             Payroll.list_tax_declarations(%{member_id: employee.member.id}, scope: admin_scope)

    assert listed_draft.id == draft.id

    assert {:ok, completed} =
             Payroll.correct_tax_declaration(
               draft,
               %{received_on: ~D[2025-12-20], applies_from: ~D[2026-01-01]},
               scope: admin_scope
             )

    assert completed.applies_from == ~D[2026-01-01]

    assert {:ok, [effective]} =
             Payroll.list_tax_declarations(
               %{member_id: employee.member.id, as_of: ~D[2026-01-01]},
               scope: admin_scope
             )

    assert effective.id == completed.id

    assert {:error, _error} =
             Payroll.correct_tax_declaration(
               completed,
               %{applies_from: ~D[2026-02-01]},
               scope: admin_scope
             )
  end

  test "completing an imported draft carries forward known facts without undoing its explicit choice",
       %{
         employee: employee,
         org_id: org_id,
         admin_scope: admin_scope,
         processor_scope: processor_scope
       } do
    Payroll.create_tax_declaration!(
      %{
        member_id: employee.member.id,
        received_on: ~D[2026-01-01],
        applies_from: ~D[2026-01-01],
        pit2: :one_twelfth,
        employee_costs: :standard,
        ppk: :none
      },
      scope: admin_scope
    )

    draft =
      MemberTaxDeclaration.import_from_document!(
        %{
          member_id: employee.member.id,
          source_blob_id: blob_fixture!(org_id, employee.member.id).id,
          pit2: :none
        },
        scope: processor_scope
      )

    completed =
      Payroll.correct_tax_declaration!(
        draft,
        %{
          received_on: ~D[2026-02-01],
          applies_from: ~D[2026-02-01],
          employee_costs: nil,
          ppk: nil
        },
        scope: admin_scope
      )

    assert completed.pit2 == :none
    assert completed.employee_costs == :standard
    assert completed.ppk == :none

    corrected = Payroll.correct_tax_declaration!(completed, %{ppk: nil}, scope: admin_scope)
    assert corrected.ppk == nil
  end

  test "rejects importing another organization's member", %{
    org_id: org_id,
    employee: employee,
    admin_scope: admin_scope,
    processor_scope: processor_scope
  } do
    other_org_admin = admin_fixture()
    other_member = user_in_org_fixture(other_org_admin.member.organization_id)
    blob = blob_fixture!(org_id, nil)

    current =
      Payroll.create_tax_declaration!(
        %{
          member_id: employee.member.id,
          received_on: ~D[2026-01-01],
          applies_from: ~D[2026-01-01],
          pit2: :one_twelfth
        },
        scope: admin_scope
      )

    for identity <- [
          %{member_id: "", source_blob_id: blob.id},
          %{member_id: employee.member.id, source_blob_id: ""}
        ] do
      attrs = Map.merge(identity, %{applies_from: ~D[2026-01-01], pit2: :none})

      assert {:error, _} =
               MemberTaxDeclaration.import_from_document(attrs, scope: processor_scope)
    end

    [unchanged] =
      Payroll.list_tax_declarations!(%{member_id: employee.member.id}, scope: admin_scope)

    assert unchanged.id == current.id
    assert unchanged.pit2 == :one_twelfth

    assert {:error, _error} =
             MemberTaxDeclaration.import_from_document(
               %{
                 member_id: other_member.member.id,
                 source_blob_id: blob.id,
                 pit2: :one_twelfth
               },
               scope: processor_scope
             )
  end

  test "recognizes a standalone declaration without creating an employment contract", %{
    employee: employee,
    org_id: org_id,
    processor_scope: processor_scope
  } do
    blob = blob_fixture!(org_id, employee.member.id)

    stub_extract(%{
      "document_type" => "employee_tax_declaration",
      "tax_declaration" => %{"pit2" => "one_twelfth"}
    })

    assert :ok =
             ProcessEmploymentContractBlob.run_processing("https://example.com/document", blob, scope: processor_scope)

    assert {:ok, declarations} =
             Payroll.list_tax_declarations(%{member_id: employee.member.id},
               scope: processor_scope
             )

    assert [%{pit2: :one_twelfth, applies_from: nil}] = declarations

    assert {:ok, []} =
             Payroll.list_employment_contracts(%{member_id: employee.member.id},
               scope: processor_scope
             )
  end

  test "rolls back a contract packet when its attached declaration is invalid", %{
    employee: employee,
    org_id: org_id,
    processor_scope: processor_scope
  } do
    blob = blob_fixture!(org_id, employee.member.id)

    stub_extract(%{
      "document_type" => "signed_employment_contract",
      "starts_at" => "2026-01-01",
      "signed_at" => "2026-01-01",
      "salary_amount" => 100,
      "salary_currency" => "PLN",
      "contract_type" => "uop",
      "tax_declaration" => %{
        "received_on" => "2026-02-01",
        "applies_from" => "2026-01-01",
        "pit2" => "one_twelfth"
      }
    })

    assert {:error, _} =
             ProcessEmploymentContractBlob.run_processing("https://example.com/document", blob, scope: processor_scope)

    assert {:ok, []} =
             Payroll.list_employment_contracts(%{member_id: employee.member.id},
               scope: processor_scope
             )

    assert {:ok, []} = Payroll.list_salaries(%{user_id: employee.id}, scope: processor_scope)
  end

  test "keeps a legacy hourly-converted contract salary unconfirmed", %{
    employee: employee,
    org_id: org_id,
    processor_scope: processor_scope
  } do
    blob = blob_fixture!(org_id, employee.member.id)

    stub_extract(%{
      "document_type" => "signed_employment_contract",
      "starts_at" => Date.to_iso8601(Date.utc_today()),
      "signed_at" => "2026-01-01",
      "salary_amount" => 10,
      "salary_currency" => "PLN",
      "hourly_rate_confirmed" => false,
      "contract_type" => "uop"
    })

    assert :ok =
             ProcessEmploymentContractBlob.run_processing("https://example.com/document", blob, scope: processor_scope)

    assert {:ok, [contract]} =
             Payroll.list_employment_contracts(%{member_id: employee.member.id},
               scope: processor_scope
             )

    assert contract.hourly_rate_confirmed == false
    assert Decimal.equal?(Money.to_decimal(contract.salary), Decimal.new("10"))

    unknown_rate_blob = blob_fixture!(org_id, employee.member.id)

    stub_extract(%{
      "document_type" => "signed_employment_contract",
      "starts_at" => Date.to_iso8601(Date.add(Date.utc_today(), 1)),
      "signed_at" => Date.to_iso8601(Date.utc_today()),
      "salary_amount" => 20,
      "salary_currency" => "PLN",
      "contract_type" => "uop"
    })

    assert :ok =
             ProcessEmploymentContractBlob.run_processing(
               "https://example.com/document",
               unknown_rate_blob,
               scope: processor_scope
             )

    assert {:ok, contracts} =
             Payroll.list_employment_contracts(%{member_id: employee.member.id},
               scope: processor_scope
             )

    unknown_rate_contract = Enum.find(contracts, &(&1.blob_id == unknown_rate_blob.id))
    assert unknown_rate_contract.hourly_rate_confirmed == nil
  end

  test "requires explicit PLN for payroll amounts and preserves zero and false", %{
    employee: employee,
    org_id: org_id,
    processor_scope: processor_scope
  } do
    blob = blob_fixture!(org_id, employee.member.id)

    stub_extract(%{
      "document_type" => "payroll_statement",
      "payroll_input" => %{"gross" => 1000, "single_payment" => false}
    })

    assert :ok =
             ProcessEmploymentContractBlob.run_processing("https://example.com/document", blob, scope: processor_scope)

    assert {:ok, []} =
             MemberPayrollInput.list(
               %{member_id: employee.member.id, salary_month: ~D[2026-06-01]},
               scope: processor_scope
             )

    stub_extract(%{
      "document_type" => "payroll_statement",
      "payroll_input" => %{
        "currency" => "PLN",
        "salary_month" => "2026-06-01",
        "gross" => 0,
        "prior_taxable_income" => 9000,
        "single_payment" => false,
        "payout_date_basis" => "actual"
      }
    })

    assert :ok =
             ProcessEmploymentContractBlob.run_processing("https://example.com/document", blob, scope: processor_scope)

    assert {:ok, [input]} =
             MemberPayrollInput.list(
               %{member_id: employee.member.id, salary_month: ~D[2026-06-01]},
               scope: processor_scope
             )

    assert Decimal.equal?(input.gross, Decimal.new("0"))
    assert Decimal.equal?(input.prior_taxable_income, Decimal.new("9000"))
    assert input.single_payment == false
    assert input.payout_date_basis == :actual

    foreign_blob = blob_fixture!(org_id, employee.member.id)

    stub_extract(%{
      "document_type" => "payroll_statement",
      "payroll_input" => %{
        "currency" => "EUR",
        "salary_month" => "2026-06-01",
        "gross" => 1200,
        "single_payment" => true
      }
    })

    assert :ok =
             ProcessEmploymentContractBlob.run_processing(
               "https://example.com/document",
               foreign_blob,
               scope: processor_scope
             )

    assert {:ok, [retained_input]} =
             MemberPayrollInput.list(
               %{member_id: employee.member.id, salary_month: ~D[2026-06-01]},
               scope: processor_scope
             )

    assert retained_input.id == input.id
    assert Decimal.equal?(retained_input.gross, Decimal.new("0"))
    assert retained_input.single_payment == false

    unknown_currency_blob = blob_fixture!(org_id, employee.member.id)

    stub_extract(%{
      "document_type" => "payroll_statement",
      "payroll_input" => %{"salary_month" => "2026-08-01", "gross" => 1300}
    })

    assert :ok =
             ProcessEmploymentContractBlob.run_processing(
               "https://example.com/document",
               unknown_currency_blob,
               scope: processor_scope
             )

    assert {:ok, []} =
             MemberPayrollInput.list(
               %{member_id: employee.member.id, salary_month: ~D[2026-08-01]},
               scope: processor_scope
             )
  end

  defp scope(actor), do: %Scope{actor: actor, tenant: actor.member.organization_id}

  defp processor_scope(org_id) do
    %Scope{
      actor: %SystemActor{org_id: org_id, role: :document_blob_processor},
      tenant: org_id
    }
  end

  defp blob_fixture!(organization_id, member_id) do
    Ash.Seed.seed!(Blob, %{
      blob_path: "/test/employees/#{System.unique_integer([:positive])}.pdf",
      blob_checksum: "employee-document-#{System.unique_integer([:positive])}",
      original_filename: "employee-document.pdf",
      processing_target: :employment_contract,
      processing_metadata: %{"member_id" => member_id},
      organization_id: organization_id
    })
  end

  defp stub_extract(metadata) do
    Req.Test.stub(__MODULE__, fn conn ->
      {:ok, _body, conn} = Plug.Conn.read_body(conn)
      Req.Test.json(conn, %{result: metadata})
    end)
  end

  defp restore_env(key, nil), do: Application.delete_env(:firmowid, key)
  defp restore_env(key, value), do: Application.put_env(:firmowid, key, value)
end
