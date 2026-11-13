defmodule FirmowidWeb.Core.Router do
  use FirmowidWeb, :router
  use AshAuthentication.Phoenix.Router
  use AshAuthentication.Phoenix.Oauth2Server.Router

  import FirmowidWeb.Infrastructure.Plugs.RedirectTrailing
  import FirmowidWeb.Infrastructure.UserAuth
  import Oban.Web.Router
  import Phoenix.LiveDashboard.Router

  alias AshAuthentication.Phoenix.LiveSession
  alias AshAuthentication.Phoenix.Oauth2Server.BearerPlug
  alias AshAuthentication.Phoenix.Oauth2Server.RequireScopePlug
  alias Auth.Controllers.AuthController
  alias Delegations.Views.DelegationForm
  alias FirmowidMcp.Utilities.Authenticate
  alias FirmowidWeb.Core.Telemetry
  alias FirmowidWeb.Inbox.Hooks.LiveQueue
  alias FirmowidWeb.Infrastructure.Hooks.CurrentPath
  alias FirmowidWeb.Infrastructure.Hooks.FeatureFlags
  alias FirmowidWeb.Infrastructure.Hooks.Locale
  alias FirmowidWeb.Infrastructure.Hooks.RedirectAuthenticated
  alias FirmowidWeb.Infrastructure.Hooks.RequireOrganization
  alias FirmowidWeb.Infrastructure.Hooks.RequireSuperuser
  alias FirmowidWeb.Infrastructure.Hooks.RequireUser
  alias FirmowidWeb.Infrastructure.Hooks.Timezone
  alias Infrastructure.Controllers.AgentDiscovery
  alias Invoicing.CostInvoices.Controllers.Pdf, as: CostInvoicePdf
  alias Invoicing.SalesInvoices.Controllers.Pdf
  alias Invoicing.SalesInvoices.Controllers.Shared
  alias Landing.Views.Guides
  alias Management.Controllers.EmploymentContract
  alias Management.Views.Counterparties
  alias Management.Views.CounterpartyForm
  alias Management.Views.CounterpartySuggestions
  alias Management.Views.Employee
  alias Management.Views.Employees
  alias Management.Views.ProjectForm
  alias Management.Views.Projects
  alias Timetracker.Controllers.Csv

  pipeline :browser do
    plug :accepts, ["html"]
    plug :redirect_trailing_slash
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {FirmowidWeb.Infrastructure.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug FirmowidWeb.Infrastructure.Plugs.ContentSecurityPolicy

    plug :sign_in_with_remember_me
    plug :load_from_session
    plug :restore_live_socket_id
    plug :set_actor, :user
    plug FirmowidWeb.Infrastructure.Plugs.Locale
  end

  pipeline :api do
    plug BearerPlug,
      oauth2_server: Firmowid.Oauth2Server,
      required?: true,
      scope: "api"

    plug RequireScopePlug,
      oauth2_server: Firmowid.Oauth2Server,
      scope: "api"

    plug Authenticate
  end

  pipeline :oauth_api do
    plug :accepts, ["json"]
    plug FirmowidMcp.Utilities.PublicClientAuthentication
    plug FirmowidMcp.Utilities.TokenOrganization
  end

  pipeline :oauth_request_normalization do
    plug FirmowidMcp.Utilities.NormalizeRedirectUri
    plug FirmowidMcp.Utilities.DefaultAuthorizationScope
  end

  pipeline :oauth_consent do
    plug FirmowidWeb.Auth.Utilities.ConsentOrganization
  end

  pipeline :google_remember_me do
    plug FirmowidWeb.Auth.Utilities.GoogleRememberMe
  end

  pipeline :health do
    plug :accepts, ["json"]
  end

  pipeline :mcp do
    plug BearerPlug,
      oauth2_server: Firmowid.Oauth2Server,
      required?: true,
      scope: "mcp"

    plug RequireScopePlug,
      oauth2_server: Firmowid.Oauth2Server,
      scope: "mcp"

    plug Authenticate
  end

  scope "/", FirmowidWeb do
    pipe_through :health

    get "/health", Infrastructure.Controllers.Health, :check
  end

  pipeline :agent_discovery_links do
    plug :put_agent_discovery_links
  end

  # Runs before `:browser`, whose `accepts ["html"]` answers 406 to markdown requests.
  pipeline :markdown_home do
    plug :serve_markdown_home
  end

  scope "/", FirmowidWeb do
    get "/.well-known/openai-apps-challenge", Infrastructure.Controllers.OpenaiChallenge, :show
    get "/.well-known/ai-catalog.json", AgentDiscovery, :ai_catalog
    get "/.well-known/api-catalog", AgentDiscovery, :api_catalog
    get "/.well-known/agent-skills/index.json", AgentDiscovery, :agent_skills
    get "/.well-known/agent-skills/firmowid-mcp/SKILL.md", AgentDiscovery, :agent_skill
    # Pre-final SEP-2127 location, still probed by isitagentready.com.
    get "/.well-known/mcp/server-card.json", AgentDiscovery, :server_card
    options "/.well-known/mcp/server-card.json", AgentDiscovery, :preflight
    # Must precede the bearer-protected `/mcp` forward below.
    get "/mcp/server-card", AgentDiscovery, :server_card
    options "/mcp/server-card", AgentDiscovery, :preflight
  end

  ## Authentication routes (Ash Authentication)
  # Consent must be registered before `forward "/oauth"` below. Phoenix
  # first-match-wins, and the protocol router would 404 `/oauth/authorize`.

  scope "/", FirmowidWeb do
    pipe_through [:browser, :google_remember_me]

    auth_routes(AuthController, Firmowid.Core.User, path: "/auth")
  end

  scope "/", FirmowidWeb do
    pipe_through :browser

    delete "/wyloguj", AuthController, :sign_out
    post "/zaloguj-ponownie", AuthController, :sign_in_again
    delete "/admin/impersonacja", Admin.Controllers.Impersonation, :delete
    post "/jezyk", Infrastructure.Controllers.Locale, :update
  end

  scope "/", FirmowidWeb do
    pipe_through [:browser, :oauth_request_normalization, :oauth_consent]

    oauth2_server_consent_routes(
      oauth2_server: Firmowid.Oauth2Server,
      consent_view: FirmowidWeb.Auth.Components.McpConsent
    )
  end

  scope "/" do
    pipe_through [:oauth_api, :oauth_request_normalization]

    forward "/oauth", FirmowidMcp.Utilities.RefreshTokenTransaction, oauth2_server: Firmowid.Oauth2Server

    forward "/.well-known", AshAuthentication.Phoenix.Oauth2Server.ProtocolRouter,
      oauth2_server: Firmowid.Oauth2Server,
      well_known?: true
  end

  scope "/api/timetracker" do
    pipe_through :api

    forward "/", FirmowidWeb.Timetracker.Api
  end

  ## MCP resource server

  scope "/mcp" do
    pipe_through :mcp

    forward "/", FirmowidMcp.Router,
      tools: Firmowid.AiTools.mcp(),
      mcp_resources: [:ksef_connection, :issue_invoice, :issue_correction]
  end

  scope "/admin" do
    pipe_through [:browser, :require_authenticated_user_with_organization, :require_superuser]

    post "/rozliczenia/:org_id/impersonacja", FirmowidWeb.Admin.Controllers.Impersonation, :create

    if Mix.env() != :dev do
      live_dashboard "/dashboard",
        metrics: Telemetry,
        csp_nonce_assign_key: :csp_nonce,
        on_mount: [
          LiveSession,
          {RequireOrganization, :default},
          {RequireSuperuser, :default}
        ]

      oban_dashboard("/oban",
        oban_name: Oban,
        csp_nonce_assign_key: :csp_nonce,
        on_mount: [
          LiveSession,
          {RequireOrganization, :default},
          {RequireSuperuser, :default}
        ]
      )
    end

    ash_authentication_live_session :admin,
      on_mount: [
        Locale,
        {RequireOrganization, :default},
        {RequireSuperuser, :default},
        {FeatureFlags, :default},
        {CurrentPath, :save_request_uri},
        Timezone
      ] do
      live "/rozliczenia", FirmowidWeb.Admin.Views.Organizations, :index
      live "/rozliczenia/:org_id", FirmowidWeb.Admin.Views.Settlement, :show
    end
  end

  # Development tools, open without signing in.
  if Mix.env() == :dev do
    scope "/admin" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: Telemetry, csp_nonce_assign_key: :csp_nonce
      oban_dashboard("/oban", oban_name: Oban, csp_nonce_assign_key: :csp_nonce)

      forward "/mailbox", Plug.Swoosh.MailboxPreview, csp_nonce_assign_key: %{script: :csp_nonce, style: :csp_nonce}
    end
  end

  # Canonical policy: Google accounts auto-link only when provider email is verified
  # and matches an existing user email (enforced in User.register_with_google).
  # TODO: Make this auto-link policy opt-in per organization.
  # TODO: Add explicit UX flow for linking different-email Google and password accounts.

  ## Organization onboarding (authenticated, with or without an organization)

  scope "/", FirmowidWeb do
    pipe_through [:browser, :require_authenticated_user_for_onboarding]

    ash_authentication_live_session :onboarding,
      on_mount: [
        Locale,
        {RequireUser, :default},
        {FeatureFlags, :default},
        {CurrentPath, :save_request_uri}
      ] do
      live "/organizacja", Organization.Views.Index, :index
      live "/organizacja/formularz", Organization.Views.LegacyForm, :index
    end
  end

  scope "/", FirmowidWeb do
    pipe_through [
      :browser,
      :require_authenticated_user_with_organization
    ]

    post "/organizacja/przelacz", Organization.Controllers.Switch, :switch
    get "/kosztowe/:id/pobierz", CostInvoicePdf, :pdf
    get "/sprzedazowe/:id/pdf", Pdf, :index
    get "/sprzedazowe/:id/pobierz", Pdf, :pdf
    get "/pobierz-miesiac", Infrastructure.Controllers.FileDownload, :batch
    get "/czasosledz/projekty/csv", Csv, :salaries
    get "/czasosledz/projekty/:id/csv", Csv, :project
    get "/zarzadzanie/umowy/:id", EmploymentContract, :download
    get "/czasosledz/ewidencja/:date/pdf", HoursRecord.Controllers.Record, :pdf
    get "/czasosledz/ewidencja/:date/podglad", HoursRecord.Controllers.Record, :preview
    get "/czasosledz/ewidencja/:id", HoursRecord.Controllers.Record, :download
    get "/delegacje/:reference/rozliczenie/pobierz", Delegations.Controllers.Settlement, :download

    get "/zarzadzanie/pracownicy/:employee_id/delegacje/:reference/pdf",
        Management.Controllers.DelegationOrder,
        :pdf

    if Mix.env() == :dev do
      get "/development/mcp", Development.Controllers.Mcp, :index
    end

    ash_authentication_live_session :with_org,
      on_mount: [
        Locale,
        {RequireOrganization, :default},
        {FeatureFlags, :default},
        {RequireOrganization, :first_steps},
        {RequireOrganization, :plan_limit},
        {CurrentPath, :save_request_uri},
        Timezone,
        {LiveQueue, :default}
      ] do
      live "/skrzynka", Inbox.Views.Index, :index
      live "/asystent", Assistant.Views.Index, :index
      live "/fakturowanie", Invoicing.Views.Index, :index
      live "/kosztowe/:id", Invoicing.CostInvoices.Views.Show, :show

      live "/sprzedazowe", Invoicing.SalesInvoices.Views.Creator
      live "/sprzedazowe/:id/podsumowanie", Invoicing.SalesInvoices.Views.Summary, :summary
      live "/sprzedazowe/:id/edytuj", Invoicing.SalesInvoices.Views.Edit, :edit
      live "/sprzedazowe/:id", Invoicing.SalesInvoices.Views.Show, :show
      live "/transakcje/:id", Invoicing.Transactions.Views.Show, :show

      live "/zaproszenia", Organization.Invites.Views.Index, :index

      live "/analiza", Analysis.Views.Dashboard, :index

      live "/czasosledz", Timetracker.Views.Index, :index
      live "/czasosledz/ewidencja", HoursRecord.Views.Index, :index
      live "/ustawienia", Settings.Views.Index, :index
      live "/ustawienia/:section", Settings.Views.Index, :index
      live "/delegacje/dodaj", DelegationForm, :new
      live "/delegacje/:reference/edycja", DelegationForm, :edit
      live "/delegacje/:reference", Delegations.Views.Delegation, :show

      # Admin-only pages require the admin themselves (see RequireAdmin).
      live "/pierwsze-kroki", Organization.Views.FirstSteps, :index
      live "/limit-planu", Billing.Views.PlanLimit, :index
      live "/ustawienia/bank/dodaj", BankSync.Views.Create, :index
      live "/zarzadzanie/pracownicy", Employees, :index
      live "/zarzadzanie/pracownicy/archiwum", Employees, :archive
      live "/zarzadzanie/pracownicy/:id", Employee, :projects
      live "/zarzadzanie/pracownicy/:id/profil", Employee, :profile
      live "/zarzadzanie/pracownicy/:id/dokumenty", Employee, :documents
      live "/zarzadzanie/pracownicy/:id/urlopy", Employee, :leaves
      live "/zarzadzanie/pracownicy/:id/delegacje", Employee, :delegations

      live "/zarzadzanie/pracownicy/:id/delegacje/:reference",
           Management.Views.Delegation,
           :show

      live "/zarzadzanie/pracownicy/:id/delegacje/:reference/edycja",
           DelegationForm,
           :edit

      live "/zarzadzanie/kontrahenci", Counterparties, :index
      live "/zarzadzanie/kontrahenci/archiwum", Counterparties, :archive
      live "/zarzadzanie/kontrahenci/do-przejrzenia", CounterpartySuggestions, :index
      live "/zarzadzanie/kontrahenci/dodaj", CounterpartyForm, :new
      live "/zarzadzanie/kontrahenci/:id", Management.Views.Counterparty, :show
      live "/zarzadzanie/kontrahenci/:id/edycja", CounterpartyForm, :edit
      live "/zarzadzanie/projekty", Projects, :index
      live "/zarzadzanie/projekty/archiwum", Projects, :archive
      live "/zarzadzanie/projekty/dodaj", ProjectForm, :new
      live "/zarzadzanie/projekty/:id", Management.Views.Project, :show
      live "/zarzadzanie/projekty/:id/edycja", ProjectForm, :edit

      if Mix.env() == :dev do
        live "/development", Development.Views.Index, :index
        live "/development/design-system", Development.Views.DesignSystem, :index
        live "/development/skrzynka", Development.Views.InboxScenarios, :index
      end
    end
  end

  scope "/", FirmowidWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    ash_authentication_live_session :guest,
      on_mount: [
        Locale,
        {RedirectAuthenticated, :default},
        {CurrentPath, :save_request_uri},
        Timezone
      ] do
      live "/zarejestruj", Auth.Views.Registration, :new
      live "/zaloguj", Auth.Views.Login, :new
      live "/resetuj-haslo", Auth.Views.ForgotPassword, :new
      live "/resetuj-haslo/:token", Auth.Views.ResetPassword, :edit
    end
  end

  scope "/faktura", FirmowidWeb do
    pipe_through [:browser]

    get "/:token", Shared, :show
    get "/:token/pdf", Shared, :pdf
  end

  scope "/", FirmowidWeb do
    pipe_through [:markdown_home, :browser, :agent_discovery_links]

    get "/index.html", Infrastructure.Controllers.LegacyIndex, :index
    get "/sitemap.xml", Infrastructure.Controllers.Sitemap, :index

    ash_authentication_live_session :public,
      on_mount: [
        Locale,
        {CurrentPath, :save_request_uri},
        Timezone
      ] do
      live "/abonament-wygasl", Auth.Views.ExpiredSubscription
      live "/konto-wylaczone", Auth.Views.DisabledAccount
      live "/potwierdz-email/:token", Auth.Views.ConfirmEmail, :edit
      live "/", Landing.Views.Index, :home
      live "/cennik", Landing.Views.Index, :pricing
      live "/funkcje", Landing.Views.Index, :features
      live "/faq", Landing.Views.Index, :faq
      live "/open-source", Landing.Views.Index, :open_source
      live "/poradnik", Guides, :index
      live "/poradnik/:slug", Guides, :show
      live "/polityka-prywatnosci", Landing.Views.PrivacyPolicy
      live "/regulamin", Landing.Views.TermsOfService
    end
  end

  defp put_agent_discovery_links(conn, _opts),
    do: put_resp_header(conn, "link", FirmowidWeb.Infrastructure.Controllers.AgentDiscovery.link_header())

  defp serve_markdown_home(%Plug.Conn{request_path: "/"} = conn, _opts) do
    if conn |> get_req_header("accept") |> Enum.any?(&String.contains?(&1, "text/markdown")),
      do: conn |> FirmowidWeb.Infrastructure.Controllers.AgentDiscovery.markdown_home(%{}) |> halt(),
      else: conn
  end

  defp serve_markdown_home(conn, _opts), do: conn
end
