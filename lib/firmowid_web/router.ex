defmodule FirmowidWeb.Router do
  use FirmowidWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {FirmowidWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", FirmowidWeb do
    pipe_through :browser

    get "/", PageController, :home

    live "/bank_accounts", BankAccountLive.Index, :index
    live "/bank_accounts/new", BankAccountLive.Index, :new
    live "/bank_accounts/:id/edit", BankAccountLive.Index, :edit

    live "/bank_accounts/:id", BankAccountLive.Show, :show
    live "/bank_accounts/:id/show/edit", BankAccountLive.Show, :edit

    live "/imported_transactions", ImportedTransactionLive.Index, :index
    live "/imported_transactions/new", ImportedTransactionLive.Index, :new
    live "/imported_transactions/:id/edit", ImportedTransactionLive.Index, :edit

    live "/imported_transactions/:id", ImportedTransactionLive.Show, :show
    live "/imported_transactions/:id/show/edit", ImportedTransactionLive.Show, :edit

    live "/requisitions", RequisitionLive.Index, :index
    live "/requisitions/new", RequisitionLive.Index, :new
    live "/requisitions/:id/edit", RequisitionLive.Index, :edit

    live "/requisitions/:id", RequisitionLive.Show, :show
    live "/requisitions/:id/show/edit", RequisitionLive.Show, :edit
  end

  # Other scopes may use custom stacks.
  # scope "/api", FirmowidWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:firmowid, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: FirmowidWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
