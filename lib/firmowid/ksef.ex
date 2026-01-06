defmodule Firmowid.Ksef do
  @moduledoc false
  import Ecto.Query, warn: false

  alias Firmowid.Accounts
  alias Firmowid.Ksef.Credential
  alias Firmowid.Ksef.FetchWorker
  alias Firmowid.Ksef.SessionWorker
  alias Firmowid.Ksef.SubmissionWorker
  alias Firmowid.Repo

  @doc """
  Authenticates the current organization with KSeF using the provided token.

  The token format is: `<id>|nip-<nip>|<hash>`
  Example: `20251129-EC-2880DEC000-943359B3B3-DA|nip-1234563218|7489ef19...`

  Returns:
    - `{:ok, credential}` on success
    - `{:error, :invalid_token_format}` if token format is invalid
    - `{:error, :nip_mismatch}` if NIP in token doesn't match organization's NIP
    - `{:error, :already_connected}` if organization already has KSeF credentials
  """
  def authenticate_with_ksef_token(ksef_token) when is_binary(ksef_token) do
    org_id = Repo.get_org_id()
    {:ok, organization} = Accounts.get_organization(org_id)

    with {:ok, token_nip} <- extract_nip_from_token(ksef_token),
         :ok <- validate_nip_match(token_nip, organization.identification_number),
         :ok <- validate_no_existing_credential() do
      {:ok, credential} =
        %Credential{}
        |> Credential.changeset(%{
          organization_id: org_id,
          auth_type: :token,
          credentials: ksef_token
        })
        |> Repo.insert()

      %{"organization_id" => org_id}
      |> SessionWorker.new()
      |> Firmowid.Oban.insert!()

      {:ok, credential}
    end
  end

  defp extract_nip_from_token(token) do
    case String.split(token, "|") do
      [_id, "nip-" <> nip, _hash] when byte_size(nip) > 0 ->
        {:ok, nip}

      _ ->
        {:error, :invalid_token_format}
    end
  end

  defp validate_nip_match(token_nip, org_nip) do
    # Normalize NIPs by removing any non-digit characters for comparison
    normalized_token_nip = String.replace(token_nip, ~r/\D/, "")
    normalized_org_nip = String.replace(org_nip || "", ~r/\D/, "")

    if normalized_token_nip == normalized_org_nip do
      :ok
    else
      {:error, :nip_mismatch}
    end
  end

  defp validate_no_existing_credential do
    case get_credential() do
      nil -> :ok
      _credential -> {:error, :already_connected}
    end
  end

  def get_credential do
    Repo.get_by(Credential, organization_id: Repo.get_org_id())
  end

  def unauthenticate do
    credential = get_credential()

    Firmowid.Oban.cancel_all_jobs(
      from(j in Oban.Job,
        where: j.worker in ["Firmowid.Ksef.SessionWorker", "Firmowid.Ksef.FetchWorker"],
        where: fragment("?->>'organization_id' = ?", j.args, ^Repo.get_org_id()),
        where: j.state in ["available", "scheduled", "executing"]
      )
    )

    Repo.delete(credential)
  end

  def fetch_cost_invoices(date_from) do
    %{
      "action" => "initiate_export",
      "organization_id" => Repo.get_org_id(),
      "date_from" => DateTime.to_iso8601(date_from)
    }
    |> FetchWorker.new()
    |> Firmowid.Oban.insert()
  end

  @doc """
  Submits a sales invoice to KSeF.

  The invoice must be fully confirmed and not already locked.
  This function enqueues a submission job that will:
  1. Open an online session with KSeF
  2. Generate FA(3) XML from the invoice
  3. Encrypt and submit the invoice
  4. Close the session
  5. Poll for the KSeF number

  Returns `{:ok, job}` on success, or `{:error, reason}` if the submission cannot be started.

  Possible errors:
  - `:not_authenticated` - Organization is not connected to KSeF
  - `:invoice_not_found` - Invoice with given ID doesn't exist
  - `:invoice_not_confirmed` - Invoice is not fully confirmed
  - `:invoice_already_locked` - Invoice has already been submitted or manually locked
  """
  def submit_sales_invoice(sales_invoice_id) do
    with :ok <- validate_ksef_authenticated(),
         {:ok, invoice} <- validate_invoice_for_submission(sales_invoice_id) do
      %{
        "action" => "submit",
        "organization_id" => Repo.get_org_id(),
        "sales_invoice_id" => invoice.id
      }
      |> SubmissionWorker.new()
      |> Firmowid.Oban.insert()
    end
  end

  defp validate_ksef_authenticated do
    case get_credential() do
      nil -> {:error, :not_authenticated}
      _credential -> :ok
    end
  end

  defp validate_invoice_for_submission(sales_invoice_id) do
    alias Firmowid.SalesInvoices.SalesInvoice

    invoice =
      SalesInvoice
      |> where([i], i.id == ^sales_invoice_id)
      |> Repo.one()

    cond do
      is_nil(invoice) ->
        {:error, :invoice_not_found}

      SalesInvoice.locked?(invoice) ->
        {:error, :invoice_already_locked}

      not SalesInvoice.confirmed?(invoice) ->
        {:error, :invoice_not_confirmed}

      true ->
        {:ok, invoice}
    end
  end
end
