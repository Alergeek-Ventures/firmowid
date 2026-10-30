defmodule FirmowidWeb.Landing.Views.Guides do
  @moduledoc """
  Public guide list (`/poradnik`) and guide articles (`/poradnik/:slug`).
  """

  use FirmowidWeb, :live_view

  import FirmowidWeb.Landing.Components.LegalPage, only: [legal_page: 1]

  alias Firmowid.TimeFormatter
  alias FirmowidWeb.Landing.Utilities.Guides

  @impl true
  def mount(params, _session, socket) do
    {:ok, socket |> assign(public_marketing?: true) |> assign_page(socket.assigns.live_action, params), layout: false}
  end

  defp assign_page(socket, :index, _params) do
    assign(socket,
      guides: Guides.all(),
      page_title: gettext("Firmowid guides — KSeF and invoicing"),
      meta_description: gettext("Practical guides on KSeF, e-invoices and invoicing software for small businesses.")
    )
  end

  defp assign_page(socket, :show, %{"slug" => slug}) do
    case Guides.fetch(slug) do
      {:ok, guide} ->
        assign(socket,
          article: guide,
          page_title: guide.title,
          meta_description: guide.description
        )

      :error ->
        raise Ecto.NoResultsError, queryable: "guides"
    end
  end

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(%{live_action: :index} = assigns) do
    ~H"""
    <.legal_page>
      <h1>{gettext("Guides")}</h1>
      <article :for={guide <- @guides}>
        <h2><a href={~p"/poradnik/#{guide.slug}"}>{guide.title}</a></h2>
        <p>{guide.description}</p>
        <p class="text-sm text-grey-600">
          <time datetime={Date.to_iso8601(guide.updated)}>
            {TimeFormatter.format_date(guide.updated, :long)}
          </time>
        </p>
      </article>
    </.legal_page>
    """
  end

  # sobelow_skip ["XSS.Raw"]
  # Guide HTML is compiled from Markdown committed in priv/guides with raw HTML disabled.
  def render(%{live_action: :show} = assigns) do
    ~H"""
    <.legal_page>
      <p class="text-sm">
        <a href={~p"/poradnik"}>{gettext("All guides")}</a>
      </p>
      <h1>{@article.title}</h1>
      <p class="text-sm text-grey-600">
        {gettext("Updated:")}
        <time datetime={Date.to_iso8601(@article.updated)}>
          {TimeFormatter.format_date(@article.updated, :long)}
        </time>
      </p>
      <div class="[&_table]:block [&_table]:overflow-x-auto">{Phoenix.HTML.raw(@article.html)}</div>
    </.legal_page>
    """
  end
end
