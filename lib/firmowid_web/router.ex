defmodule FirmowidWeb.Router do
  use FirmowidWeb, :router

  import Phoenix.LiveDashboard.Router
  import FirmowidWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {FirmowidWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/admin" do
    pipe_through [:browser, :require_authenticated_user_with_organization, :require_superuser]

    live_dashboard "/dashboard",
      metrics: FirmowidWeb.Telemetry,
      additional_pages: [
        oban: Oban.LiveDashboard
      ]

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
    pipe_through [:browser, :require_authenticated_user_with_organization]

    live_session :require_authenticated_user_with_organization,
      on_mount: [{FirmowidWeb.UserAuth, :ensure_authenticated_with_organization}] do
      live "/", InvoicingLive.Index, :index
      live "/kosztowe/:id", CostInvoicesLive.Show, :index
      get "/pobierz-miesiac", FileController, :batch

      live "/sprzedazowe", SalesInvoicesLive.Index, :index
      live "/sprzedazowe/:id", SalesInvoicesLive.Index, :index
      get "/sprzedazowe/:id/pdf", PdfController, :index
      get "/sprzedazowe/:id/download", PdfController, :pdf

      live "/czasosledz", TimetrackerLive.Index, :index
      live "/czasosledz/projekty", TimetrackerLive.Projects, :projects

      live "/ustawienia/uzytkownik", User.SettingsLive, :edit
      live "/ustawienia/uzytkownik/potwierdz/:token", User.SettingsLive, :index

      live "/ustawienia", SettingsLive.Index, :index
      live "/ustawienia/bank", BankSyncLive.Index, :index
      live "/ustawienia/bank/dodaj", BankSyncLive.Create, :index

      live "/zaproszenia", OrganizationInvitesLive.Index, :index
    end
  end

  scope "/", FirmowidWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live_session :redirect_if_user_is_authenticated,
      on_mount: [{FirmowidWeb.UserAuth, :redirect_if_user_is_authenticated}] do
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
      on_mount: [{FirmowidWeb.UserAuth, :mount_current_user}] do
      live "/potwierdz/:token", User.ConfirmationLive, :edit
      live "/potwierdz", User.ConfirmationInstructionsLive, :new
    end
  end
end
