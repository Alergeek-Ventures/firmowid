defmodule Firmowid.BankDataTest do
  use Firmowid.DataCase
  alias Firmowid.BankData

  test "syncing accounts for requisition works" do
    Req.Test.stub(:bank_data_requisition, fn conn ->
      Req.Test.json(
        conn,
        %{
          id: "3fa85f64-5717-4562-b3fc-2c963f66afa6",
          created: "2024-12-30T15:00:42.026Z",
          redirect: "string",
          status: "LN",
          institution_id: "string",
          agreement: "3fa85f64-5717-4562-b3fc-2c963f66afa7",
          reference: "string",
          accounts: [
            "3fa85f64-5717-4562-b3fc-2c963f66afa8"
          ],
          user_language: "string",
          link:
            "https://ob.gocardless.com/psd2/start/3fa85f64-5717-4562-b3fc-2c963f66afa6/b19af386-8228-410d-bd1c-a44692727635",
          ssn: "string",
          account_selection: false,
          redirect_immediate: false
        }
      )
    end)

    Req.Test.stub(:bank_data_account, fn conn ->
      Req.Test.json(
        conn,
        %{
          id: "3fa85f64-5717-4562-b3fc-2c963f66afa8",
          created: "2024-12-30T15:02:11.463Z",
          last_accessed: "2024-12-30T15:02:11.463Z",
          iban: "PL12345678901234567890123456",
          bban: "PL12345678901234567890123456",
          status: "string",
          institution_id: "N26_NTSBDEB1",
          owner_name: "Alergeek Ventures"
        }
      )
    end)

    Req.Test.stub(:bank_data_transactions, fn conn ->
      Req.Test.json(
        conn,
        %{
          transactions: %{
            booked: [
              %{
                transactionId: "string",
                creditorName: "N26 Bank",
                creditorAccount: %{
                  iban: "string"
                },
                debtorName: "string",
                debtorAccount: %{
                  iban: "string"
                },
                transactionAmount: %{
                  currency: "EUR",
                  amount: "-32"
                },
                bankTransactionCode: "string",
                bookingDate: "2023-12-30",
                valueDate: "2023-12-30",
                remittanceInformationUnstructured: "Testowa transakcja"
              },
              %{
                transactionId: "2",
                creditorName: "Nest Bank S.A.",
                creditorAccount: %{
                  iban: "string"
                },
                debtorName: "string",
                debtorAccount: %{
                  iban: "string"
                },
                transactionAmount: %{
                  currency: "EUR",
                  amount: "-12.45"
                },
                bankTransactionCode: "string",
                bookingDate: "2023-12-30",
                valueDate: "2023-12-30",
                remittanceInformationUnstructured: "Alergeek Ventures, Nr karty 123"
              },
              %{
                "balance_after_transaction" => %{
                  "balance_amount" => %{"amount" => "11227.32", "currency" => "PLN"},
                  "balance_type" => "interimBooked"
                },
                "booking_date" => "2024-12-24",
                "booking_date_time" => "2024-12-24T23:00:00.000+0000",
                "creditor_name" => "Nest Bank S.A.",
                "debtor_name" => "ALERGEEK VENTURES SPÓŁKA Z OG",
                "internal_transaction_id" => "1c5705ede00e47e55021d6be8c34a791",
                "remittance_information_unstructured" =>
                  "NOTION LABS, INC. NOTION.SO, Nr karty ...9285 840,00USD 4,3224",
                "remittance_information_unstructured_array" => [
                  "NOTION LABS, INC. NOTION.SO, Nr karty ...9285 840,00USD 4,3224"
                ],
                "transaction_amount" => %{"amount" => "-3630.82", "currency" => "PLN"},
                "transaction_id" => "AT#548394693",
                "value_date" => "2024-12-21"
              }
            ],
            pending: []
          }
        }
      )
    end)

    {:ok, owner} =
      Firmowid.Accounts.register_user(%{
        email: "owner@a.com",
        password: "testing123456"
      })

    {:ok, organization} =
      %Firmowid.Accounts.Organization{
        id: "3fa85f64-5717-4562-b3fc-2c963f66afa7",
        identification_number: "123456789",
        slug: "firmowid",
        name: "Firmowid",
        owner_id: owner.id
      }
      |> Firmowid.Accounts.Organization.changeset()
      |> Repo.insert()

    {:ok, requisition} =
      %Firmowid.BankData.Requisition{
        requisition_id: "3fa85f64-5717-4562-b3fc-2c963f66afa6",
        status: :accepted,
        organization_id: organization.id
      }
      |> Firmowid.BankData.Requisition.changeset()
      |> Repo.insert(organization_id: organization.id)

    {:ok, bank_account} =
      %Firmowid.Finances.BankAccount{
        iban: "PL12345678901234567890123456",
        organization_id: organization.id,
        requisition_id: requisition.id,
        gocardless_id: "3fa85f64-5717-4562-b3fc-2c963f66afa5"
      }
      |> Firmowid.Finances.BankAccount.changeset()
      |> Repo.insert(organization_id: organization.id)

    BankData.sync_bank_account(bank_account.id, :skip_organization_id)

    imported_transactions =
      Firmowid.Finances.ImportedTransaction
      |> Repo.all(organization_id: organization.id)

    n26 = imported_transactions |> Enum.find(&(&1.creditor_name == "N26 Bank"))

    assert is_nil(n26) == false
    assert n26.transaction_amount == Decimal.new("-32.00")

    nest_bank = imported_transactions |> Enum.find(&(&1.creditor_name == "Alergeek Ventures"))

    assert is_nil(nest_bank) == false
    assert nest_bank.transaction_amount == Decimal.new("-12.45")

    notion_labs =
      imported_transactions |> Enum.find(&(&1.creditor_name == "NOTION LABS, INC. NOTION.SO"))

    assert is_nil(notion_labs) == false
    assert notion_labs.transaction_amount == Decimal.new("-3630.82")
    assert notion_labs.creditor_account == "N/A"

    assert length(imported_transactions) == 3
  end

  test "lists institutions properly" do
    Req.Test.stub(:bank_data_institutions, fn conn ->
      Req.Test.json(conn, [
        %{
          id: "N26_NTSBDEB1",
          name: "N26 Bank",
          bic: "NTSBDEB1",
          transaction_total_days: "90",
          countries: [
            "PL",
            "BE",
            "DE"
          ],
          logo: "https://cdn-logos.gocardless.com/ais/N26_SANDBOX_NTSBDEB1.png",
          identification_codes: [],
          max_access_valid_for_days: "180"
        }
      ])
    end)

    institutions = BankData.get_available_institutions_for_country("PL")

    assert length(institutions) == 1

    [n26] = institutions

    assert n26 == %{
             "id" => "N26_NTSBDEB1",
             "name" => "N26 Bank",
             "bic" => "NTSBDEB1",
             "transaction_total_days" => "90",
             "countries" => [
               "PL",
               "BE",
               "DE"
             ],
             "logo" => "https://cdn-logos.gocardless.com/ais/N26_SANDBOX_NTSBDEB1.png",
             "identification_codes" => [],
             "max_access_valid_for_days" => "180"
           }
  end
end
