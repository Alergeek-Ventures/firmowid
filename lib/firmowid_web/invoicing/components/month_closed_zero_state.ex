defmodule FirmowidWeb.Invoicing.Components.MonthClosedZeroState do
  @moduledoc false
  use FirmowidWeb, :live_component

  def render(assigns) do
    ~H"""
    <div class="justify-center flex flex-col md:flex-row gap-4 my-8">
      <img src="/images/celebration.jpg" class="h-[360px]" draggable="false" />
      <div class="flex flex-col gap-6 text-center items-center">
        <h2 class="font-bold text-xl">Gratulacje!</h2>
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
