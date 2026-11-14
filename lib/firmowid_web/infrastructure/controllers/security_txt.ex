defmodule FirmowidWeb.Infrastructure.Controllers.SecurityTxt do
  @moduledoc "Serves the RFC 9116 security.txt with the vulnerability reporting contact."
  use FirmowidWeb, :controller

  # RFC 9116 requires an Expires field and recommends less than a year ahead.
  # Counting it from today keeps the file valid without a yearly edit.
  @validity_days 180

  @doc "Returns security.txt as plain text, valid for #{@validity_days} days from today."
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, _params) do
    expires = Date.utc_today() |> Date.add(@validity_days) |> DateTime.new!(~T[00:00:00])

    text(conn, """
    Contact: mailto:contact@alergeek.ventures
    Expires: #{DateTime.to_iso8601(expires)}
    Policy: https://github.com/Alergeek-Ventures/firmowid/blob/main/SECURITY.md
    Preferred-Languages: pl, en
    """)
  end
end
