defmodule FirmowidWeb.Router do
  use FirmowidWeb, :router

  import Phoenix.LiveDashboard.Router
  import FirmowidWeb.UserAuth
  import Oban.Web.Router
  import FirmowidWeb.RedirectTrailing

  pipeline :browser do
    plug :accepts, ["html"]
    plug :redirect_trailing_slash
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {FirmowidWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers

    plug ContentSecurityPolicy.Plug.Setup,
      default_policy: %ContentSecurityPolicy.Policy{
        default_src: ["'self'", "https://i.alergeek.workers.dev"],
        font_src: ["'self'", "fonts.gstatic.com"],
        style_src: [
          "'self'",
          "'unsafe-inline'",
          "https://fonts.googleapis.com",
          "https://cdn.jsdelivr.net"
        ],
        img_src: ["'self'", "https:", "data:"],
        script_src: [
          "'self'",
          "https://i.alergeek.workers.dev",
          if(Mix.env() == :dev, do: "http://127.0.0.1:4007")
        ]
      }

    plug ContentSecurityPolicy.Plug.AddNonce, directives: [:script_src]

    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :fetch_api_user
  end

  scope "/admin" do
    pipe_through [:browser, :require_authenticated_user_with_organization, :require_superuser]

    live_dashboard "/dashboard",
      ### TODO:
      ### Ecto repo stats:
      # - unused indices, adding how to remove them here (but didn't because they might be used)
      #   - drop index(:oban_jobs, [:meta], prefix: "oban")
      #   - drop index(:oban_jobs, [:args], prefix: "oban")
      # -  Missing foreign key constraints detected:
      #   - 'transactions'.'transaction_id' - false positive
      metrics: FirmowidWeb.Telemetry,
      csp_nonce_assign_key: :csp_nonce

    oban_dashboard("/oban", oban_name: Firmowid.Oban, csp_nonce_assign_key: :csp_nonce)

    forward "/mailbox", Plug.Swoosh.MailboxPreview
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
        {FirmowidWeb.Live.Hooks.CurrentPath, :save_request_uri}
      ] do
      live "/", InvoicingLive.Index, :index
      live "/kosztowe/:id", CostInvoiceLive.Show, :show

      live "/sprzedazowe", SalesInvoicesLive.Index, :index
      live "/sprzedazowe/kreator", SalesInvoicesLive.Create, :index
      live "/sprzedazowe/:id", SalesInvoicesLive.Show, :show
      live "/sprzedazowe/:id/edycja", SalesInvoicesLive.Index, :index

      live "/czasosledz/projekty", Project.Index, :projects
      live "/czasosledz/projekty/dodaj", Project.ProjectNew, :new
      live "/czasosledz/projekty/:id", Project.Index, :projects

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
        {FirmowidWeb.Live.Hooks.CurrentPath, :save_request_uri}
      ] do
      live "/czasosledz", TimetrackerLive.Index, :index

      live "/czasosledz/ewidencja", HoursRecordLive.Index, :index

      live "/ustawienia/uzytkownik", User.SettingsLive, :edit
      live "/ustawienia/uzytkownik/potwierdz/:token", User.SettingsLive, :index

      live "/ustawienia", SettingsLive.Index, :index
    end
  end

  scope "/", FirmowidWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live_session :redirect_if_user_is_authenticated,
      on_mount: [
        {FirmowidWeb.UserAuth, :redirect_if_user_is_authenticated},
        {FirmowidWeb.Live.Hooks.CurrentPath, :save_request_uri}
      ] do
      live "/zarejestruj", User.RegistrationLive, :new
      live "/zaloguj", User.LoginLive, :new
      live "/resetuj-haslo", User.ForgotPasswordLive, :new
      live "/resetuj-haslo/:token", User.ResetPasswordLive, :edit
    end

    post "/zaloguj", UserSessionController, :create
  end

  scope "/", FirmowidWeb do
    pipe_through [:browser]

    delete "/wyloguj", UserSessionController, :delete

    live_session :current_user,
      on_mount: [
        {FirmowidWeb.UserAuth, :mount_current_user},
        {FirmowidWeb.Live.Hooks.CurrentPath, :save_request_uri}
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
