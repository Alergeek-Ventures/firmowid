defmodule FirmowidWeb.Timetracker.Utilities.LeavePresentation do
  @moduledoc """
  Shared labels, icons, and formatting for leave request UI.
  """

  @type reason ::
          :sick | :vacation | :unpaid | :indisposition | :rest | :other
  @type status :: :pending | :accepted | :declined
  @type label_style :: :short | :full

  @spec reason_label(reason(), label_style()) :: String.t()
  def reason_label(reason, style \\ :full)

  def reason_label(:vacation, :short), do: "Wypoczynkowy"
  def reason_label(:sick, :short), do: "Zdrowotny"
  def reason_label(:unpaid, :short), do: "Bezpłatny"
  def reason_label(:vacation, :full), do: "Urlop wypoczynkowy"
  def reason_label(:sick, :full), do: "Urlop zdrowotny"
  def reason_label(:unpaid, :full), do: "Urlop bezpłatny"
  def reason_label(:indisposition, _), do: "Niedyspozycja"
  def reason_label(:rest, _), do: "Wypoczynek"
  def reason_label(:other, _), do: "Inne"

  @spec reason_icon(reason()) :: String.t()
  def reason_icon(:vacation), do: "hero-sun"
  def reason_icon(:sick), do: "hero-heart"
  def reason_icon(:unpaid), do: "hero-no-symbol"
  def reason_icon(:indisposition), do: "hero-face-frown"
  def reason_icon(:rest), do: "hero-moon"
  def reason_icon(:other), do: "hero-ellipsis-horizontal"

  @spec status_label(status()) :: String.t()
  def status_label(:pending), do: "oczekujący"
  def status_label(:accepted), do: "zatwierdzony"
  def status_label(:declined), do: "odrzucony"

  @spec status_badge_styles(status()) :: String.t()
  def status_badge_styles(:pending), do: "bg-turquoise-100 text-turquoise-700"
  def status_badge_styles(:accepted), do: "bg-green-100 text-green-700"
  def status_badge_styles(:declined), do: "bg-red-100 text-red-700"

  @spec format_range(Date.t(), Date.t()) :: String.t()
  def format_range(%Date{} = from, %Date{} = to) when from == to do
    "#{pad(to.day)}.#{pad(to.month)}.#{to.year}"
  end

  def format_range(%Date{} = from, %Date{} = to) when from.year == to.year and from.month == to.month do
    "#{from.day}-#{pad(to.day)}.#{pad(to.month)}.#{to.year}"
  end

  def format_range(%Date{} = from, %Date{} = to) when from.year == to.year do
    "#{pad(from.day)}.#{pad(from.month)}-#{pad(to.day)}.#{pad(to.month)}.#{to.year}"
  end

  def format_range(%Date{} = from, %Date{} = to) do
    "#{pad(from.day)}.#{pad(from.month)}.#{from.year}-#{pad(to.day)}.#{pad(to.month)}.#{to.year}"
  end

  @spec filter_by_search([map()], String.t() | nil, label_style()) :: [map()]
  def filter_by_search(requests, search, label_style \\ :full)
  def filter_by_search(requests, search, _label_style) when search in [nil, ""], do: requests

  def filter_by_search(requests, search, label_style) do
    q = String.downcase(search)

    Enum.filter(requests, fn request ->
      [
        reason_label(request.reason, label_style),
        status_label(request.status),
        to_string(request.note || ""),
        format_range(request.starts_on, request.ends_on)
      ]
      |> Enum.join(" ")
      |> String.downcase()
      |> String.contains?(q)
    end)
  end

  defp pad(n), do: n |> Integer.to_string() |> String.pad_leading(2, "0")
end
