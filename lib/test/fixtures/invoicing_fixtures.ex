defmodule Firmowid.InvoicingFixtures do
  @moduledoc """
  Test helpers for invoicing-domain records.

  Issuance always goes through KSeF, so tests that need an invoice in a given
  lifecycle state (issued, mid-submission, accepted by KSeF) seed that state directly.
  """

  import Ecto.Query, only: [from: 2]

  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Ksef.Credential

  @doc "Seeds a working KSeF connection, which issuance requires, unless the organization has one."
  @spec connect_ksef!(Ecto.UUID.t()) :: :ok
  def connect_ksef!(organization_id) do
    connected? =
      Firmowid.Repo.exists?(
        from(credential in "ksef_credentials",
          where: credential.organization_id == type(^organization_id, :binary_id)
        )
      )

    if !connected? do
      Ash.Seed.seed!(Credential, %{
        organization_id: organization_id,
        status: :working,
        auth_type: :token,
        credentials: "token-#{System.unique_integer([:positive])}"
      })
    end

    :ok
  end

  @doc """
  Connects KSeF and stubs its API to accept every submitted invoice.

  Test Oban runs jobs inline, so issuance submits and verifies inside its own transaction.
  """
  @spec accept_ksef_submissions!(Ecto.UUID.t()) :: :ok
  def accept_ksef_submissions!(organization_id) do
    connect_ksef!(organization_id)

    access_token = jwt_expiring_at(DateTime.shift(DateTime.utc_now(), minute: 5))

    Cachex.put(:ksef, {:access_token, organization_id}, access_token, expire: to_timeout(minute: 5))

    private_key = X509.PrivateKey.new_rsa(2048)

    Cachex.put(
      :ksef,
      {:public_key, "SymmetricKeyEncryption"},
      X509.Certificate.self_signed(private_key, "/CN=KSeF Test")
    )

    Req.Test.stub(:ksef_api, fn conn ->
      case {conn.method, String.replace_prefix(conn.request_path, "/v2", "")} do
        {"POST", "/sessions/online"} ->
          Req.Test.json(Plug.Conn.put_status(conn, 201), %{"referenceNumber" => "SESSION-REF"})

        {"POST", "/sessions/online/SESSION-REF/invoices"} ->
          Req.Test.json(Plug.Conn.put_status(conn, 202), %{"referenceNumber" => "INVOICE-REF"})

        {"POST", "/sessions/online/SESSION-REF/close"} ->
          Plug.Conn.send_resp(conn, 204, "")

        {"GET", "/sessions/SESSION-REF/invoices/INVOICE-REF"} ->
          Req.Test.json(conn, %{
            "status" => %{"code" => 200},
            "ksefNumber" => "KSEF-#{System.unique_integer([:positive])}",
            "acquisitionDate" => DateTime.to_iso8601(DateTime.utc_now()),
            "invoiceHash" => "verified-hash"
          })
      end
    end)
  end

  defp jwt_expiring_at(expires_at) do
    encode = &(&1 |> Jason.encode!() |> Base.url_encode64(padding: false))

    encode.(%{"alg" => "none", "typ" => "JWT"}) <>
      "." <> encode.(%{"exp" => DateTime.to_unix(expires_at)}) <> ".signature"
  end

  @doc "Seeds a sales invoice with its line items in the organization given by `:scope` or `:tenant`."
  @spec seed_sales_invoice(map(), keyword()) :: {:ok, SalesInvoice.t()}
  def seed_sales_invoice(attrs, opts), do: {:ok, seed_sales_invoice!(attrs, opts)}

  @doc "Seeds a sales invoice with its line items in the organization given by `:scope` or `:tenant`."
  @spec seed_sales_invoice!(map(), keyword()) :: SalesInvoice.t()
  def seed_sales_invoice!(attrs, opts) do
    organization_id =
      case Keyword.fetch(opts, :scope) do
        {:ok, scope} -> scope.tenant
        :error -> Keyword.fetch!(opts, :tenant)
      end

    {items, attrs} = Map.pop(attrs, :sales_invoice_items, [])

    items =
      items
      |> Enum.with_index()
      |> Enum.map(fn {item, index} ->
        Map.merge(%{index: index, vat_rate: "23", organization_id: organization_id}, item)
      end)

    SalesInvoice
    |> Ash.Seed.seed!(
      attrs
      |> Map.put(:organization_id, organization_id)
      |> Map.put_new(:item_names, Enum.map_join(items, " ", & &1.name))
      |> Map.put(:sales_invoice_items, items)
    )
    |> Ash.load!([:sales_invoice_items], Keyword.take(opts, [:scope, :actor, :tenant]))
  end
end
