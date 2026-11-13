defmodule FirmowidWeb.Landing.Views.Guides do
  @moduledoc """
  Public guide list (`/poradnik`) and guide articles (`/poradnik/:slug`).
  """

  use FirmowidWeb, :live_view

  import FirmowidWeb.Landing.Components.LegalPage, only: [legal_page: 1]

  alias Firmowid.TimeFormatter
  alias FirmowidWeb.Core.Endpoint
  alias FirmowidWeb.Landing.Utilities.Guides

  @impl true
  def mount(params, _session, socket) do
    {:ok, socket |> assign(public_marketing?: true) |> assign_page(socket.assigns.live_action, params), layout: false}
  end

  defp assign_page(socket, :index, _params) do
    assign(socket,
      categories: Guides.by_category(),
      page_title: gettext("Firmowid guides — KSeF and invoicing"),
      meta_description: gettext("Practical guides on KSeF, e-invoices and invoicing software for small businesses.")
    )
  end

  defp assign_page(socket, :show, %{"slug" => slug}) do
    case Guides.fetch(slug) do
      {:ok, guide} ->
        assign(socket,
          article: guide,
          share_url: Endpoint.url() <> ~p"/poradnik/#{guide.slug}",
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
      <h1>{gettext("Firmowid guides: KSeF and invoicing")}</h1>
      <ul>
        <li :for={{category, _guides} <- @categories}>
          <a href={"#" <> category.slug}>{category.name}</a>
        </li>
      </ul>
      <section :for={{category, guides} <- @categories} id={category.slug}>
        <h2>{category.name}</h2>
        <p>{category.description}</p>
        <article :for={guide <- guides}>
          <h3><a href={~p"/poradnik/#{guide.slug}"}>{guide.title}</a></h3>
          <p>{guide.description}</p>
          <p class="text-sm text-grey-600">
            <time datetime={Date.to_iso8601(guide.updated)}>
              {TimeFormatter.format_date(guide.updated, :long)}
            </time>
          </p>
        </article>
      </section>
    </.legal_page>
    """
  end

  # sobelow_skip ["XSS.Raw"]
  # Guide HTML is compiled from Markdown committed in priv/guides with raw HTML disabled.
  def render(%{live_action: :show} = assigns) do
    ~H"""
    <.legal_page>
      <nav class="not-prose text-sm">
        <ol class="flex flex-wrap gap-x-2 text-grey-600">
          <li><a href={~p"/poradnik"} class="underline">{gettext("Guides")}</a></li>
          <li aria-hidden="true">/</li>
          <li>
            <a href={~p"/poradnik" <> "#" <> @article.category.slug} class="underline">
              {@article.category.name}
            </a>
          </li>
        </ol>
      </nav>
      <h1>{@article.title}</h1>
      <p class="text-sm text-grey-600">
        {gettext("Updated:")}
        <time datetime={Date.to_iso8601(@article.updated)}>
          {TimeFormatter.format_date(@article.updated, :long)}
        </time>
      </p>
      <div class="[&_table]:block [&_table]:overflow-x-auto">{Phoenix.HTML.raw(@article.html)}</div>
      <div class="not-prose mt-12 flex flex-wrap items-center gap-3 border-t border-grey-300 pt-6 text-sm font-medium [&>a]:rounded-full [&>a]:border [&>a]:border-grey-300 [&>a]:px-4 [&>a]:py-2 [&>a:hover]:border-grey-900 [&>button]:rounded-full [&>button]:border [&>button]:border-grey-300 [&>button]:px-4 [&>button]:py-2 [&>button:hover]:border-grey-900">
        <.icon name="hero-share" class="size-5 text-grey-600" />
        <a
          href={"https://www.linkedin.com/sharing/share-offsite/?" <> URI.encode_query(url: @share_url)}
          target="_blank"
          rel="noopener noreferrer"
        >
          LinkedIn
        </a>
        <a
          href={"https://www.facebook.com/sharer/sharer.php?" <> URI.encode_query(u: @share_url)}
          target="_blank"
          rel="noopener noreferrer"
        >
          Facebook
        </a>
        <a
          href={"https://x.com/intent/post?" <> URI.encode_query(url: @share_url, text: @article.title)}
          target="_blank"
          rel="noopener noreferrer"
        >
          X
        </a>
        <button
          id="copy-guide-link"
          type="button"
          phx-hook="CopyToClipboard"
          data-copy-text={@share_url}
        >
          <span data-copy-label>{gettext("Copy")}</span>
          <span data-copy-done class="hidden">{gettext("Link copied to the clipboard.")}</span>
        </button>
      </div>
    </.legal_page>
    """
  end
end
