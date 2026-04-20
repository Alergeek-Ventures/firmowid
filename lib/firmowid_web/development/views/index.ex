defmodule FirmowidWeb.Development.Views.Index do
  @moduledoc """
  Development guide page showing seed data overview, credentials, and testing info.

  Intentionally accessible to all authenticated org members (not just admins).
  Lives in the :admin live_session which requires an authenticated user with an
  organization, but has no additional role-based gate. This is a read-only
  reference page with no sensitive data — it shows seed data structure and
  testing guidance.
  """
  use FirmowidWeb, :live_view

  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]
  import FirmowidWeb.DesignSystem.Components.Link
  import Phoenix.Component, except: [link: 1]

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
