defmodule FirmowidWeb.Delegations.Utilities.DelegationPresentation do
  @moduledoc "Presentation helpers shared by employee and management delegation lists."

  use Gettext, backend: Firmowid.Gettext

  alias Firmowid.Delegations.PerDiem
  alias Firmowid.TimeFormatter

  @spec status_label(atom()) :: String.t()
  def status_label(:pending), do: gettext("Pending")
  def status_label(:in_progress), do: pgettext("business trip status", "in progress")

  def status_label(:awaiting_signature), do: pgettext("business trip status", "awaiting signature")

  def status_label(:submitted), do: pgettext("business trip status", "under review")
  def status_label(:complete), do: pgettext("business trip status", "approved")

  @spec status_badge_styles(atom()) :: list(String.t())
  def status_badge_styles(:pending), do: ["bg-teal-100 text-teal-700"]
  def status_badge_styles(:in_progress), do: ["bg-moss-200/80 text-moss-700"]
  def status_badge_styles(:awaiting_signature), do: ["bg-rust-100 text-rust-700"]
  def status_badge_styles(:submitted), do: ["bg-teal-100 text-teal-700"]
  def status_badge_styles(:complete), do: ["bg-grey-100 text-grey-700"]

  @spec format_range(Date.t(), Date.t()) :: String.t()
  def format_range(start_date, end_date), do: TimeFormatter.format_date_range(start_date, end_date)

  @spec format_date(Date.t()) :: String.t()
  def format_date(date), do: Calendar.strftime(date, "%d.%m.%Y")

  @doc "Formats an exchange rate with a Polish decimal comma."
  @spec format_rate(Decimal.t()) :: String.t()
  def format_rate(rate), do: rate |> Decimal.to_string(:normal) |> String.replace(".", ",")

  @doc "Labels a per-diem line, with the foreign amount and NBP rate it was converted with."
  @spec per_diem_line_label(PerDiem.line(), map()) :: String.t()
  def per_diem_line_label(%{foreign_amount: nil} = line, _delegation), do: per_diem_kind_label(line.kind)

  def per_diem_line_label(line, delegation) do
    gettext("%{label}: %{amount} at the NBP rate %{rate} of %{date}",
      label: per_diem_kind_label(line.kind),
      amount: Money.to_string!(line.foreign_amount),
      rate: format_rate(delegation.per_diem_nbp_rate),
      date: format_date(delegation.per_diem_nbp_rate_date)
    )
  end

  defp per_diem_kind_label(:domestic_per_diem), do: gettext("Domestic per diem")
  defp per_diem_kind_label(:foreign_per_diem), do: gettext("Foreign per diem")

  defp per_diem_kind_label(:accommodation_lump_sum), do: gettext("Lump sum for nights without a receipt")

  defp per_diem_kind_label(:local_transport_lump_sum), do: gettext("Lump sum for local transport")

  defp per_diem_kind_label(:station_transfer_lump_sum), do: gettext("Lump sum for station and airport transfers")

  @doc "Formats money with grouped thousands for delegation documents."
  @spec format_money(Money.t()) :: String.t()
  def format_money(money) do
    [_, integer, fraction, suffix] =
      Regex.run(~r/^(\d+)([,.]\d+)?(.*)$/u, Money.to_string!(money))

    grouped_integer =
      integer
      |> String.graphemes()
      |> Enum.reverse()
      |> Enum.chunk_every(3)
      |> Enum.reverse()
      |> Enum.map_join(" ", &(&1 |> Enum.reverse() |> Enum.join()))

    grouped_integer <> fraction <> String.replace(suffix, "\u00A0", " ")
  end
end
