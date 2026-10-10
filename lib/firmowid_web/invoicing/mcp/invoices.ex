defmodule FirmowidWeb.Invoicing.Mcp.Invoices do
  @moduledoc "MCP presentation contract for the read-only invoice list tool and LiveView."

  alias FirmowidWeb.Core.Endpoint
  alias FirmowidWeb.Invoicing.Utilities.Navigation

  @doc "Returns the sole invoice MCP tool name."
  @spec tool_name() :: String.t()
  def tool_name, do: "list_invoices"

  @doc "Returns the versioned native invoice UI resource URI."
  @spec resource_uri() :: String.t()
  def resource_uri, do: "ui://firmowid/invoicing/invoices-v1.html"

  @doc "Returns the feature-owned embedded LiveView."
  @spec live_view() :: module()
  def live_view, do: FirmowidWeb.Invoicing.Mcp.Views.Index

  @doc "Declares this tool's read-only semantics independently of the shared transport."
  @spec annotations() :: map()
  def annotations do
    %{"readOnlyHint" => true, "destructiveHint" => false, "openWorldHint" => false}
  end

  @doc "Adds canonical absolute invoice details URLs to the JSON-safe backend result."
  @spec present_result(map()) :: map()
  def present_result(%{invoices: invoices} = result) do
    Map.put(result, :invoices, Enum.map(invoices, &Map.put(&1, :url, invoice_url(&1))))
  end

  def present_result(%{"invoices" => invoices} = result) do
    Map.put(
      result,
      "invoices",
      Enum.map(invoices, fn invoice ->
        Map.put(invoice, "url", invoice_url(%{type: invoice["type"], id: invoice["id"]}))
      end)
    )
  end

  @doc "Returns the JSON Schema for presented tool results, including invoice URLs."
  @spec output_schema() :: map()
  def output_schema do
    nullable_string = %{type: ["string", "null"]}
    nullable_date = Map.put(nullable_string, :format, "date")

    invoice_properties = %{
      id: %{type: "string", format: "uuid"},
      type: %{type: "string", enum: ["sales", "cost"]},
      number: nullable_string,
      issue_date: nullable_date,
      due_date: nullable_date,
      counterparty: %{type: "string"},
      amount: object(%{value: %{type: "string"}, currency: nullable_string}),
      ksef_number: nullable_string,
      invoice_kind: nullable_string,
      url: %{type: "string", format: "uri"}
    }

    query_properties = %{
      type: %{type: "string", enum: ["all", "sales", "cost"]},
      query: nullable_string,
      date_from: nullable_date,
      date_to: nullable_date,
      currency: nullable_string,
      sort: %{type: "string", enum: ["newest", "oldest"]},
      limit: %{type: "integer", minimum: 1, maximum: 100}
    }

    object(%{
      invoices: %{type: "array", items: object(invoice_properties), maxItems: 100},
      query: object(query_properties),
      has_more: %{type: "boolean"},
      next_cursor: nullable_string
    })
  end

  defp object(properties) do
    %{
      type: "object",
      properties: properties,
      required: properties |> Map.keys() |> Enum.map(&Atom.to_string/1),
      additionalProperties: false
    }
  end

  defp invoice_url(%{type: "sales", id: id}), do: Endpoint.url() <> Navigation.sales_invoice_show_path(id)

  defp invoice_url(%{type: "cost", id: id}), do: Endpoint.url() <> Navigation.cost_invoice_show_path(id)
end
