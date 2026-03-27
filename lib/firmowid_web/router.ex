defmodule FirmowidWeb.Router do
  use FirmowidWeb, :router
  use PhoenixAnalytics.Web, :router

  import ErrorTracker.Web.Router
  import FirmowidWeb.Plugs.RedirectTrailing
  import FirmowidWeb.UserAuth
  import Oban.Web.Router
  import Phoenix.LiveDashboard.Router

  alias FirmowidWeb.Live.Hooks.CurrentPath
  alias FirmowidWeb.Live.Hooks.Timezone

  pipeline :browser do
    plug :accepts, ["html"]
    plug :redirect_trailing_slash
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {FirmowidWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers

    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :fetch_api_user
  end

  pipeline :webhook do
    plug :accepts, ["json"]
    plug FirmowidWeb.Plugs.WebhookAuth
  end

  pipeline :health do
    plug :accepts, ["json"]
  end

  pipeline :analytics_guard do
    plug FirmowidWeb.Plugs.AnalyticsDashboardGuard
  end

  scope "/", FirmowidWeb do
    pipe_through :health

    get "/health", HealthController, :check
  end

  scope "/admin" do
    if Mix.env() == :dev do
      pipe_through [:browser, :analytics_guard]
    else
      pipe_through [
        :browser,
        :require_authenticated_user_with_organization,
        :require_superuser,
        :analytics_guard
      ]
    end

    live_dashboard "/dashboard",
      metrics: FirmowidWeb.Telemetry

    oban_dashboard("/oban", oban_name: Firmowid.Oban)

    error_tracker_dashboard("/errors")

    phoenix_analytics_dashboard("/analytics")

    forward "/flags", FunWithFlags.UI.Router, namespace: "admin/flags"

    forward "/mailbox", Plug.Swoosh.MailboxPreview
  end

  ## Webhook routes

  scope "/", FirmowidWeb do
    pipe_through :webhook

    post "/kosztowe/skrzynka", ResendInboundController, :handle_webhook
  end

  ## Authentication routes

  scope "/", FirmowidWeb do
    pipe_through [:browser, :require_authenticated_user_without_organization]

    live_session :require_authenticated_user_without_organization,
      on_mount: [{FirmowidWeb.UserAuth, :ensure_authenticated_without_organization}] do
      live "/organization/", OrganizationLive, :index
    end
  end

  scope "/", FirmowidWeb do
    pipe_through [
      :browser,
      :require_authenticated_user_with_organization
    ]

    get "/sprzedazowe/:id/pdf", PdfController, :index
    get "/sprzedazowe/:id/pobierz", PdfController, :pdf
    get "/pobierz-miesiac", FileController, :batch
    get "/czasosledz/projekty/csv", CsvController, :salaries
    get "/czasosledz/projekty/:id/csv", CsvController, :project

    live_session :admin,
      on_mount: [
        {FirmowidWeb.UserAuth, :ensure_authenticated_with_organization},
        {CurrentPath, :save_request_uri},
        Timezone
      ] do
      live "/fakturowanie", InvoicingLive.Index, :index
      live "/kosztowe/skrzynka", CostInvoiceLive.InboxLive, :index
      live "/kosztowe/:id", CostInvoiceLive.Show, :show

      live "/sprzedazowe", SalesInvoicesLive.Creator
      live "/sprzedazowe/:id/podsumowanie", SalesInvoicesLive.Summary, :summary
      live "/sprzedazowe/:id/edytuj", SalesInvoicesLive.Edit, :edit
      live "/sprzedazowe/:id", SalesInvoicesLive.Show, :show

      live "/zarzadzanie/pracownicy", ManagementLive.Employees
      live "/zarzadzanie/pracownicy/:id", ManagementLive.Employee, :projects
      live "/zarzadzanie/projekty", ManagementLive.Projects, :index
      live "/zarzadzanie/projekty/archiwum", ManagementLive.Projects, :archive
      live "/zarzadzanie/projekty/dodaj", ManagementLive.ProjectForm, :new
      live "/zarzadzanie/projekty/:id", ManagementLive.Project, :show
      live "/zarzadzanie/projekty/:id/edycja", ManagementLive.ProjectForm, :edit

      live "/ustawienia/bank/dodaj", BankSyncLive.Create, :index

      live "/zaproszenia", OrganizationInvitesLive.Index, :index

      live "/analiza", AnalysisLive.Dashboard, :index

      live "/development", DevelopmentLive, :index
    end
  end

  scope "/", FirmowidWeb do
    pipe_through [:browser, :require_authenticated_user_with_organization]
    get "/czasosledz/ewidencja/:date/pdf", HoursRecordController, :pdf
    get "/czasosledz/ewidencja/:date/podglad", HoursRecordController, :preview
    get "/czasosledz/ewidencja/:id", HoursRecordController, :download

    live_session :require_authenticated_user_with_organization,
      on_mount: [
        {FirmowidWeb.UserAuth, :ensure_authenticated_with_organization},
        {CurrentPath, :save_request_uri},
        Timezone
      ] do
      live "/czasosledz", TimetrackerLive.Index, :index

      live "/czasosledz/ewidencja", HoursRecordLive.Index, :index

      live "/ustawienia", SettingsLive.Index, :account
      live "/ustawienia/konto", SettingsLive.Index, :account
      live "/ustawienia/bezpieczenstwo", SettingsLive.Index, :security
      live "/ustawienia/organizacja", SettingsLive.Index, :organization
      live "/ustawienia/konta-bankowe", SettingsLive.Index, :bank_accounts

      live "/ustawienia/bezpieczenstwo/potwierdz/:token", SettingsLive.Index, :confirm_email
    end
  end

  scope "/", FirmowidWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live_session :redirect_if_user_is_authenticated,
      on_mount: [
        {FirmowidWeb.UserAuth, :redirect_if_user_is_authenticated},
        {CurrentPath, :save_request_uri},
        Timezone
      ] do
      live "/zarejestruj", User.RegistrationLive, :new
      live "/zaloguj", User.LoginLive, :new
      live "/resetuj-haslo", User.ForgotPasswordLive, :new
      live "/resetuj-haslo/:token", User.ResetPasswordLive, :edit
    end

    post "/zaloguj", UserSessionController, :create
  end

  scope "/faktura", FirmowidWeb do
    pipe_through [:browser]

    get "/:token", SharedInvoiceController, :show
    get "/:token/pdf", SharedInvoiceController, :pdf
  end

  scope "/auth", FirmowidWeb do
    pipe_through [:browser]

    get "/google", GoogleAuthController, :request
    get "/google/callback", GoogleAuthController, :callback
    get "/google/link/:token", GoogleAuthController, :link
  end

  scope "/", FirmowidWeb do
    pipe_through [:browser]

    delete "/wyloguj", UserSessionController, :delete

    live_session :current_user,
      on_mount: [
        {FirmowidWeb.UserAuth, :mount_current_user},
        {CurrentPath, :save_request_uri},
        Timezone
      ] do
      live "/", LandingLive
      live "/potwierdz/:token", User.ConfirmationLive, :edit
      live "/potwierdz", User.ConfirmationInstructionsLive, :new
    end
  end

  scope "/api", FirmowidWeb do
    pipe_through [:api]

    post "/login", UserSessionApiController, :create
  end

  scope "/api", FirmowidWeb do
    pipe_through [:api, :require_authenticated_user_with_organization_api]

    post "/cost-invoices", CostInvoicesApiController, :create
  end
end
