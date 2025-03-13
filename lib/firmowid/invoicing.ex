defmodule Firmowid.Invoicing do
  alias Firmowid.Accounts.User
  alias Akin
  alias OpenAI

  alias Firmowid.CostInvoices
  alias Firmowid.Finances
  alias Firmowid.SalesInvoices

  alias Firmowid.SalesInvoices.SalesInvoice
  alias Firmowid.CostInvoices.CostInvoice
  alias Firmowid.Finances.Transaction

  require Logger

  alias Firmowid.Repo
  import Ecto.Query, warn: false

  @behaviour Bodyguard.Policy

  def authorize(_, %User{role: :admin}, _), do: true

  def authorize(_, _, _), do: false

  @doc """
  Returns all months with invoicing entries - so all months where Firmowid can function.
  Useful e.g. for the invoicing live view's date picker.
  """
  def get_all_months_with_invoicing_entries() do
    transactions_query =
      from(t in Transaction,
        select: %{
          date_string:
            fragment(
              "date_trunc('month', ?)",
              t.booking_date
            ),
          organization_id: t.organization_id
        }
      )

    sales_invoices_query =
      from(si in Firmowid.SalesInvoices.SalesInvoice,
        select: %{
          date_string:
            fragment(
              "date_trunc('month', ?)",
              si.issue_date
            ),
          organization_id: si.organization_id
        }
      )

    cost_invoices_query =
      from(ci in Firmowid.CostInvoices.CostInvoice,
        select: %{
          date_string:
            fragment(
              "date_trunc('month', ?)",
              ci.issue_date
            ),
          organization_id: ci.organization_id
        }
      )

    union_query =
      transactions_query
      |> union(^sales_invoices_query)
      |> union(^cost_invoices_query)

    from(u in subquery(union_query),
      select: %{
        date: u.date_string
      },
      distinct: true
    )
    |> Repo.all()
    |> Enum.map(& &1.date)
  end

  def get_invoicing_entries(from, to, filter) do
    case filter do
      :all ->
        Enum.concat([
          CostInvoices.list_cost_invoices(from, to),
          SalesInvoices.list_sales_invoices(from, to),
          Finances.list_transactions(from, to)
        ])
        |> order_entries_for_display()

      :unmatched ->
        Enum.concat([
          CostInvoices.list_unmatched_cost_invoices(from, to),
          SalesInvoices.list_unmatched_sales_invoices(from, to),
          Finances.list_unmatched_transactions(from, to)
        ])
        |> order_entries_for_display()

      :invoices ->
        Enum.concat(
          CostInvoices.list_cost_invoices(from, to),
          SalesInvoices.list_sales_invoices(from, to)
        )
        |> order_entries_for_display()

      :transactions ->
        Finances.list_transactions(from, to)
        |> order_entries_for_display()
    end
  end

  defp get_date(%SalesInvoice{} = invoice) do
    invoice.issue_date
  end

  defp get_date(%CostInvoice{} = invoice) do
    invoice.issue_date
  end

  defp get_date(%Transaction{} = transaction) do
    transaction.booking_date
  end

  def order_entries_for_display(invoicing_entries) do
    order_by_date = fn a, b ->
      a_date = get_date(a)
      b_date = get_date(b)

      case Date.compare(a_date, b_date) do
        :gt ->
          true

        :lt ->
          false

        :eq ->
          a.id < b.id
      end
    end

    invoicing_entries
    |> Enum.sort_by(& &1, order_by_date)
  end

  defp get_potential_transactions_for_invoice(
         issue_date,
         due_date,
         currency,
         total_amount,
         seller,
         opts
       ) do
    opts =
      Keyword.validate!(opts,
        similarity_threshold: 0.1,
        amount_lower_bound: 0.9,
        amount_upper_bound: 1.1,
        max_results: 5,
        days_before: 3,
        days_after: 6
      )

    similarity_threshold = Keyword.fetch!(opts, :similarity_threshold)
    max_results = Keyword.fetch!(opts, :max_results)

    amount_lower_bound = Keyword.fetch!(opts, :amount_lower_bound)
    amount_upper_bound = Keyword.fetch!(opts, :amount_upper_bound)

    days_before = Keyword.fetch!(opts, :days_before)
    days_after = Keyword.fetch!(opts, :days_after)

    rates =
      case Money.ExchangeRates.historic_rates(issue_date) do
        {:ok, rates} ->
          {:ok, rates}

        # fallback to some hardcoded rates if OpenExchange API is not
        # available (like Bartek running dev on it and using our quota)
        _ ->
          {:ok,
           %{
             EUR: Decimal.new("0.9"),
             PLN: Decimal.new("4.2"),
             USD: Decimal.new("1.1")
           }}
      end

    {:ok, amount} =
      Money.to_currency(
        Money.new(
          currency,
          total_amount
        ),
        "PLN",
        rates
      )

    amount = amount |> Money.to_decimal()

    {min_amount, max_amount} =
      {
        Decimal.mult(amount, Decimal.from_float(amount_lower_bound)),
        Decimal.mult(amount, Decimal.from_float(amount_upper_bound))
      }

    # date range -> between issue_date and payment_deadline
    issue_date = issue_date |> Date.add(-days_before)
    payment_deadline = due_date |> Date.add(days_after)

    unmatched_transactions =
      Finances.list_unmatched_transactions(issue_date, payment_deadline)

    # transactions with exact amount (or in the range for non-PLN)
    # that are between issue_date and payment_deadline
    candidates =
      unmatched_transactions
      |> Enum.filter(fn i ->
        {:ok, transaction_amount_in_pln} =
          Money.to_currency(
            Money.new(
              i.transaction_currency,
              i.transaction_amount
            ),
            "PLN",
            rates
          )

        transaction_amount =
          transaction_amount_in_pln
          |> Money.to_decimal()

        decimal_between?(min_amount, max_amount, transaction_amount)
      end)

    # use Jaro-Winkler name similarity to check if seller matches
    candidates
    |> Enum.map(fn candidate_transaction ->
      similarity =
        Akin.compare(candidate_transaction.creditor_name, seller).jaro_winkler

      {candidate_transaction, similarity}
    end)
    |> Enum.filter(fn {_candidate, similarity} ->
      similarity >= similarity_threshold
    end)
    |> Enum.sort_by(fn {_candidate, similarity} -> similarity end, :desc)
    |> Enum.map(fn {candidate, _similarity} -> candidate end)
    |> Enum.take(max_results)
  end

  def get_potential_transactions_for_sales_invoice(sales_invoice, opts \\ []) do
    get_potential_transactions_for_invoice(
      sales_invoice.issue_date,
      sales_invoice.due_date,
      sales_invoice.currency,
      SalesInvoice.get_gross_value(sales_invoice),
      sales_invoice.seller_display_name,
      opts
    )
  end

  def get_potential_transactions_for_cost_invoice(cost_invoice, opts \\ []) do
    get_potential_transactions_for_invoice(
      cost_invoice.issue_date,
      cost_invoice.due_date,
      cost_invoice.currency,
      cost_invoice.total_amount,
      cost_invoice.seller_display_name,
      opts
    )
  end

  defp decimal_between?(min, max, value) do
    cond do
      # when amount is positive (sales)
      Decimal.compare(value, 0) == :gt ->
        Decimal.compare(value, min) != :lt and
          Decimal.compare(value, max) != :gt

      # when amount is negative (costs)
      true ->
        Decimal.compare(value, max) != :lt and Decimal.compare(value, min) != :gt
    end
  end

  def match_with_transaction_combo(
        issue_date,
        due_date,
        total_amount
      ) do
    # when there are multiple transactions on the same invoice
    # typically - services / goods that you get across the month

    # highly experimental!

    issue_date = issue_date |> Date.add(-35)
    due_date = due_date |> Date.add(7)

    all_found =
      Finances.list_unmatched_transactions(issue_date, due_date)
      |> Enum.group_by(
        &%{
          creditor_name: &1.creditor_name,
          year_month: "#{&1.booking_date.year}-#{&1.booking_date.month}"
        }
      )
      |> Enum.map(fn
        {%{creditor_name: creditor_name, year_month: year_month}, transactions} ->
          %{
            id: UUIDv7.generate(),
            creditor_name: creditor_name,
            year_month: year_month,
            total_amount:
              Enum.reduce(transactions, Decimal.new(0), fn t, acc ->
                Decimal.add(t.transaction_amount, acc)
              end),
            currency: Enum.at(transactions, 0).transaction_currency,
            transactions: transactions
          }
      end)

    result =
      all_found
      |> Enum.filter(fn %{
                          total_amount: group_total_amount,
                          transactions: transactions
                        } ->
        is_amount_equal = Decimal.compare(group_total_amount, total_amount) == :eq
        is_a_group = length(transactions) > 1

        is_amount_equal and is_a_group
      end)

    # if we have multiple groups this means something went wrong :)
    case result do
      [%{transactions: transactions}] -> transactions
      _ -> nil
    end
  end

  def match_all_good_candidates_for_unconnected_cost_invoices(organization_id) do
    for similarity_threshold <- [0.9, 0.8, 0] do
      cost_invoices = CostInvoices.list_unmatched_cost_invoices()

      if similarity_threshold == 0 do
        cost_invoices
        |> Enum.map(fn cost_invoice ->
          {cost_invoice,
           get_potential_transactions_for_cost_invoice(
             cost_invoice,
             similarity_threshold: similarity_threshold,
             max_results: 5
           )}
        end)
        |> Enum.each(fn {cost_invoice, candidates} ->
          matches =
            llm_re_grade_matches(
              cost_invoice.invoice_identifier,
              cost_invoice.description,
              cost_invoice.issue_date,
              cost_invoice.total_amount,
              cost_invoice.currency,
              cost_invoice.seller,
              candidates
              |> Enum.map(
                &Map.merge(
                  &1,
                  %{party_name: &1.creditor_name}
                )
              )
            )
            |> Enum.filter(fn {_transaction, grade} -> grade >= 0.8 end)
            |> Enum.map(fn {transaction, _grade} -> transaction end)

          if length(matches) == 1 do
            [match] = matches

            CostInvoices.create_cost_invoices_transactions_connection(
              cost_invoice.id,
              match.id,
              organization_id
            )
          end
        end)
      else
        cost_invoices
        |> Enum.map(fn cost_invoice ->
          {cost_invoice,
           get_potential_transactions_for_cost_invoice(
             cost_invoice,
             similarity_threshold: similarity_threshold,
             max_results: 5
           )}
        end)
        |> Enum.each(fn
          {cost_invoice, [golden_candidate]} ->
            CostInvoices.create_cost_invoices_transactions_connection(
              cost_invoice.id,
              golden_candidate.id,
              organization_id
            )

          _ ->
            nil
        end)
      end
    end

    cost_invoices = CostInvoices.list_unmatched_cost_invoices()

    cost_invoices
    |> Enum.each(fn cost_invoice ->
      combo_matches =
        match_with_transaction_combo(
          cost_invoice.issue_date,
          cost_invoice.due_date,
          cost_invoice.total_amount
        )

      case combo_matches do
        nil ->
          nil

        transactions ->
          Enum.each(transactions, fn transaction ->
            CostInvoices.create_cost_invoices_transactions_connection(
              cost_invoice.id,
              transaction.id,
              organization_id
            )
          end)
      end
    end)
  end

  def match_all_good_candidates_for_unconnected_sales_invoices(organization_id) do
    for similarity_threshold <- [0.9, 0.8, 0] do
      sales_invoices = SalesInvoices.list_unmatched_sales_invoices()

      if similarity_threshold == 0 do
        sales_invoices
        |> Enum.map(fn sales_invoice ->
          {sales_invoice,
           get_potential_transactions_for_sales_invoice(
             sales_invoice,
             similarity_threshold: similarity_threshold,
             max_results: 5
           )}
        end)
        |> Enum.each(fn {sales_invoice, candidates} ->
          sales_invoice_description =
            case sales_invoice.sales_invoice_items == [] do
              true -> "N/A"
              false -> sales_invoice.sales_invoice_items |> Enum.at(0) |> Map.get(:name)
            end

          matches =
            llm_re_grade_matches(
              sales_invoice.invoice_number,
              sales_invoice_description,
              sales_invoice.issue_date,
              SalesInvoices.SalesInvoice.get_gross_value(sales_invoice),
              sales_invoice.currency,
              SalesInvoices.get_full_buyer_data_as_single_string(sales_invoice),
              candidates
              |> Enum.map(
                &Map.merge(
                  &1,
                  %{party_name: &1.debtor_name}
                )
              )
            )
            |> Enum.filter(fn {_transaction, grade} -> grade >= 0.8 end)
            |> Enum.map(fn {transaction, _grade} -> transaction end)

          if length(matches) == 1 do
            [match] = matches

            SalesInvoices.create_sales_invoices_transactions_connection(
              sales_invoice.id,
              match.id,
              organization_id
            )
          end
        end)
      else
        sales_invoices
        |> Enum.map(fn sales_invoice ->
          {sales_invoice,
           get_potential_transactions_for_sales_invoice(
             sales_invoice,
             similarity_threshold: similarity_threshold,
             max_results: 5
           )}
        end)
        |> Enum.each(fn
          {sales_invoice, [golden_candidate]} ->
            SalesInvoices.create_sales_invoices_transactions_connection(
              sales_invoice.id,
              golden_candidate.id,
              organization_id
            )

          _ ->
            nil
        end)
      end
    end

    sales_invoices = SalesInvoices.list_unmatched_sales_invoices()

    sales_invoices
    |> Enum.each(fn sales_invoice ->
      combo_matches =
        match_with_transaction_combo(
          sales_invoice.issue_date,
          sales_invoice.due_date,
          SalesInvoices.SalesInvoice.get_gross_value(sales_invoice)
        )

      case combo_matches do
        nil ->
          nil

        transactions ->
          Enum.each(transactions, fn transaction ->
            SalesInvoices.create_sales_invoices_transactions_connection(
              sales_invoice.id,
              transaction.id,
              organization_id
            )
          end)
      end
    end)
  end

  def llm_re_grade_matches(
        invoice_identifier,
        description,
        issue_date,
        total_amount,
        currency,
        party,
        candidates
      ) do
    candidates
    # run calls for each candidate in parallel
    |> Enum.map(
      &Task.async(fn ->
        {&1,
         call_llm_for_grade(
           invoice_identifier,
           description,
           issue_date,
           total_amount,
           currency,
           party,
           &1
         )}
      end)
    )
    |> Enum.map(&Task.await/1)
  end

  def call_llm_for_grade(
        invoice_identifier,
        description,
        issue_date,
        total_amount,
        currency,
        party,
        transaction
      ) do
    call_with_retry(&do_call_llm_for_grade/7, [
      invoice_identifier,
      description,
      issue_date,
      total_amount,
      currency,
      party,
      transaction
    ])
  end

  def do_call_llm_for_grade(
        invoice_identifier,
        description,
        issue_date,
        total_amount,
        currency,
        party,
        transaction
      ) do
    {:ok, response} =
      OpenAI.chat_completion(
        model: "gpt-4o-mini",
        max_completion_tokens: 20,
        response_format: %{
          type: "json_schema",
          json_schema: %{
            name: "grading_response",
            strict: true,
            schema: %{
              type: "object",
              properties: %{
                grade: %{
                  type: "number",
                  additionalProperties: false
                }
              },
              required: ["grade"],
              additionalProperties: false
            }
          }
        },
        messages: [
          %{
            role: "system",
            content:
              "You are a assistant to a finance person. You help matching between cost invoices and transactions, to complete the paper trail."
          },
          %{
            role: "user",
            content: "
              This is the metadata of an invoice I want to match:
              {
                invoice_identifier: #{invoice_identifier},
                description: #{description},
                issue_date: #{issue_date},
                total_amount: #{total_amount},
                currency: #{currency},
                party: #{party},
              }

              Here is a transaction that I selected as possible match:
              {
                booking_date: #{transaction.booking_date},
                value_date: #{transaction.value_date},
                transaction_currency: #{transaction.transaction_currency},
                transaction_amount: #{transaction.transaction_amount},
                party_name: #{transaction.party_name},
                remittance_information_unstructured: #{transaction.remittance_information_unstructured},
              }

              Considering  metadata of them and the metadata of the cost invoice,
              please give me a score between 0 and 1 (so if it's 30% chance of matching, it should be 0.3).
              Take into consideration whether the name of party on the invoice matches the one in the
              transactions, dates and if the amount matches. Also look at the
              description of the invoice.

              Reply only with the score.
            " |> String.trim()
          }
        ]
      )

    grade =
      response.choices
      |> List.first()
      |> Map.get("message")
      |> Map.get("content")
      |> Jason.decode!()
      |> Map.get("grade")

    grade
  end

  defp call_with_retry(call_fn, args, opts \\ []) do
    max_retries = Keyword.get(opts, :max_retries, 10)
    base_delay = Keyword.get(opts, :base_delay, 500)
    max_delay = Keyword.get(opts, :max_delay, 5000)

    do_call_with_retry(call_fn, args, max_retries, base_delay, max_delay)
  end

  defp do_call_with_retry(call_fn, args, retries_left, current_delay, max_delay)
       when retries_left > 0 do
    try do
      apply(call_fn, args)
    rescue
      reason ->
        if retries_left > 1 do
          # Calculate next delay with exponential backoff and jitter
          next_delay = calculate_delay(current_delay, max_delay)

          Logger.warning(fn ->
            "LLM call failed. Retrying in #{next_delay}ms. Reason: #{inspect(reason)}. Retries left: #{retries_left - 1}"
          end)

          :timer.sleep(next_delay)

          do_call_with_retry(call_fn, args, retries_left - 1, next_delay, max_delay)
        else
          # Last attempt
          apply(call_fn, args)
        end
    end
  end

  defp do_call_with_retry(_call_fn, _args, 0, _current_delay, _max_delay) do
    {:error, :max_retries_exceeded}
  end

  # Exponential backoff with jitter
  defp calculate_delay(current_delay, max_delay) do
    next_delay = min(current_delay * 2, max_delay)
    next_delay + :rand.uniform(100)
  end
end
