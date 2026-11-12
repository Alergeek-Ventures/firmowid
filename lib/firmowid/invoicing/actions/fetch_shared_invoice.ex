defmodule Firmowid.Invoicing.Actions.FetchSharedInvoice do
  @moduledoc """
  Fetches the invoice chain a public share token authorizes, with the
  organization's VAT display setting and a short-lived logo URL.

  The root invoice is found with an Ecto query: Ash multitenancy needs the
  tenant before querying, and the tenant is known only once the invoice is
  found. Only the VAT display setting and that organization's own logo path
  join the lookup; no general organization or blob read is granted. The chain
  is then read through Ash with the discovered tenant and the root token.
  """

  use Ash.Resource.Actions.Implementation

  import Ecto.Query

  alias Firmowid.Blobs.Blob
  alias Firmowid.Core.Organization
  alias Firmowid.Invoicing.SalesInvoice
  alias Firmowid.Invoicing.Services.SalesInvoiceChain
  alias Firmowid.S3Client

  @impl true
  def run(input, _opts, context) do
    share_token = input.arguments.token
    opts = Ash.Context.to_opts(context)

    root_invoice_row =
      SalesInvoice
      |> join(:inner, [i], o in Organization, on: o.id == i.organization_id)
      |> join(:left, [i, o], b in Blob, on: b.id == o.avatar_blob_id and b.organization_id == i.organization_id)
      |> where([i], i.share_token == ^share_token and i.ksef_invoice_kind == :vat)
      |> select([i, o, b], {i.id, i.organization_id, o.is_vat_payer, b.blob_path})
      |> Firmowid.Repo.one(skip_organization_id: true)

    case root_invoice_row do
      nil ->
        {:ok, nil}

      {root_invoice_id, org_id, show_vat, logo_path} ->
        read_opts =
          opts
          |> Keyword.delete(:tenant)
          |> Keyword.put(:tenant, org_id)

        chain =
          SalesInvoiceChain.fetch_public_shared_chain!(
            root_invoice_id,
            share_token,
            read_opts
          )

        logo_url =
          if logo_path do
            {:ok, url} = S3Client.presigned_get_url(logo_path, expires_in: 200)
            url
          end

        {:ok, %{invoice: List.first(chain), show_vat: show_vat, logo_url: logo_url}}
    end
  end
end
