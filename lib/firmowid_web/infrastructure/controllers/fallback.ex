defmodule FirmowidWeb.Infrastructure.Controllers.Fallback do
  @moduledoc """
  Answers the `{:error, :unauthorized}` a controller action returns (see
  `Phoenix.Controller.action_fallback/1`).
  """
  use FirmowidWeb, :controller

  alias FirmowidWeb.Infrastructure.Components.ErrorHtml
  alias FirmowidWeb.Infrastructure.Components.ErrorJson

  def call(conn, {:error, :unauthorized}) do
    conn
    |> put_status(:unauthorized)
    |> put_view(html: ErrorHtml, json: ErrorJson)
    |> render(:"401", layout: false)
  end
end
