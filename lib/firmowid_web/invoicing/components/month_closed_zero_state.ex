defmodule FirmowidWeb.Invoicing.Components.MonthClosedZeroState do
  @moduledoc false
  use FirmowidWeb, :live_component

  def render(assigns) do
    [closed_before, closed_after] =
      "This %{likely} means the month can be considered closed."
      |> gettext(likely: "__LIKELY__")
      |> String.split("__LIKELY__", parts: 2)

    assigns = assign(assigns, closed_before: closed_before, closed_after: closed_after)

    ~H"""
    <div class="my-8 flex flex-col justify-center gap-4 md:flex-row">
      <img src="/images/celebration.jpg" class="h-[360px]" draggable="false" />
      <div class="flex flex-col items-center gap-6 text-center">
        <h2 class="text-xl font-bold">{gettext("Congratulations!")}</h2>
        <p class="max-w-[400px]">
          {gettext("This month is behind us, so no more transactions will appear.")}
        </p>
        <p class="max-w-[400px]">
          {@closed_before}<span
            id="month-closed-annotation"
            phx-hook="Tippy"
            data-tippy-content={
              gettext("You can still add invoices paid from another account or in cash.")
            }
          >{gettext("most likely*")}</span>{@closed_after}
        </p>

        <p class="max-w-[400px]">
          {gettext("You can download a package of all invoices issued this month:")}
        </p>
        <.live_component
          id="download-modal"
          module={FirmowidWeb.Invoicing.Components.DownloadModal}
          month={@month}
        />
      </div>
    </div>
    """
  end
end
