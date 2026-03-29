# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Firmowid.Seeds.Voidstack do
  @moduledoc """
  Seeds for VoidStack Labs — the evil org for authorization testing.

  Dragan Krypt, former Bytecraft intern fired for mining crypto on the
  office Keurig, now runs a 12-person operation from a converted bowling
  alley in Bratislava.
  """

  import Ecto.Query

  alias Firmowid.Accounts
  alias Firmowid.Accounts.Organization
  alias Firmowid.Ash.Finances.TransactionQueries
  alias Firmowid.Ash.Timetracker.Project, as: AshProject
  alias Firmowid.CostInvoices
  alias Firmowid.Repo
  alias Firmowid.SalesInvoices
  alias Firmowid.Seeds.Helpers

  def seed! do
    dragan = seed_dragan()
    voidstack = seed_organization(dragan)
    Repo.put_org_id(voidstack.id)
    seed_project(dragan)
    seed_blob(voidstack)
    seed_bank_and_transactions(voidstack)
    seed_cost_invoice(voidstack)
    seed_sales_invoice(voidstack)
  end

  defp seed_dragan do
    dragan =
      case Accounts.register_user(%{email: "dragan@voidstack.io", password: "kolejka123456"}) do
        {:ok, user} -> user
        {:error, _} -> Accounts.get_user_by_email("dragan@voidstack.io")
      end

    Accounts.update_user(dragan, %{
      system_role: :user,
      role: :admin,
      name: "Dragan Krypt",
      position: "CEO & Chief Chaos Officer",
      employment_contract_type: :b2b,
      phone: "+421 902 555 666"
    })

    dragan
  end

  defp seed_organization(dragan) do
    case Repo.one(
           from(o in Organization, where: o.nip == "7871963656", limit: 1),
           skip_organization_id: true
         ) do
      nil ->
        {:ok, org} =
          Accounts.create_organization(
            %{
              "name" => "VoidStack Labs spółka z ograniczoną odpowiedzialnością",
              "nip" => "7871963656",
              "address" => "ul. Kręgielnia 1, 811 01 Bratislava (oddział w Polsce)",
              "owner_id" => dragan.id
            },
            dragan
          )

        org

      org ->
        org
    end
  end

  defp seed_project(dragan) do
    project =
      case Repo.one(
             from(p in AshProject,
               where: p.name == "Shadow Protocol",
               limit: 1
             )
           ) do
        nil ->
          {:ok, p} =
            AshProject.create(
              %{name: "Shadow Protocol"},
              tenant: Repo.get_org_id(),
              authorize?: false,
              actor: %{}
            )

          p

        p ->
          p
      end

    {:ok, _} =
      AshProject.set_users([dragan.id], %{project_id: project.id},
        tenant: Repo.get_org_id(),
        authorize?: false,
        actor: %{}
      )

    project
  end

  defp seed_blob(voidstack) do
    Helpers.get_or_create_blob("aaaaaaaa-1111-4b80-9d53-a71d0efc4cad", %{
      blob_path: "aaaaaaaa-1111-4b80-9d53-a71d0efc4cad/void-invoice.pdf",
      blob_checksum: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      original_filename: "void-invoice.pdf",
      organization_id: voidstack.id
    })
  end

  defp seed_bank_and_transactions(voidstack) do
    bank =
      Helpers.get_or_create_bank_account("aaaaaaaa-2222-4088-b6a1-08950daa5ec2", %{
        iban: "PL98109024020000000142345678",
        institution_id: "SANTANDER_PL",
        institution_name: "Santander Bank Polska",
        owner_name: "VoidStack Labs sp. z o.o.",
        currency: "PLN",
        organization_id: voidstack.id,
        is_default: true
      })

    transactions = [
      %{
        internal_transaction_id: "void_bankfee",
        creditor_name: "Santander Bank Polska S.A.",
        creditor_account: "INTERNAL",
        debtor_name: "VoidStack Labs sp. z o.o.",
        debtor_account: "PL98109024020000000142345678",
        transaction_amount: -25.00,
        transaction_currency: "PLN",
        booking_date: Helpers.date_this_month(1),
        bank_account_id: bank.id,
        organization_id: voidstack.id,
        skip_invoicing: true,
        remittance_information_unstructured: "Opłata za prowadzenie rachunku"
      },
      %{
        internal_transaction_id: "void_allegro_chair",
        creditor_name: "Allegro.pl Sp. z o.o.",
        creditor_account: "PL60102019250000000103445301",
        debtor_name: "VoidStack Labs sp. z o.o.",
        debtor_account: "PL98109024020000000142345678",
        transaction_amount: -1_200.00,
        transaction_currency: "PLN",
        booking_date: Helpers.date_this_month(4),
        bank_account_id: bank.id,
        organization_id: voidstack.id,
        skip_invoicing: false,
        remittance_information_unstructured: "Allegro — fotel biurowy ergonomiczny"
      },
      %{
        internal_transaction_id: "void_zabka",
        creditor_name: "Żabka Polska S.A.",
        creditor_account: "N/A",
        debtor_name: "VoidStack Labs sp. z o.o.",
        debtor_account: "PL98109024020000000142345678",
        transaction_amount: -87.50,
        transaction_currency: "PLN",
        booking_date: Helpers.date_this_month(6),
        bank_account_id: bank.id,
        organization_id: voidstack.id,
        skip_invoicing: false,
        remittance_information_unstructured: "Żabka — napoje energetyczne dla zespołu × 25 szt."
      },
      %{
        internal_transaction_id: "void_mystery_client",
        creditor_name: "VoidStack Labs sp. z o.o.",
        creditor_account: "PL98109024020000000142345678",
        debtor_name: "Mysterious Client LLC",
        debtor_account: "N/A",
        transaction_amount: 15_000.00,
        transaction_currency: "PLN",
        booking_date: Helpers.date_this_month(8),
        bank_account_id: bank.id,
        organization_id: voidstack.id,
        skip_invoicing: false,
        remittance_information_unstructured: "Shadow Protocol — dostawa fazy 1"
      }
    ]

    TransactionQueries.create_or_update(transactions)
  end

  defp seed_cost_invoice(voidstack) do
    today = Helpers.today()

    blob =
      Repo.get(Firmowid.Blobs.Blob, "aaaaaaaa-1111-4b80-9d53-a71d0efc4cad")

    if is_nil(Repo.get(CostInvoices.CostInvoice, "aaaaaaaa-3333-7433-bd41-3d8b719610a4")) do
      Repo.insert!(%CostInvoices.CostInvoice{
        id: "aaaaaaaa-3333-7433-bd41-3d8b719610a4",
        blob_id: blob && blob.id,
        seller: "Allegro.pl Sp. z o.o.",
        seller_display_name: "Allegro",
        sale_date: Helpers.date_this_month(4),
        issue_date: Helpers.date_this_month(5),
        due_date: Helpers.date_this_month(19),
        total_amount: -1_200.00,
        currency: "PLN",
        invoice_identifier: "ALG/#{today.year}/#{String.pad_leading("#{today.month}", 2, "0")}/001",
        description: "Fotel biurowy ergonomiczny — Dragan upierał się przy modelu wyścigowym",
        skip_invoicing: false,
        organization_id: voidstack.id,
        seller_address: "ul. Grunwaldzka 182, 60-166 Poznań"
      })
    end
  end

  defp seed_sales_invoice(voidstack) do
    prefix = Helpers.month_prefix(0)
    inv_number = "VS/01/#{prefix}"

    existing =
      Repo.one(
        from(si in SalesInvoices.SalesInvoice,
          where: si.invoice_number == ^inv_number and si.organization_id == ^voidstack.id,
          limit: 1
        )
      )

    if is_nil(existing) do
      SalesInvoices.create_sales_invoice(
        %SalesInvoices.SalesInvoice{organization_id: voidstack.id},
        %{
          "invoice_number" => inv_number,
          "invoice_type" => "poland",
          "issue_date" => Helpers.date_this_month(8),
          "sale_date" => Helpers.date_this_month(8),
          "due_date" => Helpers.date_this_month(22),
          "currency" => "PLN",
          "seller_display_name" => "VoidStack Labs sp. z o.o.",
          "seller_address" => "ul. Kręgielnia 1, 811 01 Bratislava (oddział w Polsce)",
          "seller_nip" => "7871963656",
          "seller_account_number" => "PL98109024020000000142345678",
          "buyer_display_name" => "Mysterious Client LLC",
          "buyer_full_name" => "Mysterious Client LLC",
          "buyer_address" => "ul. Tajemnicza 13, 00-666 Warszawa",
          "buyer_country" => "PL",
          "buyer_id" => "5213370128",
          "buyer_type" => "company",
          "payment_method" => "transfer",
          "is_reverse_charge" => false,
          "is_cash_account" => false,
          "sales_invoice_items" => [
            %{
              "name" => "Shadow Protocol — dostawa fazy 1",
              "quantity" => 120,
              "unit" => "godz.",
              "unit_price" => 100.00,
              "vat_rate" => "23"
            },
            %{
              "name" => "Awaryjne zaopatrzenie w napoje energetyczne",
              "quantity" => 25,
              "unit" => "szt.",
              "unit_price" => 3.50,
              "vat_rate" => "23"
            }
          ]
        }
      )
    end
  end
end
