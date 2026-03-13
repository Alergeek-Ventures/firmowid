defmodule FirmowidWeb.DevelopmentLive do
  @moduledoc """
  Development guide page showing seed data overview, credentials, and testing info.

  Only accessible within the :admin live_session (requires authenticated user with organization).
  """
  use FirmowidWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Przewodnik deweloperski")}
  end

  @doc false
  def toggle_section(id) do
    {"aria-expanded", "true", "false"}
    |> JS.toggle_attribute(to: "#section-trigger-#{id}")
    |> JS.toggle_attribute({"data-expanded", ""}, to: "#section-panel-#{id}")
  end
end
