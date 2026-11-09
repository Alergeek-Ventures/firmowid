defmodule FirmowidWeb.Assistant.Utilities.Navigation do
  @moduledoc "Canonical URL of the full assistant page."

  use FirmowidWeb, :verified_routes

  @doc "The full-screen assistant page with the conversation list."
  @spec page_path() :: String.t()
  def page_path, do: ~p"/asystent"
end
