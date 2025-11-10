defmodule FirmowidWeb.Router do
  use FirmowidWeb, :router

  import FirmowidWeb.RedirectTrailing
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
    plug FirmowidWeb.WebhookAuth
  end

  scope "/admin" do
    if Mix.env() == :dev do
      pipe_through [:browser]
    else
      pipe_through [:browser, :require_authenticated_user_with_organization, :require_superuser]
    end

    live_dashboard "/dashboard",
      metrics: FirmowidWeb.Telemetry

    oban_dashboard("/oban", oban_name: Firmowid.Oban)

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
      :require_authenticated_user_with_organization,
      :redirect_employees_to_timetracker
    ]

    get "/sprzedazowe/:id/pdf", PdfController, :index
    get "/sprzedazowe/:id/pobierz", PdfController, :pdf
    get "/pobierz-miesiac", FileController, :batch

    live_session :admin,
      on_mount: [
        {FirmowidWeb.UserAuth, :ensure_authenticated_with_organization},
        {CurrentPath, :save_request_uri},
        Timezone
      ] do
      live "/", InvoicingLive.Index, :index
      live "/kosztowe/skrzynka", CostInvoiceLive.InboxLive, :index
      live "/kosztowe/:id", CostInvoiceLive.Show, :show

      live "/sprzedazowe", SalesInvoicesLive.Index, :index
      live "/sprzedazowe/kreator", SalesInvoicesLive.Create, :index
      live "/sprzedazowe/:id", SalesInvoicesLive.Show, :show
      live "/sprzedazowe/:id/edycja", SalesInvoicesLive.Index, :index

      live "/czasosledz/projekty", Project.Index, :projects
      live "/czasosledz/projekty/dodaj", Project.ProjectNew, :new
      live "/czasosledz/projekty/:id", Project.Index, :projects
      live "/czasosledz/archiwum", Project.Index, :archive
      live "/czasosledz/archiwum/:id", Project.Index, :archive

      live "/zarzadzanie/pracownicy", ManagementLive.Employees
      # TODO: /:id page
      live "/zarzadzanie/pracownicy/:id", ManagementLive.Employees
      live "/zarzadzanie/projekty", ManagementLive.Projects
      live "/zarzadzanie/kontrahenci", ManagementLive.Clients

      live "/ustawienia/bank", BankSyncLive.Index, :index
      live "/ustawienia/bank/dodaj", BankSyncLive.Create, :index

      live "/zaproszenia", OrganizationInvitesLive.Index, :index

      live "/analiza", AnalysisLive.Dashboard, :index
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
