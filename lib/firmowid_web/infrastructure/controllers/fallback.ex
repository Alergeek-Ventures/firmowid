defmodule FirmowidWeb.Infrastructure.Controllers.Fallback do
  @moduledoc """
  Translates controller action results into valid `Plug.Conn` responses.

  See `Phoenix.Controller.action_fallback/1` for more details.
  """
  use FirmowidWeb, :controller

  alias FirmowidWeb.Infrastructure.Components.ErrorJson

  # This clause handles errors returned by Ecto's insert/update/delete.
  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: FirmowidWeb.Infrastructure.Components.ChangesetJson)
    |> render(:error, changeset: changeset)
  end

  # This clause is an example of how to handle resources that cannot be found.
  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(html: FirmowidWeb.Infrastructure.Components.ErrorHtml, json: ErrorJson)
    |> render(:"404")
  end

  def call(conn, {:error, :unauthorized}) do
    conn
    |> put_status(:unauthorized)
    |> put_view(ErrorJson)
    |> render(:"401")
  end
end
