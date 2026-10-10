defmodule Firmowid.Ash.Payroll.UserEmploymentContractTest do
  use Firmowid.DataCase, async: true

  import Firmowid.AccountsFixtures

  alias Ash.Error.Forbidden
  alias Firmowid.Ash.Blobs.Blob
  alias Firmowid.Ash.Payroll
  alias Firmowid.Ash.Payroll.UserEmploymentContract
  alias Firmowid.Ash.Payroll.Workers.EmploymentContractEmailWorker
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor

  setup do
    admin = admin_fixture()
    employee = user_in_org_fixture(admin.organization_id)
    org_id = admin.organization_id

    %{
      admin: admin,
      employee: employee,
      org_id: org_id,
      admin_scope: scope(admin),
      employee_scope: scope(employee),
      processor_scope: processor_scope(org_id)
    }
  end

  describe "read and list authorization" do
    test "employee reads only their own contracts even when listing another user", %{
      admin: admin,
      employee: employee,
      employee_scope: employee_scope,
      processor_scope: processor_scope
    } do
      own_contract = contract_fixture!(employee, processor_scope, %{})
      contract_fixture!(admin, processor_scope, %{})

      assert {:ok, [read_contract]} = UserEmploymentContract.read(scope: employee_scope)
      assert read_contract.id == own_contract.id
      assert {:ok, [listed_contract]} = Payroll.list_employment_contracts(scope: employee_scope)
      assert listed_contract.id == own_contract.id

      assert {:ok, []} =
               Payroll.list_employment_contracts(%{user_id: admin.id}, scope: employee_scope)

      assert {:ok, fetched_contract} =
               Payroll.get_employment_contract(own_contract.id, scope: employee_scope)

      assert fetched_contract.id == own_contract.id
    end

    test "organization cleanup keeps list access without gaining framework read access", %{
      employee: employee,
      org_id: org_id,
      processor_scope: processor_scope
    } do
      contract = contract_fixture!(employee, processor_scope, %{})

      cleanup_scope = %Scope{
        actor: %SystemActor{org_id: org_id, role: :organization_cleanup},
        tenant: org_id
      }

      assert {:ok, [listed_contract]} = Payroll.list_employment_contracts(scope: cleanup_scope)
      assert listed_contract.id == contract.id
      assert {:ok, []} = UserEmploymentContract.read(scope: cleanup_scope)
    end
  end

  describe "submit_signed/3 activation" do
    test "activates contract when starts_at is today or in the past", %{
      employee: employee,
      employee_scope: employee_scope,
      processor_scope: processor_scope
    } do
      contract =
        contract_fixture!(employee, processor_scope, %{
          starts_at: Date.utc_today(),
          status: :pending_signature
        })

      assert {:ok, updated} =
               Payroll.submit_signed(
                 contract,
                 signed_upload_path!(),
                 "signed.pdf",
                 scope: employee_scope
               )

      assert updated.status == :active
    end

    test "keeps contract signed when starts_at is in the future", %{
      employee: employee,
      employee_scope: employee_scope,
      processor_scope: processor_scope
    } do
      contract =
        contract_fixture!(employee, processor_scope, %{
          starts_at: Date.add(Date.utc_today(), 30),
          status: :pending_signature
        })

      assert {:ok, updated} =
               Payroll.submit_signed(
                 contract,
                 signed_upload_path!(),
                 "signed.pdf",
                 scope: employee_scope
               )

      assert updated.status == :signed
    end
  end

  describe "activate/2" do
    test "allows admin and document_blob_processor to activate contract", %{
      employee: employee,
      admin_scope: admin_scope,
      processor_scope: processor_scope
    } do
      contract_for_admin =
        contract_fixture!(employee, processor_scope, %{
          starts_at: Date.add(Date.utc_today(), 10),
          status: :signed
        })

      assert {:ok, activated} = Payroll.activate(contract_for_admin, scope: admin_scope)
      assert activated.status == :active

      contract_for_processor =
        contract_fixture!(employee, processor_scope, %{
          starts_at: Date.add(Date.utc_today(), 1),
          status: :signed
        })

      assert {:ok, activated} = Payroll.activate(contract_for_processor, scope: processor_scope)
      assert activated.status == :active
    end
  end

  describe "email notifications" do
    test "submit_signed enqueues admin notification job", %{
      employee: employee,
      employee_scope: employee_scope,
      org_id: org_id,
      processor_scope: processor_scope
    } do
      contract =
        contract_fixture!(employee, processor_scope, %{
          starts_at: Date.add(Date.utc_today(), 30),
          status: :pending_signature
        })

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _contract} =
                 Payroll.submit_signed(
                   contract,
                   signed_upload_path!(),
                   "signed.pdf",
                   scope: employee_scope
                 )

        assert_enqueued(
          worker: EmploymentContractEmailWorker,
          args: %{
            "contract_id" => contract.id,
            "organization_id" => org_id,
            "kind" => "admin_notification"
          }
        )
      end)
    end

    test "create pending_signature enqueues employee email", %{
      employee: employee,
      org_id: org_id,
      processor_scope: processor_scope
    } do
      Oban.Testing.with_testing_mode(:manual, fn ->
        contract =
          contract_fixture!(employee, processor_scope, %{
            starts_at: Date.utc_today(),
            status: :pending_signature
          })

        assert_enqueued(
          worker: EmploymentContractEmailWorker,
          args: %{
            "contract_id" => contract.id,
            "organization_id" => org_id
          }
        )
      end)
    end
  end

  describe "update/2 policies" do
    test "admin can update contract details, employee cannot", %{
      admin: admin,
      employee: employee,
      admin_scope: admin_scope,
      employee_scope: employee_scope,
      processor_scope: processor_scope
    } do
      contract =
        contract_fixture!(employee, processor_scope, %{
          starts_at: Date.utc_today(),
          status: :pending_signature,
          position: "Developer"
        })

      assert {:ok, updated} =
               Payroll.update_employment_contract(
                 contract,
                 %{position: "Lead Developer"},
                 scope: admin_scope,
                 actor: admin
               )

      assert updated.position == "Lead Developer"

      assert {:error, %Forbidden{}} =
               Payroll.update_employment_contract(
                 updated,
                 %{position: "Hacker"},
                 scope: employee_scope,
                 actor: employee
               )
    end
  end

  defp scope(actor) do
    %Scope{actor: actor, tenant: actor.organization_id}
  end

  defp processor_scope(org_id) do
    %Scope{
      actor: %SystemActor{org_id: org_id, role: :document_blob_processor},
      tenant: org_id
    }
  end

  defp contract_fixture!(employee, processor_scope, attrs) do
    blob = blob_fixture!(employee.organization_id)

    defaults = %{
      user_id: employee.id,
      starts_at: Date.utc_today(),
      salary: Money.new!(:PLN, Decimal.new("100")),
      blob_id: blob.id,
      status: :pending_signature,
      contract_type: :uop,
      position: "Developer"
    }

    attrs = Map.merge(defaults, attrs)

    Payroll.create_employment_contract!(attrs, scope: processor_scope)
  end

  defp blob_fixture!(organization_id) do
    Ash.Seed.seed!(Blob, %{
      blob_path: "/test/contracts/#{System.unique_integer([:positive])}.pdf",
      blob_checksum: "contract-#{System.unique_integer([:positive])}",
      original_filename: "contract.pdf",
      organization_id: organization_id
    })
  end

  defp signed_upload_path! do
    {:ok, path} = Briefly.create()
    File.write!(path, "%PDF-1.4 signed #{System.unique_integer([:positive])}")
    path
  end
end
