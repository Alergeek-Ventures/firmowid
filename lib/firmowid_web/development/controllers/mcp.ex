defmodule FirmowidWeb.Development.Controllers.Mcp do
  @moduledoc """
  Development-only host for the ChatGPT MCP widgets.

  Builds the tool results ChatGPT receives for the signed-in user's organization
  (data tool output plus the signed `firmowid/app` mount) and renders a page that
  hosts the real widget document in inline and fullscreen frames.
  """
  use FirmowidWeb, :controller

  alias AshAuthentication.Oauth2Server.Jwt
  alias Firmowid.Invoicing.SalesInvoice
  alias Firmowid.Oauth2Server
  alias FirmowidMcp.Invoicing.IssueCorrection
  alias FirmowidMcp.Invoicing.IssueInvoice
  alias FirmowidMcp.Runtime
  alias FirmowidMcp.Utilities.AccessToken
  alias FirmowidMcp.Widgets

  require Ash.Query

  plug :put_view, html: FirmowidWeb.Development.Components.McpPage

  # Seeded Bytecraft bank account, as ChatGPT would repeat it from the conversation.
  @seller_account_number "PL61105000997603123456789012"
  @mount_lifetime 900

  @doc "Renders every available scenario with freshly signed widget mounts."
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, _params) do
    scope = conn.assigns.ash_scope

    {:ok, access_token, claims} =
      Jwt.mint(Oauth2Server,
        sub: scope.actor.id,
        client_id: "development",
        scope: "mcp",
        tenant: scope.tenant,
        ttl: @mount_lifetime
      )

    AccessToken.store!(access_token, scope.actor)

    oauth_conn =
      conn
      |> assign(:oauth_claims, claims)
      |> Ash.PlugHelpers.set_actor(scope.actor)
      |> Ash.PlugHelpers.set_tenant(scope.tenant)

    scenarios =
      scope
      |> scenarios()
      |> Enum.map(&Map.put(&1, :result, tool_result(oauth_conn, scope, &1)))

    render(conn, :index,
      layout: false,
      page_title: "Widżety MCP",
      scenarios: scenarios,
      host:
        Jason.encode!(%{
          document: Runtime.document(),
          scenarios: Map.new(scenarios, &{&1.id, Map.take(&1, [:arguments, :result])})
        })
    )
  end

  defp scenarios(scope) do
    Enum.reject(
      [draft_scenario(scope), new_invoice_scenario(), correction_scenario(scope)],
      &is_nil/1
    )
  end

  defp draft_scenario(scope) do
    SalesInvoice
    |> Ash.Query.filter(is_nil(invoice_number))
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.Query.limit(1)
    |> Ash.read_one!(scope: scope)
    |> case do
      nil ->
        nil

      draft ->
        %{
          id: "draft",
          title: "Wystawienie zapisanego szkicu (#{draft.buyer_display_name})",
          app: IssueInvoice,
          arguments: %{"input" => %{"invoice" => %{}, "invoice_id" => draft.id}}
        }
    end
  end

  defp new_invoice_scenario do
    today = Date.utc_today()

    %{
      id: "new",
      title: "Nowa faktura z danych od ChatGPT",
      app: IssueInvoice,
      arguments: %{
        "input" => %{
          "invoice" => %{
            "buyer_type" => "company",
            "buyer_id" => "9876543210",
            "buyer_full_name" => "Północny Kod spółka z ograniczoną odpowiedzialnością",
            "buyer_address" => "ul. Warmińska 18/4, 80-857 Gdańsk",
            "buyer_country" => "PL",
            "currency" => "PLN",
            "payment_method" => "transfer",
            "seller_account_number" => @seller_account_number,
            "sale_date" => Date.to_iso8601(today),
            "due_date" => today |> Date.add(14) |> Date.to_iso8601(),
            "sales_invoice_items" => [
              %{
                "name" => "Konsultacje programistyczne",
                "quantity" => "10",
                "unit" => "h",
                "unit_price" => "200",
                "vat_rate" => "23"
              }
            ]
          }
        }
      }
    }
  end

  defp correction_scenario(scope) do
    SalesInvoice
    |> Ash.Query.filter(not is_nil(invoice_number) and ksef_invoice_kind == :vat and invoice_type == :poland)
    |> Ash.Query.sort(issue_date: :desc)
    |> Ash.Query.limit(1)
    |> Ash.Query.load(:sales_invoice_items)
    |> Ash.read_one!(scope: scope)
    |> case do
      nil ->
        nil

      original ->
        %{
          id: "correction",
          title: "Korekta faktury #{original.invoice_number} (rabat 50%)",
          app: IssueCorrection,
          arguments: %{
            "input" => %{
              "original_invoice_id" => original.id,
              "invoice" => %{
                "correction_reason" => "Rabat posprzedażowy",
                "sales_invoice_items" => Enum.map(original.sales_invoice_items, &discounted_item/1)
              }
            }
          }
        }
    end
  end

  defp discounted_item(item) do
    %{
      "name" => item.name,
      "quantity" => Decimal.to_string(item.quantity),
      "unit" => item.unit,
      "unit_price" => item.unit_price |> Decimal.div(2) |> Decimal.to_string(),
      "vat_rate" => item.vat_rate
    }
  end

  # Mirrors the AshAi tools/call result and the decoration added by FirmowidMcp.Router.
  defp tool_result(conn, scope, %{app: app, arguments: arguments}) do
    case Widgets.execute(app, arguments, scope) do
      {:ok, data, _raw} ->
        %{
          "isError" => false,
          "content" => [%{"type" => "text", "text" => Jason.encode!(data)}],
          "structuredContent" => data,
          "_meta" => %{"firmowid/app" => Runtime.mount_metadata(conn, app, arguments)}
        }

      {:error, reason} ->
        %{"isError" => true, "content" => [%{"type" => "text", "text" => to_string(reason)}]}
    end
  end
end
