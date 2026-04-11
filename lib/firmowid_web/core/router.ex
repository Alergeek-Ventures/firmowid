defmodule FirmowidWeb.Core.Router do
  use FirmowidWeb, :router
  use AshAuthentication.Phoenix.Router

  import FirmowidWeb.Infrastructure.Plugs.RedirectTrailing
  import FirmowidWeb.Infrastructure.UserAuth
  import Oban.Web.Router
  import Phoenix.LiveDashboard.Router

  alias Auth.Controllers.AuthController
  alias FirmowidWeb.Infrastructure.Hooks.CurrentPath
  alias FirmowidWeb.Infrastructure.Hooks.RedirectAuthenticated
  alias FirmowidWeb.Infrastructure.Hooks.RequireAdmin
  alias FirmowidWeb.Infrastructure.Hooks.RequireNoOrganization
  alias FirmowidWeb.Infrastructure.Hooks.RequireOrganization
  alias FirmowidWeb.Infrastructure.Hooks.Timezone
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

    plug :sign_in_with_remember_me
    plug :load_from_session
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :load_from_bearer
  end

  pipeline :webhook do
    plug :accepts, ["json"]
    plug FirmowidWeb.Infrastructure.Plugs.WebhookAuth
  end

  pipeline :health do
    plug :accepts, ["json"]
  end

  scope "/", FirmowidWeb do
    pipe_through :health

    get "/health", Infrastructure.Controllers.Health, :check
  end

  scope "/admin" do
    if Mix.env() == :dev do
      pipe_through [:browser]
    else
      pipe_through [:browser, :require_authenticated_user_with_organization, :require_superuser]
    end

    live_dashboard "/dashboard",
      metrics: FirmowidWeb.Core.Telemetry

    oban_dashboard("/oban", oban_name: Oban)

    forward "/flags", FunWithFlags.UI.Router, namespace: "admin/flags"

    forward "/mailbox", Plug.Swoosh.MailboxPreview
  end

  ## Webhook routes

  scope "/", FirmowidWeb do
    pipe_through :webhook

    post "/kosztowe/skrzynka", Invoicing.CostInvoices.Controllers.Inbound, :handle_webhook
  end

  ## Authentication routes (Ash Authentication)

  scope "/", FirmowidWeb do
    pipe_through :browser

    auth_routes(AuthController, Firmowid.Ash.Core.User, path: "/auth")
    sign_out_route(AuthController)
  end

  # Canonical policy: Google accounts auto-link only when provider email is verified
  # and matches an existing user email (enforced in User.register_with_google).
  # TODO: Make this auto-link policy opt-in per organization.
  # TODO: Add explicit UX flow for linking different-email Google and password accounts.

  ## Organization onboarding (authenticated, no org)

  scope "/", FirmowidWeb do
    pipe_through [:browser, :require_authenticated_user_without_organization]

    ash_authentication_live_session :without_org,
      on_mount: [{RequireNoOrganization, :default}] do
      live "/organization", Organization.Views.Index, :index
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

    ash_authentication_live_session :with_org,
      on_mount: [
        {RequireOrganization, :default},
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

      live "/ustawienia/bank/dodaj", BankSync.Views.Create, :index

      live "/zaproszenia", Organization.Invites.Views.Index, :index

      live "/analiza", Analysis.Views.Dashboard, :index

      live "/development", Development.Views.Index, :index
    end

    ash_authentication_live_session :with_org_management,
      on_mount: [
        {RequireOrganization, :default},
        {RequireAdmin, :default},
        {CurrentPath, :save_request_uri},
        Timezone
      ] do
      live "/zarzadzanie/pracownicy", Management.Views.Employees
      live "/zarzadzanie/pracownicy/:id", Management.Views.Employee, :projects
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

    ash_authentication_live_session :with_org_extended,
      on_mount: [
        {RequireOrganization, :default},
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

    ash_authentication_live_session :public,
      on_mount: [
        {CurrentPath, :save_request_uri},
        Timezone
      ] do
      live "/", Landing.Views.Index
      live "/polityka-prywatnosci", Landing.Views.PrivacyPolicy
      live "/regulamin", Landing.Views.TermsOfService
    end
  end

  scope "/api", FirmowidWeb do
    pipe_through [:api]

    # API login endpoint - SessionApi controller rewritten for Ash Authentication
    post "/login", Auth.Controllers.SessionApi, :create
  end
end
