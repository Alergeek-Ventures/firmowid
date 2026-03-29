defmodule FirmowidWeb.Core.Router do
  use FirmowidWeb, :router
  use PhoenixAnalytics.Web, :router

  import ErrorTracker.Web.Router
  import FirmowidWeb.Infrastructure.Plugs.RedirectTrailing
  import FirmowidWeb.Infrastructure.UserAuth
  import Oban.Web.Router
  import Phoenix.LiveDashboard.Router

  alias Auth.Controllers.Google
  alias Auth.Controllers.Session
  alias Auth.Controllers.SessionApi
  alias FirmowidWeb.Infrastructure.Hooks.CurrentPath
  alias FirmowidWeb.Infrastructure.Hooks.Timezone
  alias FirmowidWeb.Infrastructure.UserAuth
  alias Invoicing.SalesInvoices.Controllers.Pdf
  alias Invoicing.SalesInvoices.Controllers.Shared
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

    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :fetch_api_user
  end

  pipeline :webhook do
    plug :accepts, ["json"]
    plug FirmowidWeb.Infrastructure.Plugs.WebhookAuth
  end

  pipeline :health do
    plug :accepts, ["json"]
  end

  pipeline :analytics_guard do
    plug FirmowidWeb.Infrastructure.Plugs.AnalyticsDashboardGuard
  end

  scope "/", FirmowidWeb do
    pipe_through :health

    get "/health", Infrastructure.Controllers.Health, :check
  end

  scope "/admin" do
    if Mix.env() == :dev do
      pipe_through [:browser, :analytics_guard]
    else
      pipe_through [:browser, :require_authenticated_user_with_organization, :require_superuser, :analytics_guard]
    end

    live_dashboard "/dashboard",
      metrics: FirmowidWeb.Core.Telemetry

    oban_dashboard("/oban", oban_name: Firmowid.Oban)

    error_tracker_dashboard("/errors")

    phoenix_analytics_dashboard("/analytics")

    forward "/flags", FunWithFlags.UI.Router, namespace: "admin/flags"

    forward "/mailbox", Plug.Swoosh.MailboxPreview
  end

  ## Webhook routes

  scope "/", FirmowidWeb do
    pipe_through :webhook

    post "/kosztowe/skrzynka", Invoicing.CostInvoices.Controllers.Inbound, :handle_webhook
  end

  ## Authentication routes

  scope "/", FirmowidWeb do
    pipe_through [:browser, :require_authenticated_user_without_organization]

    live_session :require_authenticated_user_without_organization,
      on_mount: [{UserAuth, :ensure_authenticated_without_organization}] do
      live "/organization/", Organization.Views.Index, :index
    end
  end

  scope "/", FirmowidWeb do
    pipe_through [
      :browser,
      :require_authenticated_user_with_organization
    ]

    get "/sprzedazowe/:id/pdf", Pdf, :index
    get "/sprzedazowe/:id/pobierz", Pdf, :pdf
    get "/pobierz-miesiac", Infrastructure.Controllers.FileDownload, :batch
    get "/czasosledz/projekty/csv", Csv, :salaries
    get "/czasosledz/projekty/:id/csv", Csv, :project

    live_session :admin,
      on_mount: [
        {UserAuth, :ensure_authenticated_with_organization},
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

      live "/zarzadzanie/pracownicy", Management.Views.Employees
      live "/zarzadzanie/pracownicy/:id", Management.Views.Employee, :projects
      live "/zarzadzanie/projekty", Projects, :index
      live "/zarzadzanie/projekty/archiwum", Projects, :archive
      live "/zarzadzanie/projekty/dodaj", ProjectForm, :new
      live "/zarzadzanie/projekty/:id", Management.Views.Project, :show
      live "/zarzadzanie/projekty/:id/edycja", ProjectForm, :edit

      live "/ustawienia/bank/dodaj", BankSync.Views.Create, :index

      live "/zaproszenia", Organization.Invites.Views.Index, :index

      live "/analiza", Analysis.Views.Dashboard, :index

      live "/development", Development.Views.Index, :index
    end
  end

  scope "/", FirmowidWeb do
    pipe_through [:browser, :require_authenticated_user_with_organization]
    get "/czasosledz/ewidencja/:date/pdf", HoursRecord.Controllers.Record, :pdf
    get "/czasosledz/ewidencja/:date/podglad", HoursRecord.Controllers.Record, :preview
    get "/czasosledz/ewidencja/:id", HoursRecord.Controllers.Record, :download

    live_session :require_authenticated_user_with_organization,
      on_mount: [
        {UserAuth, :ensure_authenticated_with_organization},
        {CurrentPath, :save_request_uri},
        Timezone
      ] do
      live "/czasosledz", Timetracker.Views.Index, :index

      live "/czasosledz/ewidencja", HoursRecord.Views.Index, :index

      live "/ustawienia", Settings.Views.Index, :account
      live "/ustawienia/konto", Settings.Views.Index, :account
      live "/ustawienia/bezpieczenstwo", Settings.Views.Index, :security
      live "/ustawienia/organizacja", Settings.Views.Index, :organization
      live "/ustawienia/konta-bankowe", Settings.Views.Index, :bank_accounts

      live "/ustawienia/bezpieczenstwo/potwierdz/:token", Settings.Views.Index, :confirm_email
    end
  end

  scope "/", FirmowidWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live_session :redirect_if_user_is_authenticated,
      on_mount: [
        {UserAuth, :redirect_if_user_is_authenticated},
        {CurrentPath, :save_request_uri},
        Timezone
      ] do
      live "/zarejestruj", Auth.Views.Registration, :new
      live "/zaloguj", Auth.Views.Login, :new
      live "/resetuj-haslo", Auth.Views.ForgotPassword, :new
      live "/resetuj-haslo/:token", Auth.Views.ResetPassword, :edit
    end

    post "/zaloguj", Session, :create
  end

  scope "/faktura", FirmowidWeb do
    pipe_through [:browser]

    get "/:token", Shared, :show
    get "/:token/pdf", Shared, :pdf
  end

  scope "/auth", FirmowidWeb do
    pipe_through [:browser]

    get "/google", Google, :request
    get "/google/callback", Google, :callback
    get "/google/link/:token", Google, :link
  end

  scope "/", FirmowidWeb do
    pipe_through [:browser]

    delete "/wyloguj", Session, :delete

    live_session :current_user,
      on_mount: [
        {UserAuth, :mount_current_user},
        {CurrentPath, :save_request_uri},
        Timezone
      ] do
      live "/", Landing.Views.Index
      live "/potwierdz/:token", Auth.Views.Confirmation, :edit
      live "/potwierdz", Auth.Views.ConfirmationInstructions, :new
    end
  end

  scope "/api", FirmowidWeb do
    pipe_through [:api]

    post "/login", SessionApi, :create
  end

  scope "/api", FirmowidWeb do
    pipe_through [:api, :require_authenticated_user_with_organization_api]

    post "/cost-invoices", Invoicing.CostInvoices.Controllers.Api, :create
  end
end
