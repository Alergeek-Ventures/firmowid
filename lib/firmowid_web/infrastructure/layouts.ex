defmodule FirmowidWeb.Infrastructure.Layouts do
  @moduledoc """
  HTML layout helpers and embedded layout templates for the web UI.

  See the `layouts` directory for available templates.
  The "root" layout is a skeleton rendered as part of the
  application router. The "app" layout is set as the default
  layout on both `use FirmowidWeb, :controller` and
  `use FirmowidWeb, :live_view`.
  """
  use FirmowidWeb, :html

  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]
  import FirmowidWeb.DesignSystem.Components.Link
  import FirmowidWeb.Infrastructure.Flags
  import Phoenix.Component, except: [link: 1]

  alias FirmowidWeb.Core.Endpoint

  @default_meta_description "Firmowid pomaga polskim firmom wystawiać faktury zgodne z KSeF, synchronizować bank, ewidencjonować czas pracy i rozliczać zespół w jednym miejscu."

  embed_templates "layouts/*"

  @doc """
  Builds canonical URL for the currently rendered page.
  """
  @spec canonical_url(map()) :: String.t()
  def canonical_url(assigns) do
    Endpoint.url() <> canonical_path(assigns)
  end

  defp canonical_path(assigns) do
    case assigns[:current_uri] do
      %URI{path: path} when is_binary(path) and path != "" ->
        path

      _ ->
        case assigns[:conn] do
          %{request_path: request_path} when is_binary(request_path) and request_path != "" ->
            request_path

          _ ->
            "/"
        end
    end
  end

  defp meta_description(assigns) do
    assigns[:meta_description] || @default_meta_description
  end

  defp load_full_browser_assets?(assigns) do
    assigns[:public_marketing?] != true
  end
end
