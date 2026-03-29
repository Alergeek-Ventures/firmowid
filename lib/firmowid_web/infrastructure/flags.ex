defmodule FirmowidWeb.Infrastructure.Flags do
  @moduledoc """
  Convenience wrapper around FunWithFlags for use in templates.

  Imported automatically via `html_helpers/0`, so every LiveView,
  LiveComponent and HTML module can call `flag_enabled?/2` directly.

  ## Usage in templates

      <%= if flag_enabled?(:analysis_dashboard, @current_user) do %>
        <.link navigate={~p"/analiza"}>Analiza</.link>
      <% end %>

  Returns `false` when the user is `nil` or the flag does not exist,
  so a missing flag never breaks anything.
  """

  @doc """
  Returns `true` when `flag_name` is enabled for the given user.

  Safely returns `false` for `nil` users or non-existent flags.
  """
  @spec flag_enabled?(atom(), map() | nil) :: boolean()
  def flag_enabled?(flag_name, user) when is_atom(flag_name) do
    case user do
      nil -> false
      user -> FunWithFlags.enabled?(flag_name, for: user)
    end
  end
end
