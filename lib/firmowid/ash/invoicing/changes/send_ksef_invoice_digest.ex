defmodule Firmowid.Ash.Invoicing.Changes.SendKsefInvoiceDigest do
  @moduledoc """
  Delivers a persisted KSeF invoice digest to all active organization admins.

  The digest is marked as delivered only when every recipient email succeeds.
  """
  use Ash.Resource.Change

  alias Ash.Error.Changes.InvalidAttribute
  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Invoicing.Digests.Email
  alias Firmowid.Ash.Invoicing.InvoiceMatching
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor
  alias Firmowid.ErrorKind

  require Logger

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      digest = changeset.data
      actor = %SystemActor{org_id: digest.organization_id, role: :ksef_digest}

      digest =
        Ash.load!(digest, [:organization, cost_invoices: [:effective_amount, :transactions]],
          tenant: digest.organization_id,
          actor: actor
        )

      selected_admin_user_ids = Ash.Changeset.get_argument(changeset, :admin_user_ids)

      admins =
        %{status: :active, role: :admin}
        |> Core.list_users!(
          tenant: digest.organization_id,
          actor: actor
        )
        |> maybe_filter_admins(selected_admin_user_ids)

      log_digest_delivery_attempt(digest, admins, selected_admin_user_ids)

      cond do
        admins == [] ->
          Ash.Changeset.add_error(
            changeset,
            InvalidAttribute.exception(
              field: :delivered_at,
              message: "cannot send KSeF digest without recipients"
            )
          )

        digest.cost_invoices == [] ->
          Ash.Changeset.add_error(
            changeset,
            InvalidAttribute.exception(
              field: :delivered_at,
              message: "cannot send KSeF digest without persisted invoices"
            )
          )

        true ->
          invoice_summaries =
            build_invoice_summaries(digest.cost_invoices, hd(admins), digest.organization_id)

          case deliver_to_admins(admins, digest, invoice_summaries) do
            :ok ->
              Ash.Changeset.force_change_attribute(changeset, :delivered_at, DateTime.utc_now())

            {:error, failures} ->
              Ash.Changeset.add_error(
                changeset,
                InvalidAttribute.exception(
                  field: :delivered_at,
                  message: Enum.map_join(failures, "; ", &format_failure/1)
                )
              )
          end
      end
    end)
  end

  defp maybe_filter_admins(admins, nil), do: admins

  defp maybe_filter_admins(admins, admin_user_ids) do
    Enum.filter(admins, &(&1.id in admin_user_ids))
  end

  defp log_digest_delivery_attempt(digest, admins, selected_admin_user_ids) do
    Logger.info(
      "Sending KSeF digest for organization_id=#{digest.organization_id} " <>
        "invoice_count=#{length(digest.cost_invoices)}"
    )

    Logger.info("Digest contains #{length(digest.cost_invoices)} invoice(s) in the selected window")

    Logger.info("Digest recipients admin_count=#{length(admins)} admin_ids=#{inspect(Enum.map(admins, & &1.id))}")

    if selected_admin_user_ids do
      Logger.info("Digest recipient filter admin_user_ids=#{inspect(selected_admin_user_ids)}")
    end
  end

  defp deliver_to_admins(admins, digest, invoice_summaries) do
    failures =
      admins
      |> Enum.map(fn admin ->
        case Email.deliver_ksef_invoice_digest(
               admin,
               digest,
               digest.cost_invoices,
               invoice_summaries: invoice_summaries
             ) do
          {:ok, _email} -> nil
          {:error, reason} -> {admin.id, ErrorKind.classify(reason)}
        end
      end)
      |> Enum.reject(&is_nil/1)

    if failures == [], do: :ok, else: {:error, failures}
  end

  defp build_invoice_summaries(invoices, admin, organization_id) do
    scope = %Scope{actor: admin, tenant: organization_id}

    Map.new(invoices, fn invoice ->
      suggestions = InvoiceMatching.get_potential_transactions_for_invoice(invoice, scope)

      {invoice.id,
       %{
         suggestions_count: length(suggestions),
         top_prediction_score: top_prediction_score(suggestions),
         top_suggestions: top_suggestions(suggestions),
         amount_placeholder: amount_placeholder(invoice),
         matched?: matched_invoice?(invoice)
       }}
    end)
  end

  defp top_prediction_score([]), do: nil
  defp top_prediction_score([{_transaction, score} | _rest]), do: score

  defp top_suggestions(suggestions) do
    suggestions
    |> Enum.take(3)
    |> Enum.map(fn {transaction, score} ->
      %{
        score: score,
        booking_date_label: booking_date_label(transaction.booking_date),
        avatar_label: suggestion_avatar_label(transaction),
        avatar_color: suggestion_avatar_color(transaction)
      }
    end)
  end

  defp booking_date_label(nil), do: "bez daty"

  defp booking_date_label(%Date{} = booking_date) do
    case Date.diff(Date.utc_today(), booking_date) do
      0 -> "dzisiaj"
      1 -> "wczoraj"
      days when days > 1 -> "#{days} dni temu"
      _ -> Date.to_iso8601(booking_date)
    end
  end

  defp suggestion_avatar_label(transaction) do
    transaction
    |> suggestion_name()
    |> String.trim()
    |> case do
      "" -> "?"
      name -> name |> String.first() |> String.upcase()
    end
  end

  defp suggestion_avatar_color(transaction) do
    palette = ["#D0E6CE", "#F4D5C6", "#D9E7F7", "#E6D8F5", "#F4E7C6", "#D6ECE7"]
    name = suggestion_name(transaction)
    Enum.at(palette, :erlang.phash2(name, length(palette)))
  end

  defp suggestion_name(transaction) do
    bank_account = Map.get(transaction, :bank_account)

    Enum.find(
      [
        present_binary(if is_map(bank_account), do: Map.get(bank_account, :institution_name)),
        present_binary(if is_map(bank_account), do: Map.get(bank_account, :name)),
        present_binary(Map.get(transaction, :creditor_name)),
        present_binary(Map.get(transaction, :debtor_name)),
        "?"
      ],
      &(not is_nil(&1))
    )
  end

  defp present_binary(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present_binary(_value), do: nil

  defp matched_invoice?(invoice) do
    invoice
    |> Map.get(:transactions, [])
    |> Enum.any?()
  end

  defp amount_placeholder(invoice) do
    currency = invoice_currency(invoice)

    case currency do
      "PLN" -> "•••• zł"
      nil -> "••••"
      value -> "•••• #{value}"
    end
  end

  defp invoice_currency(invoice) do
    invoice
    |> Map.get(:effective_amount)
    |> case do
      %Money{currency: currency} -> to_string(currency)
      _ -> nil
    end
  end

  defp format_failure({admin_id, reason_kind}), do: "admin_id=#{admin_id}: error_kind=#{reason_kind}"
end
