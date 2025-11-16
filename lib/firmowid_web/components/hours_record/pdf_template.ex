defmodule FirmowidWeb.HoursRecord.PdfTemplate do
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
    <div class="w-[210mm] border print:border-none h-[267mm] relative py-[120px] px-[32px] mx-auto bg-white text-[16px]">
      <div class="flex justify-between">
        <div>
          <%= if @avatar_data_uri do %>
            <img src={@avatar_data_uri} class="w-[200px] h-[200px]" />
          <% else %>
            <img :if={@avatar_url} src={@avatar_url} class="w-[200px] h-[200px]" />
          <% end %>
        </div>
        <div class="flex flex-col items-end mt-10 mr-9">
          <span>Imię i nazwisko Zleceniobiorcy</span>
          <span class="mt-1">{@name}</span>
        </div>
      </div>

      <div class="text-center mt-[60px] mb-[35px]">
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

      <div class="text-right mr-[68px] mt-[160px]">
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
