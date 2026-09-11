defmodule FirmowidWeb.Core.Router do
  use FirmowidWeb, :router
  use AshAuthentication.Phoenix.Router
  use AshAuthentication.Phoenix.Oauth2Server.Router

  import FirmowidWeb.Infrastructure.Plugs.RedirectTrailing
  import FirmowidWeb.Infrastructure.UserAuth
  import Oban.Web.Router
  import Phoenix.LiveDashboard.Router

  alias AshAuthentication.Phoenix.LiveSession
  alias Auth.Controllers.AuthController
  alias FirmowidWeb.Core.Telemetry
  alias FirmowidWeb.Infrastructure.Hooks.CurrentPath
  alias FirmowidWeb.Infrastructure.Hooks.FeatureFlags
  alias FirmowidWeb.Infrastructure.Hooks.RedirectAuthenticated
  alias FirmowidWeb.Infrastructure.Hooks.RequireAdmin
  alias FirmowidWeb.Infrastructure.Hooks.RequireNoOrganization
  alias FirmowidWeb.Infrastructure.Hooks.RequireOrganization
  alias FirmowidWeb.Infrastructure.Hooks.RequireSuperuser
  alias FirmowidWeb.Infrastructure.Hooks.Timezone
  alias Invoicing.CostInvoices.Controllers.Pdf, as: CostInvoicePdf
  alias Invoicing.SalesInvoices.Controllers.Pdf
  alias Invoicing.SalesInvoices.Controllers.Shared
  alias Management.Controllers.EmploymentContract
  alias Management.Views.Counterparties
  alias Management.Views.CounterpartyForm
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

    plug :sign_in_with_remember_me
    plug :load_from_session
    plug :restore_live_socket_id
    plug :set_actor, :user
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :load_from_bearer
  end

  pipeline :oauth_api do
    plug :accepts, ["json"]
  end

  pipeline :oauth_loopback_fix do
    plug FirmowidWeb.Mcp.Utilities.RewriteLoopbackRedirectUri
  end

  pipeline :webhook do
    plug :accepts, ["json"]
    plug FirmowidWeb.Infrastructure.Plugs.WebhookAuth
  end

  pipeline :health do
    plug :accepts, ["json"]
  end

  pipeline :mcp do
    plug AshAuthentication.Phoenix.Oauth2Server.BearerPlug,
      oauth2_server: Firmowid.Oauth2Server,
      required?: true,
      scope: "mcp"

    plug AshAuthentication.Phoenix.Oauth2Server.RequireScopePlug,
      oauth2_server: Firmowid.Oauth2Server,
      scope: "mcp"

    plug FirmowidWeb.Mcp.Utilities.Authenticate
  end

  scope "/", FirmowidWeb do
    pipe_through :health

    get "/health", Infrastructure.Controllers.Health, :check
  end

  ## Authentication routes (Ash Authentication)
  # Consent must be registered before `forward "/oauth"` below. Phoenix
  # first-match-wins, and the protocol router would 404 `/oauth/authorize`.

  scope "/", FirmowidWeb do
    pipe_through :browser

    auth_routes(AuthController, Firmowid.Ash.Core.User, path: "/auth")
    delete "/wyloguj", AuthController, :sign_out
  end

  scope "/", FirmowidWeb do
    pipe_through [:browser, :oauth_loopback_fix]

    oauth2_server_consent_routes(
      oauth2_server: Firmowid.Oauth2Server,
      consent_view: FirmowidWeb.Mcp.Components.Consent
    )
  end

  scope "/" do
    pipe_through [:oauth_api, :oauth_loopback_fix]
    oauth2_server_protocol_routes(oauth2_server: Firmowid.Oauth2Server)
  end

  ## MCP resource server

  scope "/mcp" do
    pipe_through :mcp

    forward "/", AshAi.Mcp.Router,
      tools: [
        :list_sessions,
        :get_current_session,
        :stop_current_session,
        :start_session,
        :edit_session,
        :list_leave_requests,
        :create_leave_request,
        :update_profile,
        :get_shared_birthday,
        :list_projects
      ],
      otp_app: :firmowid
  end

  scope "/admin" do
    if Mix.env() == :dev do
      pipe_through [:browser]

      live_dashboard "/dashboard",
        metrics: Telemetry

      oban_dashboard("/oban", oban_name: Oban)
    else
      pipe_through [:browser, :require_authenticated_user_with_organization, :require_superuser]

      live_dashboard "/dashboard",
        metrics: Telemetry,
        on_mount: [
          LiveSession,
          {RequireOrganization, :default},
          {RequireSuperuser, :default}
        ]

      oban_dashboard("/oban",
        oban_name: Oban,
        on_mount: [
          LiveSession,
          {RequireOrganization, :default},
          {RequireSuperuser, :default}
        ]
      )
    end

    forward "/mailbox", Plug.Swoosh.MailboxPreview

    ash_authentication_live_session :admin,
      on_mount: [
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

  ## Webhook routes

  scope "/", FirmowidWeb do
    pipe_through :webhook

    post "/kosztowe/skrzynka", Invoicing.CostInvoices.Controllers.Inbound, :handle_webhook
  end

  # Canonical policy: Google accounts auto-link only when provider email is verified
  # and matches an existing user email (enforced in User.register_with_google).
  # TODO: Make this auto-link policy opt-in per organization.
  # TODO: Add explicit UX flow for linking different-email Google and password accounts.

  ## Organization onboarding (authenticated, no org)

  scope "/", FirmowidWeb do
    pipe_through [:browser, :require_authenticated_user_without_organization]

    ash_authentication_live_session :without_org,
      on_mount: [{RequireNoOrganization, :default}, {FeatureFlags, :default}] do
      live "/organizacja", Organization.Views.Index, :index
    end
  end

  scope "/", FirmowidWeb do
    pipe_through [
      :browser,
      :require_authenticated_user_with_organization
    ]

    get "/kosztowe/:id/pobierz", CostInvoicePdf, :pdf
    get "/sprzedazowe/:id/pdf", Pdf, :index
    get "/sprzedazowe/:id/pobierz", Pdf, :pdf
    get "/pobierz-miesiac", Infrastructure.Controllers.FileDownload, :batch
    get "/czasosledz/projekty/csv", Csv, :salaries
    get "/czasosledz/projekty/:id/csv", Csv, :project
    get "/zarzadzanie/umowy/:id", EmploymentContract, :download

    ash_authentication_live_session :with_org,
      on_mount: [
        {RequireOrganization, :default},
        {FeatureFlags, :default},
        {CurrentPath, :save_request_uri},
        Timezone
      ] do
      live "/fakturowanie", Invoicing.Views.Index, :index
      live "/kosztowe/skrzynka", Invoicing.CostInvoices.Views.Inbox, :index
      live "/kosztowe/:id", Invoicing.CostInvoices.Views.Show, :show

      live "/sprzedazowe", Invoicing.SalesInvoices.Views.Creator
      live "/sprzedazowe/:id/podsumowanie", Invoicing.SalesInvoices.Views.Summary, :summary
      live "/sprzedazowe/:id/edytuj", Invoicing.SalesInvoices.Views.Edit, :edit
      live "/sprzedazowe/:id", Invoicing.SalesInvoices.Views.Show, :show
      live "/transakcje/:id", Invoicing.Transactions.Views.Show, :show

      live "/ustawienia/bank/dodaj", BankSync.Views.Create, :index

      live "/zaproszenia", Organization.Invites.Views.Index, :index

      live "/analiza", Analysis.Views.Dashboard, :index

      if Mix.env() == :dev do
        live "/development", Development.Views.Index, :index
      end
    end

    ash_authentication_live_session :with_org_management,
      on_mount: [
        {RequireOrganization, :default},
        {RequireAdmin, :default},
        {FeatureFlags, :default},
        {CurrentPath, :save_request_uri},
        Timezone
      ] do
      live "/zarzadzanie/pracownicy", Employees, :index
      live "/zarzadzanie/pracownicy/archiwum", Employees, :archive
      live "/zarzadzanie/pracownicy/:id", Employee, :projects
      live "/zarzadzanie/pracownicy/:id/profil", Employee, :profile
      live "/zarzadzanie/pracownicy/:id/dokumenty", Employee, :documents
      live "/zarzadzanie/pracownicy/:id/urlopy", Employee, :leaves
      live "/zarzadzanie/pracownicy/:id/delegacje", Employee, :delegations

      live "/zarzadzanie/pracownicy/:id/delegacje/:delegation_id",
           Management.Views.Delegation,
           :show

      live "/zarzadzanie/kontrahenci", Counterparties, :index
      live "/zarzadzanie/kontrahenci/archiwum", Counterparties, :archive
      live "/zarzadzanie/kontrahenci/dodaj", CounterpartyForm, :new
      live "/zarzadzanie/kontrahenci/:id", Management.Views.Counterparty, :show
      live "/zarzadzanie/kontrahenci/:id/edycja", CounterpartyForm, :edit
      live "/zarzadzanie/projekty", Projects, :index
      live "/zarzadzanie/projekty/archiwum", Projects, :archive
      live "/zarzadzanie/projekty/dodaj", ProjectForm, :new
      live "/zarzadzanie/projekty/:id", Management.Views.Project, :show
      live "/zarzadzanie/projekty/:id/edycja", ProjectForm, :edit
    end
  end

  scope "/", FirmowidWeb do
    pipe_through [:browser, :require_authenticated_user_with_organization]
    get "/czasosledz/ewidencja/:date/pdf", HoursRecord.Controllers.Record, :pdf
    get "/czasosledz/ewidencja/:date/podglad", HoursRecord.Controllers.Record, :preview
    get "/czasosledz/ewidencja/:id", HoursRecord.Controllers.Record, :download

    get "/zarzadzanie/pracownicy/:employee_id/delegacje/:id/pdf",
        Management.Controllers.DelegationCommand,
        :pdf

    ash_authentication_live_session :with_org_extended,
      on_mount: [
        {RequireOrganization, :default},
        {FeatureFlags, :default},
        {CurrentPath, :save_request_uri},
        Timezone
      ] do
      live "/czasosledz", Timetracker.Views.Index, :index

      live "/czasosledz/ewidencja", HoursRecord.Views.Index, :index

      live "/ustawienia", Settings.Views.Index, :index
      live "/ustawienia/:section", Settings.Views.Index, :index
      live "/delegacje/dodaj", Delegations.Views.DelegationForm, :new
      live "/delegacje/:id", Delegations.Views.Delegation, :show
    end
  end

  scope "/", FirmowidWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    ash_authentication_live_session :guest,
      on_mount: [
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
    pipe_through [:browser]

    get "/index.html", Infrastructure.Controllers.LegacyIndex, :index
    get "/sitemap.xml", Infrastructure.Controllers.Sitemap, :index

    ash_authentication_live_session :public,
      on_mount: [
        {CurrentPath, :save_request_uri},
        Timezone
      ] do
      live "/abonament-wygasl", Auth.Views.ExpiredSubscription
      live "/konto-wylaczone", Auth.Views.DisabledAccount
      live "/potwierdz-email/:token", Auth.Views.ConfirmEmail, :edit
      live "/", Landing.Views.Index
      live "/polityka-prywatnosci", Landing.Views.PrivacyPolicy
      live "/regulamin", Landing.Views.TermsOfService
    end
  end
end
