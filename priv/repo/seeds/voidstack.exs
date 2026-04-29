# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Firmowid.Seeds.Voidstack do
  @moduledoc """
  Seeds for VoidStack Labs — the evil org for authorization testing.

  Dragan Krypt, former Bytecraft intern fired for mining crypto on the
  office Keurig, now runs a 12-person operation from a converted bowling
  alley in Bratislava.
  """

  alias Firmowid.Ash.Analysis.TagDefinition, as: AshTagDefinition
  alias Firmowid.Ash.Core.Organization, as: CoreOrganization
  alias Firmowid.Ash.Core.User, as: CoreUser
  alias Firmowid.Ash.Invoicing.CostInvoice, as: AshCostInvoice
  alias Firmowid.Ash.Timetracker.Project, as: AshProject
  alias Firmowid.Ash.Timetracker.ProjectUser, as: AshProjectUser
  alias Firmowid.Seeds.Helpers

  require Ash.Query

  @seed_actor %{id: "00000000-0000-0000-0000-000000000000", role: :admin}

  def seed! do
    dragan = seed_dragan()
    voidstack = seed_organization(dragan)
    seed_org_membership(voidstack, dragan)
    seed_project(dragan, voidstack)
    blob = seed_blob(voidstack)
    seed_bank_and_transactions(voidstack)
    seed_cost_invoice(voidstack, blob)
    seed_sales_invoice(voidstack)
  end

  defp seed_dragan do
    dragan =
      Ash.Seed.upsert!(
        CoreUser,
        %{email: "dragan@voidstack.io", hashed_password: Argon2.hash_pwd_salt("kolejka123456")},
        identity: :unique_email
      )

    Ash.Seed.update!(dragan, %{
      system_role: :user,
      role: :admin,
      name: "Dragan Krypt",
      position: "CEO & Chief Chaos Officer",
      phone: "+421 902 555 666"
    })
  end

  defp seed_organization(dragan) do
    Ash.Seed.upsert!(
      CoreOrganization,
      %{
        name: "VoidStack Labs spółka z ograniczoną odpowiedzialnością",
        nip: "7871963656",
        address: "ul. Kręgielnia 1, 811 01 Bratislava (oddział w Polsce)",
        owner_id: dragan.id,
        inbound_email_nickname: "voidstack"
      },
      identity: :unique_nickname
    )
  end

  defp seed_org_membership(voidstack, dragan) do
    if is_nil(dragan.organization_id) or dragan.organization_id != voidstack.id do
      Ash.Seed.update!(dragan, %{organization_id: voidstack.id})
    end
  end

  defp seed_project(dragan, voidstack) do
    tag_definition =
      Ash.Seed.upsert!(
        AshTagDefinition,
        %{name: "Shadow Protocol", organization_id: voidstack.id},
        identity: :unique_name_per_org,
        tenant: voidstack.id
      )

    project =
      case find_project(voidstack.id, "Shadow Protocol") do
        nil ->
          Ash.Seed.seed!(
            AshProject,
            %{name: "Shadow Protocol", organization_id: voidstack.id, tag_definition_id: tag_definition.id},
            tenant: voidstack.id
          )

        project ->
          project
      end

    if is_nil(find_project_user(voidstack.id, project.id, dragan.id)) do
      Ash.Seed.seed!(
        AshProjectUser,
        %{project_id: project.id, user_id: dragan.id, organization_id: voidstack.id},
        tenant: voidstack.id
      )
    end

    project
  end

  defp seed_blob(voidstack) do
    Helpers.seed_blob!(
      %{
        blob_path: "aaaaaaaa-1111-4b80-9d53-a71d0efc4cad/void-invoice.pdf",
        blob_checksum: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        original_filename: "void-invoice.pdf"
      },
      voidstack.id
    )
  end

  defp seed_bank_and_transactions(voidstack) do
    bank =
      Helpers.seed_bank_account!(
        %{
          iban: "PL98109024020000000142345678",
          institution_id: "SANTANDER_PL",
          institution_name: "Santander Bank Polska",
          owner_name: "VoidStack Labs sp. z o.o.",
          currency: "PLN",
          is_default: true
        },
        voidstack.id
      )

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
        skip_invoicing: false,
        remittance_information_unstructured: "Shadow Protocol — dostawa fazy 1"
      }
    ]

    Enum.each(transactions, fn attrs ->
      Helpers.seed_transaction!(attrs, voidstack.id)
    end)
  end

  defp seed_cost_invoice(voidstack, blob) do
    today = Helpers.today()

    Ash.Seed.seed!(
      AshCostInvoice,
      %{
        id: "aaaaaaaa-3333-7433-bd41-3d8b719610a4",
        blob_id: blob.id,
        seller: "Allegro.pl Sp. z o.o.",
        seller_display_name: "Allegro",
        sale_date: Helpers.date_this_month(4),
        issue_date: Helpers.date_this_month(5),
        due_date: Helpers.date_this_month(19),
        total_amount: Decimal.new("-1200.00"),
        currency: "PLN",
        invoice_identifier: "ALG/#{today.year}/#{String.pad_leading("#{today.month}", 2, "0")}/001",
        description: "Fotel biurowy ergonomiczny — Dragan upierał się przy modelu wyścigowym",
        skip_invoicing: false,
        organization_id: voidstack.id,
        seller_address: "ul. Grunwaldzka 182, 60-166 Poznań"
      },
      tenant: voidstack.id
    )
  end

  defp seed_sales_invoice(voidstack) do
    prefix = Helpers.month_prefix(0)

    Helpers.get_or_create_sales_invoice("VS/01/#{prefix}", voidstack.id, %{
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
      "buyer_id" => "5213370120",
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
    })
  end

  defp find_project(tenant, name) do
    query =
      AshProject
      |> Ash.Query.filter(organization_id == ^tenant and name == ^name)
      |> Ash.Query.limit(1)

    case Ash.read(query, tenant: tenant, actor: @seed_actor) do
      {:ok, [project | _]} -> project
      _ -> nil
    end
  end

  defp find_project_user(tenant, project_id, user_id) do
    query =
      AshProjectUser
      |> Ash.Query.filter(organization_id == ^tenant and project_id == ^project_id and user_id == ^user_id)
      |> Ash.Query.limit(1)

    case Ash.read(query, tenant: tenant, actor: @seed_actor) do
      {:ok, [project_user | _]} -> project_user
      _ -> nil
    end
  end
end
