defmodule Checks.RejectDirectHistoryRates do
  @moduledoc """
  A Credo rule that disallows direct calls to `Money.ExchangeRates.historic_rates/1`.

  ## What this rule does

  This rule prevents direct usage of `Money.ExchangeRates.historic_rates/1` function
  and encourages using `Firmowid.Ash.Currencies.Converter` module instead.

  ## Example

      # Bad
      Money.ExchangeRates.historic_rates(date)

      # Good
      Firmowid.Ash.Currencies.Converter.normalize_amount_to_pln(amount, currency, date)
  """

  use Credo.Check, base_priority: :higher, category: :warning

  @impl true
  def run(%SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    Credo.Code.prewalk(source_file, &traverse(&1, &2, [], issue_meta))
  end

  # Match function calls to Money.ExchangeRates.historic_rates
  defp traverse(
         {{:., _, [{:__aliases__, _, [:Money, :ExchangeRates]}, :historic_rates]}, meta, _args} = ast,
         issues,
         _,
         issue_meta
       ) do
    {ast, issues ++ [issue_for(:historic_rates, meta[:line], issue_meta)]}
  end

  # Match aliased calls (if Money.ExchangeRates is aliased as ExchangeRates)
  defp traverse(
         {{:., _, [{:__aliases__, _, [:ExchangeRates]}, :historic_rates]}, meta, _args} = ast,
         issues,
         _,
         issue_meta
       ) do
    {ast, issues ++ [issue_for(:historic_rates, meta[:line], issue_meta)]}
  end

  defp traverse(ast, issues, _, _issue_meta), do: {ast, issues}

  defp issue_for(trigger, line_no, issue_meta) do
    format_issue(
      issue_meta,
      message:
        "Do not call Money.ExchangeRates.historic_rates/1 directly. Use Firmowid.Ash.Currencies.Converter instead.",
      line_no: line_no,
      trigger: trigger
    )
  end
end
