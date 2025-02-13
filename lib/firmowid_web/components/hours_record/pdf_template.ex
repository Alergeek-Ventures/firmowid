defmodule FirmowidWeb.HoursRecord.PdfTemplate do
  use FirmowidWeb, :html

  attr :name, :string, required: true
  attr :employment_date, :any, required: true
  attr :start_date, :any, required: true
  attr :end_date, :any, required: true
  attr :hours, :integer, required: true
  attr :logo_path, :string, default: "/images/av-logo-colors-nobg.png"

  def hours_record(assigns) do
    ~H"""
    <link rel="preconnect" href="https://fonts.googleapis.com" />
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
    <link
      href="https://fonts.googleapis.com/css2?family=PT+Sans:ital,wght@0,400;0,700;1,400;1,700&display=swap"
      rel="stylesheet"
    />
    <div class="w-[calc(595px-2*32px)] h-[calc(842px-2*32px)] relative p-8 box-content mx-auto bg-white font-['PT Sans'] text-[14px]">
      <div class="flex justify-between">
        <%!-- <img src={@logo_path} class="w-[200px] h-[200px]" /> --%>
        <div class="flex flex-col items-end mt-10 mr-9">
          <span class="text-[12px]">Imię i nazwisko Zleceniobiorcy</span>
          <span class="mt-1">{@name}</span>
        </div>
      </div>

      <div class="text-center mt-[45px] mb-[35px]">
        <h1 class="font-bold">Informacja o liczbie godzin wykonania zlecenia</h1>
      </div>

      <div class="mx-8">
        <p class="mb-[10px]">
          Informuję, iż na wykonanie zlecenia realizowanego na podstawie umowy
        </p>
        <p class="mb-[10px]">
          zawartej w dniu {format_date(@employment_date)} w okresie od {format_date(@start_date)} do {format_date(
            @end_date
          )}
        </p>
        <p>
          <%= if String.ends_with?(String.split(@name, " ") |> List.first(), "a") do %>
            przeznaczyłam
          <% else %>
            przeznaczyłem
          <% end %>
          {format_duration(@hours)}
        </p>
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
