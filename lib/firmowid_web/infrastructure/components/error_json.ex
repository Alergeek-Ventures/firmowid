defmodule FirmowidWeb.Infrastructure.Components.ErrorJson do
  @moduledoc """
  Renders errors of JSON requests as `%{errors: %{detail: status message}}`
  (see `render_errors` in config/config.exs).
  """

  def render(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end
end
