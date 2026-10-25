defmodule FirmowidWeb.Invoicing.Components.MonthClosedZeroState do
  @moduledoc false
  use FirmowidWeb, :live_component

  def render(assigns) do
    ~H"""
    <div class="my-8 flex flex-col justify-center gap-4 md:flex-row">
      <img src="/images/celebration.jpg" class="h-[360px]" draggable="false" />
      <div class="flex flex-col items-center gap-6 text-center">
        <h2 class="text-xl font-bold">Gratulacje!</h2>
        <p class="max-w-[400px]">
          Ten miesiąc jest już za nami, więc nie pojawi się już więcej transakcji.
        </p>
        <p class="max-w-[400px]">
          To
          <span
            id="month-closed-annotation"
            phx-hook="Tippy"
            data-tippy-content="Wciąż możesz dodać faktury opłacone z innego konta lub gotówką."
          >
            najprawdopodobniej*
          </span>
          oznacza, że miesiąc można uznać za
          zamknięty.
        </p>

        <p class="max-w-[400px]">
          Możesz pobrać paczkę wszystkich faktur wystawionych w tym miesiącu:
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
