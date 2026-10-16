defmodule FirmowidWeb.Development.Components.McpPage do
  @moduledoc "Development-only page hosting MCP widget scenarios in inline and fullscreen frames."
  use FirmowidWeb, :html

  import FirmowidUI.Components.Button

  @doc "Lists scenarios; `assets/js/mcp/dev_host.js` connects each frame to the widget."
  @spec index(map()) :: Phoenix.LiveView.Rendered.t()
  def index(assigns) do
    ~H"""
    <main id="mcp-dev-host" data-host={@host} class="min-h-screen space-y-10 bg-grey-100 p-6">
      <header class="space-y-1">
        <h1 class="text-2xl font-semibold">Widżety MCP</h1>
        <p class="text-sm text-grey-600">
          Prawdziwe widżety ChatGPT z wynikami narzędzi wyliczonymi dla Twojej organizacji.
          Podpisane sesje wygasają po 15 minutach — odśwież stronę, aby je odnowić.
          Kontekst przekazywany modelowi trafia do konsoli przeglądarki.
        </p>
      </header>

      <p :if={@scenarios == []} class="text-grey-600">Brak danych do zbudowania scenariuszy.</p>

      <section :for={scenario <- @scenarios} class="space-y-3">
        <h2 class="text-lg font-semibold">
          {scenario.title} <code class="text-sm text-grey-500">{scenario.app.tool_name()}</code>
        </h2>
        <div class="flex flex-wrap items-start gap-6">
          <figure
            :for={mode <- ~w(inline fullscreen)}
            data-mcp-frame
            data-scenario={scenario.id}
            data-mode={mode}
            class="max-w-full space-y-2"
          >
            <figcaption class="flex items-center gap-3 text-sm text-grey-600">
              <span data-mode-label>{mode}</span>
              <.button
                type="button"
                variant="unstyled"
                data-exit-fullscreen
                hidden
                class="underline"
              >
                Wróć do inline
              </.button>
            </figcaption>
            <iframe
              title={"#{scenario.title} (#{mode})"}
              class="block max-w-full rounded-xl border border-grey-300 bg-white"
            ></iframe>
          </figure>
        </div>
      </section>

      <script defer src={~p"/assets/mcp_dev_host.js"}>
      </script>
    </main>
    """
  end
end
