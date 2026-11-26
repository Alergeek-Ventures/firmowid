defmodule FirmowidWeb.Billing.Utilities.Worksheet do
  @moduledoc """
  Shapes billing facts into a worksheet-oriented structure for billing views:
  the plan, what the organization uses of each limited thing, and the cheapest
  plan that covers that usage.

  Also holds the labels and price texts the billing screens share, such as
  `plan_label/1`, `limited_label/1`, `period_label/1`, `net_price_text/2` and
  `format_money/1`.
  """

  use Gettext, backend: Firmowid.Gettext

  alias Firmowid.Billing.PlanCatalog

  @type usage_source :: %{
          required(:billing_plan) => PlanCatalog.plan(),
          required(:active_non_owner_users_count) => non_neg_integer(),
          optional(atom()) => term()
        }

  @limited [:bank_institutions, :users, :active_projects]

  @doc """
  Builds worksheet sections for a selected month.
  """
  @spec build(usage_source()) :: map()
  def build(source) do
    plan = source.billing_plan
    rules = PlanCatalog.plan!(plan)
    usage = PlanCatalog.usage(source)
    fitting_plan = PlanCatalog.fitting_plan(usage)

    # A month frozen before banks or projects were counted has no row for them.
    usage_rows =
      @limited
      |> Enum.reject(&is_nil(usage[&1]))
      |> Enum.map(&usage_row(&1, usage[&1], rules.limits[&1]))

    %{
      selected_plan: plan,
      selected_plan_label: plan_label(plan),
      monthly_price_text: format_money(rules.monthly_price_pln),
      usage_rows: usage_rows,
      # `:no_plan` marks a blocked organization, not an offer whose limits it can exceed.
      over_limit?: plan != :no_plan and Enum.any?(usage_rows, &(&1.over_limit > 0)),
      fitting_plan: fitting_plan,
      fitting_plan_label: plan_label(fitting_plan),
      fitting_plan_price_text: format_money(PlanCatalog.plan!(fitting_plan).monthly_price_pln)
    }
  end

  @doc """
  Returns the human label for a plan.
  """
  @spec plan_label(PlanCatalog.plan()) :: String.t()
  def plan_label(:no_plan), do: pgettext("billing plan", "No plan")
  def plan_label(:free), do: gettext("Free")
  def plan_label(:przedsiebiorca), do: gettext("Entrepreneur")
  def plan_label(:firma), do: gettext("Company")

  @doc """
  Returns the human label for a billing period.
  """
  @spec period_label(PlanCatalog.billing_period()) :: String.t()
  def period_label(:monthly), do: pgettext("billing period", "Monthly")
  def period_label(:yearly), do: pgettext("billing period", "Yearly")

  @doc """
  Returns a net price for a billing period, as the screens state it.
  """
  @spec net_price_text(Decimal.t(), PlanCatalog.billing_period()) :: String.t()
  def net_price_text(net, :monthly), do: gettext("%{price} + VAT / month", price: format_money(net))

  def net_price_text(net, :yearly), do: gettext("%{price} + VAT / year", price: format_money(net))

  @doc """
  Formats a PLN amount, without grosze when it has none.
  """
  @spec format_money(Decimal.t()) :: String.t()
  def format_money(amount), do: :PLN |> Money.new(amount) |> Money.to_string!(no_fraction_if_integer: true)

  @doc """
  Returns the row of the documents the organization sent to OCR this month, in
  the shape of a usage row. The month's count is not frozen in a snapshot, so
  the row stands beside the worksheet's rows.
  """
  @spec ocr_documents_row(%{used: non_neg_integer(), limit: PlanCatalog.limit()}) :: map()
  def ocr_documents_row(%{used: used, limit: limit}) do
    over_limit = over_limit(used, limit)

    %{
      key: :ocr_documents,
      label: gettext("Document OCR"),
      context: gettext("Documents sent to OCR this month."),
      count: used,
      limit_text: limit_text(limit),
      over_limit: over_limit,
      total_text: total_text(used, limit),
      usage_text: usage_text(used, limit, over_limit),
      bar_width: bar_width(used, limit)
    }
  end

  defp usage_row(limited, count, limit) do
    over_limit = over_limit(count, limit)

    %{
      key: limited,
      label: limited_label(limited),
      context: context(limited),
      count: count,
      limit_text: limit_text(limit),
      over_limit: over_limit,
      total_text: total_text(count, limit),
      usage_text: usage_text(count, limit, over_limit),
      bar_width: bar_width(count, limit)
    }
  end

  @doc """
  Returns the human label for a thing the plans limit.
  """
  @spec limited_label(PlanCatalog.limited()) :: String.t()
  def limited_label(:bank_institutions), do: gettext("Banks")
  def limited_label(:users), do: gettext("Users")
  def limited_label(:active_projects), do: gettext("Projects")

  defp context(:bank_institutions), do: gettext("Banks with at least one synchronized account.")
  defp context(:users), do: gettext("Active people in the organization, including the owner.")
  defp context(:active_projects), do: gettext("Projects that are not archived.")

  defp over_limit(_count, :unlimited), do: 0
  defp over_limit(count, limit), do: max(count - limit, 0)

  @doc """
  Returns what a purchase of a plan charges and when: the first purchase starts with a 60-day
  trial (`trial?`), a returning company pays at once.
  """
  @spec first_charge_text(PlanCatalog.offered_plan(), PlanCatalog.billing_period(), boolean()) ::
          String.t()
  def first_charge_text(plan, :monthly, true = _trial?) do
    gettext("Free for 60 days, then %{amount} gross every month.",
      amount: format_money(PlanCatalog.gross_price_pln(plan, :monthly))
    )
  end

  def first_charge_text(plan, :yearly, true = _trial?) do
    gettext("Free for 60 days, then %{amount} gross once a year.",
      amount: format_money(PlanCatalog.gross_price_pln(plan, :yearly))
    )
  end

  def first_charge_text(plan, :monthly, false = _trial?) do
    gettext("You pay %{amount} gross now, then every month.",
      amount: format_money(PlanCatalog.gross_price_pln(plan, :monthly))
    )
  end

  def first_charge_text(plan, :yearly, false = _trial?) do
    gettext("You pay %{amount} gross now, then once a year.",
      amount: format_money(PlanCatalog.gross_price_pln(plan, :yearly))
    )
  end

  @doc """
  Returns how many of a limited thing a plan includes, as text.
  """
  @spec limit_text(PlanCatalog.limit()) :: String.t()
  def limit_text(:unlimited), do: gettext("unlimited")
  def limit_text(limit), do: Integer.to_string(limit)

  defp total_text(count, :unlimited), do: Integer.to_string(count)
  defp total_text(count, limit), do: "#{count} / #{limit}"

  defp usage_text(_count, :unlimited, _over_limit), do: nil
  defp usage_text(_count, _limit, over_limit) when over_limit > 0, do: gettext("Limit exceeded")

  defp usage_text(count, limit, _over_limit), do: gettext("%{count} remaining", count: limit - count)

  # A bar needs a limit to fill up to; an unlimited row has none.
  defp bar_width(_count, :unlimited), do: nil
  defp bar_width(0, 0), do: 0
  defp bar_width(_count, 0), do: 100
  defp bar_width(count, limit), do: min(trunc(count / limit * 100), 100)
end
