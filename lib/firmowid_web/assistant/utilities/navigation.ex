defmodule FirmowidWeb.Assistant.Utilities.Navigation do
  @moduledoc "Canonical URL of the full assistant page, and whether an organization's plan offers the assistant."

  use FirmowidWeb, :verified_routes

  alias Firmowid.Billing.PlanCatalog

  @doc "Whether the organization's billing plan includes the assistant; the places that start a conversation render only then."
  @spec available?(%{billing_plan: PlanCatalog.plan()}) :: boolean()
  def available?(%{billing_plan: plan}), do: PlanCatalog.includes?(plan, :assistant)

  @doc "The full-screen assistant page with the conversation list."
  @spec page_path() :: String.t()
  def page_path, do: ~p"/asystent"
end
