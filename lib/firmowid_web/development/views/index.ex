defmodule FirmowidWeb.Development.Views.Index do
  @moduledoc """
  Development-only guide page showing seed data overview, credentials, and testing info.

  Its route is registered only in the development environment. There it is
  intentionally accessible to all authenticated organization members (not just
  admins), through the regular organization live session. It is a read-only
  reference page with seed data structure and testing guidance.
  """
  use FirmowidWeb, :live_view

  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]
  import FirmowidWeb.DesignSystem.Components.InvoicingBadges
  import FirmowidWeb.DesignSystem.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias FirmowidWeb.DesignSystem.Components.InvoicingBadges

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Przewodnik deweloperski",
       bank_badges: InvoicingBadges.bank_badge_variants()
     )}
  end

  @doc false
  def toggle_section(id) do
    {"aria-expanded", "true", "false"}
    |> JS.toggle_attribute(to: "#section-trigger-#{id}")
    |> JS.toggle_attribute({"data-expanded", ""}, to: "#section-panel-#{id}")
  end
end
