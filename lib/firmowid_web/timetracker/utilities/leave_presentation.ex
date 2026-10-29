defmodule FirmowidWeb.Timetracker.Utilities.LeavePresentation do
  @moduledoc """
  Shared labels, icons, and formatting for leave request UI.
  """

  use Gettext, backend: Firmowid.Gettext

  @type reason ::
          :sick | :vacation | :unpaid | :indisposition | :rest | :other
  @type status :: :pending | :accepted | :declined
  @type label_style :: :short | :full

  @spec reason_label(reason(), label_style()) :: String.t()
  def reason_label(reason, style \\ :full)

  def reason_label(:vacation, :short), do: pgettext("leave type, short", "Recreational")
  def reason_label(:sick, :short), do: pgettext("leave type, short", "Sick")
  def reason_label(:unpaid, :short), do: pgettext("leave type, short", "Unpaid")
  def reason_label(:vacation, :full), do: pgettext("leave type", "Recreational leave")
  def reason_label(:sick, :full), do: pgettext("leave type", "Sick leave")
  def reason_label(:unpaid, :full), do: pgettext("leave type", "Unpaid leave")
  def reason_label(:indisposition, _), do: pgettext("leave type", "Indisposition")
  def reason_label(:rest, _), do: pgettext("leave type", "Rest")
  def reason_label(:other, _), do: pgettext("leave type", "Other")

  @spec reason_icon(reason()) :: String.t()
  def reason_icon(:vacation), do: "hero-sun"
  def reason_icon(:sick), do: "hero-heart"
  def reason_icon(:unpaid), do: "hero-no-symbol"
  def reason_icon(:indisposition), do: "hero-face-frown"
  def reason_icon(:rest), do: "hero-moon"
  def reason_icon(:other), do: "hero-ellipsis-horizontal"

  @spec status_label(status()) :: String.t()
  def status_label(:pending), do: gettext("Pending")
  def status_label(:accepted), do: pgettext("leave request status", "approved")
  def status_label(:declined), do: pgettext("leave request status", "rejected")

  @spec status_badge_styles(status()) :: String.t()
  def status_badge_styles(:pending), do: "bg-teal-100 text-teal-700"
  def status_badge_styles(:accepted), do: "bg-moss-100 text-moss-700"
  def status_badge_styles(:declined), do: "bg-brick-100 text-brick-700"

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
