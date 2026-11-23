defmodule FirmowidWeb.Billing.Controllers.CheckoutReturn do
  @moduledoc """
  Where Stripe Checkout brings an admin back after buying a plan.

  Stripe's redirect does not prove the purchase; the session is read from Stripe and synced here,
  so the plan is on when the admin arrives. The webhook does the same for a buyer who never comes
  back.
  """
  use FirmowidWeb, :controller

  alias Firmowid.Billing
  alias FirmowidWeb.Billing.Utilities.Navigation
  alias FirmowidWeb.Infrastructure.UserAuth

  @doc "Syncs the returned Checkout Session and leads the admin into the app."
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"sesja" => session_id}) do
    case Billing.complete_subscription_checkout(session_id, scope: conn.assigns.ash_scope) do
      {:ok, true} ->
        conn
        |> LiveToast.put_toast(:info, gettext("The plan is on."))
        |> redirect(to: UserAuth.signed_in_path(conn))

      {:ok, false} ->
        conn
        |> LiveToast.put_toast(:info, gettext("Stripe has not confirmed the purchase yet"))
        |> redirect(to: Navigation.plan_limit_path())

      {:error, _error} ->
        conn
        |> LiveToast.put_toast(:error, gettext("The purchase was not completed"))
        |> redirect(to: Navigation.plan_limit_path())
    end
  end

  def show(conn, _params), do: redirect(conn, to: Navigation.plan_limit_path())
end
