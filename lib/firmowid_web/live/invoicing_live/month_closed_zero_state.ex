defmodule FirmowidWeb.InvoicingLive.MonthClosedZeroState do
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
        <a
          id="download-button-cta"
          data-tippy-content="Pobierz wszystkie faktury wystawione w tym miesiącu"
          data-tippy-delay="3000"
          phx-hook="Tippy"
          href={"/file?month=#{@month}"}
          download
          class="relative flex flex-row gap-4 items-center justify-center
        border rounded-lg px-5 py-2 max-md:hidden hover:bg-greyButtonBg
        hover:text-black transition-colors text-xl bg-black text-white max-w-[200px] max-h-[48px]"
        >
          <.icon name="hero-cloud-arrow-down" class="w-6 h-6" />
          <span class="max-lg:hidden">
            Pobierz
          </span>
        </a>
      </div>
    </div>
    """
  end
end
