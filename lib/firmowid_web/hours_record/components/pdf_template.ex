defmodule FirmowidWeb.HoursRecord.Components.PdfTemplate do
  @moduledoc false
  use FirmowidWeb, :html

  attr :name, :string, required: true
  attr :employment_date, :any, required: true
  attr :start_date, :any, required: true
  attr :end_date, :any, required: true
  attr :hours, :integer, required: true
  attr :avatar_url, :string, default: nil
  attr :avatar_data_uri, :string, default: nil

  def hours_record(assigns) do
    ~H"""
    <div class="relative mx-auto h-[267mm] w-[210mm] border bg-white px-[32px] py-[120px] text-[16px] print:border-none">
      <div class="flex justify-between">
        <div>
          <%= if @avatar_data_uri do %>
            <img src={@avatar_data_uri} class="h-[200px] w-[200px]" />
          <% else %>
            <img :if={@avatar_url} src={@avatar_url} class="h-[200px] w-[200px]" />
          <% end %>
        </div>
        <div class="mt-10 mr-9 flex flex-col items-end">
          <span>Imię i nazwisko Zleceniobiorcy</span>
          <span class="mt-1">{@name}</span>
        </div>
      </div>

      <div class="mt-[60px] mb-[35px] text-center">
        <h1 class="font-bold">Informacja o liczbie godzin wykonania zlecenia</h1>
      </div>
      <div class="flex justify-center">
        <div>
          <p class="mb-2.5">
            Informuję, iż na wykonanie zlecenia realizowanego na podstawie umowy
          </p>
          <p class="mb-2.5">
            zawartej w dniu {format_date(@employment_date)} w okresie od {format_date(@start_date)} do {format_date(
              @end_date
            )}
          </p>
          <p>przeznaczyłem {format_duration(@hours)}.</p>
        </div>
      </div>

      <div class="mt-[160px] mr-[68px] text-right">
        <p>Podpis Zleceniobiorcy</p>
      </div>
    </div>
    """
  end

  defp format_date(date) do
    Calendar.strftime(date, "%d.%m.%Y")
  end

  defp format_duration(hours) do
    hours_text =
      if rem(hours, 10) in [2, 3, 4] and div(hours, 10) != 1 do
        "godziny"
      else
        "godzin"
      end

    "#{hours} #{hours_text}"
  end
end
