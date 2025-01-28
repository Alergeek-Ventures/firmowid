defmodule FirmowidWeb.InvoicingLive.MonthClosedZeroState do
  use FirmowidWeb, :live_component

  def render(assigns) do
    ~H"""
    <div class="text-center items-center flex flex-col gap-6 my-8">
      <img src="/images/celebration.jpg" class="h-[360px] mx-auto" draggable="false" />
      <h2 class="font-bold text-xl">Gratulacje!</h2>
      <p class="max-w-[400px]">
        Ten miesiąc jest już za nami, więc nie pojawi się już więcej transakcji.
      </p>
      <p class="max-w-[400px]">
        To
        <span
          id="month-closed-annotation"
          phx-hook="tippy"
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
        phx-hook="tippy"
        href={
          "/file?month=#{@month}"
          # "/file?month=#{"2024-10-10"}"
        }
        download
        class="relative flex flex-row gap-4 items-center justify-center
        border rounded-lg px-5 py-2 max-md:hidden hover:bg-greyButtonBg
        hover:text-black transition-colors text-xl bg-black text-white"
      >
        <.icon name="hero-cloud-arrow-down" class="w-6 h-6" />
        <span class="max-lg:hidden">
          Pobierz
        </span>
      </a>
    </div>
    """
  end
end
