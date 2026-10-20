defmodule FirmowidWeb.Infrastructure.Controllers.OpenaiChallenge do
  @moduledoc "Serves OpenAI's public domain ownership challenge."
  use FirmowidWeb, :controller

  @doc "Returns the public verification value as plain text."
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, _params), do: text(conn, "Tm1xRYshmg1ZWsBdazncyO9xBPIF6PsLtsq3dDksLac")
end
