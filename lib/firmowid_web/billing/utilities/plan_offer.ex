defmodule FirmowidWeb.Billing.Utilities.PlanOffer do
  @moduledoc """
  What each offered plan includes, as the pricing page and the subscription settings compare the
  plans: who a plan is for, the rows that set the plans apart and every feature by section.

  A row is its label and one value per plan, in the order of `plans/0`. A value is the text shown
  for the plan, or whether the plan includes the feature. The limits and the features that only
  some plans include come from `Firmowid.Billing.PlanCatalog`, which the app enforces.
  """

  use Gettext, backend: Firmowid.Gettext

  alias Firmowid.Billing.PlanCatalog

  @type value :: String.t() | boolean()
  @type row :: {String.t(), [value()]}

  @plans [:free, :przedsiebiorca, :firma]

  @audiences %{
    free: gettext_noop("For everyone who issues invoices in KSeF"),
    przedsiebiorca: gettext_noop("For sole traders with several accounts and small teams"),
    firma: gettext_noop("For service companies with 6–20 people")
  }

  @key_rows [
    {gettext_noop("Users"), :users},
    {gettext_noop("Bank accounts"), :bank_institutions},
    {gettext_noop("Time tracking"),
     [gettext_noop("up to 3 projects"), gettext_noop("unlimited"), gettext_noop("unlimited")]},
    {gettext_noop("Leave requests with approval"), :leave_requests}
  ]

  @sections [
    {gettext_noop("Invoices and KSeF"),
     [
       {gettext_noop("Sales invoices"),
        [gettext_noop("unlimited"), gettext_noop("unlimited"), gettext_noop("unlimited")]},
       {gettext_noop("KSeF: sending invoices and downloading purchases"),
        [gettext_noop("unlimited"), gettext_noop("unlimited"), gettext_noop("unlimited")]},
       {gettext_noop("Clear invoice wizard"), [true, true, true]},
       {gettext_noop("Customer database with cooperation statistics"), [true, true, true]},
       {gettext_noop("Invoices in 33 currencies"), [true, true, true]},
       {gettext_noop("Reverse charge for EU customers (automatic)"), [true, true, true]},
       {gettext_noop("ZIP package for your accountant"), [true, true, true]},
       {gettext_noop("Document OCR"), :monthly_ocr_documents}
     ]},
    {gettext_noop("Banking and payments"), [{gettext_noop("Email notifications"), :ksef_invoice_emails}]},
    {gettext_noop("Team and working time"),
     [
       {gettext_noop("Project cost"), [true, true, true]},
       {gettext_noop("PDF time tracking and payroll report"), [true, true, true]}
     ]},
    {gettext_noop("HR"),
     [
       {gettext_noop("Employee contracts and documents"), :employee_contracts},
       {gettext_noop("Business trips"), :delegations}
     ]},
    {gettext_noop("ChatGPT and integrations"),
     [
       {gettext_noop("Integration with AI assistants (Claude, ChatGPT, Cursor, Grok and others)"), :mcp},
       {gettext_noop("Assistant in the app"), :assistant},
       {gettext_noop("API keys"), [true, true, true]}
     ]},
    {gettext_noop("Data and security"), [{gettext_noop("Self-host, open source (AGPL-3.0)"), [true, true, true]}]}
  ]

  @doc "Returns the offered plans, cheapest first: the order of every row's values."
  @spec plans() :: [PlanCatalog.offered_plan()]
  def plans, do: @plans

  @doc "Returns who a plan is for."
  @spec audience(PlanCatalog.offered_plan()) :: String.t()
  def audience(plan), do: Gettext.gettext(Firmowid.Gettext, Map.fetch!(@audiences, plan))

  @doc "Returns the rows that set the plans apart at a glance."
  @spec key_rows() :: [row()]
  def key_rows, do: localize(@key_rows)

  @doc "Returns every feature of the plans, by titled section."
  @spec sections() :: [{String.t(), [row()]}]
  def sections do
    Enum.map(@sections, fn {title, rows} ->
      {Gettext.gettext(Firmowid.Gettext, title), localize(rows)}
    end)
  end

  @doc """
  Returns the rows that count something a higher plan gives more of, such as users.
  """
  @spec quotas() :: [row()]
  def quotas, do: Enum.filter(rows(), &quota?/1)

  @doc """
  Returns the features a plan adds to the cheaper one; for the cheapest plan, what every plan
  includes. A value is `true`, or the text that goes with the feature.
  """
  @spec added(PlanCatalog.offered_plan()) :: [{String.t(), value()}]
  def added(plan) do
    index = Enum.find_index(@plans, &(&1 == plan))

    for {label, values} = row <- rows(),
        not quota?(row),
        {value, cheaper} = {Enum.at(values, index), index > 0 and Enum.at(values, index - 1)},
        value != false and cheaper == false,
        do: {label, value}
  end

  defp rows, do: key_rows() ++ Enum.flat_map(sections(), fn {_title, rows} -> rows end)

  # A quota is told in words for every plan, and not the same words.
  defp quota?({_label, values}), do: Enum.all?(values, &is_binary/1) and length(Enum.uniq(values)) > 1

  defp localize(rows) do
    Enum.map(rows, fn {label, values} ->
      {Gettext.gettext(Firmowid.Gettext, label), values(values)}
    end)
  end

  # A limit or a feature reads its per-plan value from the billing catalog.
  defp values(key) when is_atom(key), do: Enum.map(@plans, &catalog_value(PlanCatalog.plan!(&1), key))

  defp values(values) do
    Enum.map(values, fn
      value when is_boolean(value) -> value
      value -> Gettext.gettext(Firmowid.Gettext, value)
    end)
  end

  defp catalog_value(%{monthly_ocr_documents: :unlimited}, :monthly_ocr_documents), do: gettext("unlimited")

  defp catalog_value(%{monthly_ocr_documents: limit}, :monthly_ocr_documents),
    do: ngettext("%{count} document", "%{count} documents", limit)

  defp catalog_value(%{limits: limits}, limited) when is_map_key(limits, limited) do
    case limits[limited] do
      :unlimited -> gettext("unlimited")
      limit -> Integer.to_string(limit)
    end
  end

  defp catalog_value(%{features: features}, feature), do: feature in features
end
