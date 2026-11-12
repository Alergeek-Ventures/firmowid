defmodule FirmowidWeb.Assistant.Utilities.Changes do
  @moduledoc """
  What a proposed write changes, for its approval card: the records it touches and each field
  before and after, read with the user's permissions. Covers the writes whose effect the record
  rows alone do not show.

  A malformed call or a record the user cannot read gives `:error`, and a profile or draft update
  that changes nothing gives `:unchanged`: either way the card stays rejectable but not
  approvable.
  """
  use Gettext, backend: Firmowid.Gettext

  alias Ash.Error.Forbidden
  alias Ash.Error.Invalid
  alias Ash.Resource.Info
  alias Firmowid.Analysis.TagDefinition
  alias Firmowid.Core
  alias Firmowid.Finances
  alias Firmowid.Invoicing
  alias Firmowid.Invoicing.SalesInvoice
  alias Firmowid.Invoicing.SalesInvoice.Preview
  alias Firmowid.Ksef.VatRate
  alias Firmowid.Scope
  alias Firmowid.Timetracker.Project
  alias Firmowid.Timetracker.Session
  alias FirmowidWeb.Invoicing.Utilities.VatExemption
  alias FirmowidWeb.Timetracker.Utilities.LeavePresentation

  # Session times are shown in the app's default time zone; the assistant has no browser zone.
  @timezone "Europe/Warsaw"

  @entity_kinds %{
    "sales_invoice" => :sales,
    "cost_invoice" => :cost,
    "transaction" => :transaction
  }
  @note_kinds %{
    "update_sales_invoice_internal_note" => :sales,
    "update_cost_invoice_internal_note" => :cost,
    "update_transaction_internal_note" => :transaction
  }
  @categories %{"company" => :company, "taxes" => :taxes, "internal" => :internal}
  @leave_reasons %{"indisposition" => :indisposition, "rest" => :rest, "other" => :other}

  @tools Map.keys(@note_kinds) ++
           ~w(connect_transaction_salary disconnect_transaction_salary set_analysis_entry_category
              set_analysis_entry_project_tags start_session stop_current_session edit_session add_sessions
              create_leave_request update_profile create_sales_invoice_draft update_sales_invoice_draft)

  @type record_ref :: {atom(), String.t()}
  @type change :: %{label: String.t(), from: String.t() | nil, to: String.t() | nil}

  @doc "Whether the tool's approval card shows field changes."
  @spec covers?(String.t()) :: boolean()
  def covers?(name), do: name in @tools

  @doc "Returns the records a covered write touches and its field changes."
  @spec preview(map(), Scope.t()) :: {:ok, [record_ref()], [change()]} | :error | :unchanged
  def preview(%{name: name, arguments: arguments}, scope) do
    case preview(name, arguments, scope) do
      {:ok, references, changes} -> {:ok, references, Enum.filter(changes, & &1)}
      failure -> failure
    end
  end

  defp preview(name, %{"id" => id, "input" => %{"internal_note" => note}}, scope) when is_map_key(@note_kinds, name) do
    kind = Map.fetch!(@note_kinds, name)

    with {:ok, note} <- text(note),
         {:ok, record} <- read(kind, id, scope) do
      {:ok, [{kind, id}], [change(gettext("Internal note"), record.internal_note, note)]}
    end
  end

  defp preview("connect_transaction_salary", %{"id" => id, "input" => input}, scope) do
    with %{"salary_user_id" => user_id, "salary_month" => month} <- input,
         {:ok, month} <- parse(&Date.from_iso8601/1, month),
         {:ok, transaction} <- read(:transaction, id, scope),
         {:ok, before} <- salary(transaction, scope),
         {:ok, later} <- salary(user_id, month, scope) do
      {:ok, [{:transaction, id}], [change(gettext("Salary"), before, later)]}
    else
      _invalid -> :error
    end
  end

  defp preview("disconnect_transaction_salary", %{"id" => id}, scope) do
    with {:ok, transaction} <- read(:transaction, id, scope),
         {:ok, before} <- salary(transaction, scope) do
      {:ok, [{:transaction, id}], [change(gettext("Salary"), before, nil)]}
    end
  end

  defp preview("set_analysis_entry_category", %{"input" => input}, scope) do
    with %{"entity_type" => type, "resource_id" => id, "kind" => kind} <- input,
         {:ok, entity} <- Map.fetch(@entity_kinds, type),
         {:ok, category} <- Map.fetch(@categories, kind),
         {:ok, entry} <- read(entity, id, scope, entity_tags: :tag_definition) do
      {:ok, [{entity, id}], [change(gettext("Category"), tags(entry.entity_tags), category_label(category))]}
    else
      _invalid -> :error
    end
  end

  defp preview("set_analysis_entry_project_tags", %{"input" => input}, scope) do
    with %{"entity_type" => type, "resource_id" => id, "tag_definition_ids" => [_ | _] = tag_ids} <-
           input,
         {:ok, entity} <- Map.fetch(@entity_kinds, type),
         {:ok, entry} <- read(entity, id, scope, entity_tags: :tag_definition),
         {:ok, tags} <- all(tag_ids, &result(TagDefinition.get_tag_definition(&1, scope: scope))) do
      {:ok, [{entity, id}],
       [
         change(
           gettext("Category"),
           tags(entry.entity_tags),
           Enum.map_join(tags, ", ", & &1.name)
         )
       ]}
    else
      _invalid -> :error
    end
  end

  defp preview("start_session", %{"input" => %{"project_id" => project_id} = input}, scope) do
    with {:ok, title} <- text(input["title"]),
         {:ok, remote?} <- boolean(input["is_remote"]),
         {:ok, running} <- result(Session.get_current(scope: scope)) do
      {:ok, [{:project, project_id}],
       [
         running && change(gettext("Running session"), session_label(running), gettext("stopped")),
         change(gettext("Title"), nil, title),
         change(gettext("Start"), nil, gettext("now")),
         remote? && change(gettext("Remote work"), nil, gettext("Yes"))
       ]}
    end
  end

  defp preview("stop_current_session", _arguments, scope) do
    case result(Session.get_current(scope: scope)) do
      {:ok, %Session{} = session} ->
        {:ok, [{:session, session.id}], [change(gettext("End"), nil, gettext("now"))]}

      _none ->
        :error
    end
  end

  defp preview("edit_session", %{"input" => %{"id" => id} = input}, scope) do
    with {:ok, title} <- text(input["title"]),
         {:ok, session} <- result(Session.current_session(id, scope: scope, load: [:project])),
         {:ok, start} <- optional(input["start_datetime"], &datetime/1),
         {:ok, finish} <- optional(input["end_datetime"], &datetime/1),
         {:ok, project} <- optional(input["project_id"], &result(Project.get(&1, scope: scope))),
         {:ok, remote?} <- boolean(input["is_remote"]) do
      {:ok, [{:session, id}],
       [
         title && change(gettext("Title"), session.title, title),
         start && change(gettext("Start"), time(session.start_datetime), time(start)),
         finish && change(gettext("End"), time(session.end_datetime), time(finish)),
         project &&
           change(gettext("Project"), session.project && session.project.name, project.name),
         is_boolean(remote?) &&
           change(gettext("Remote work"), yes_no(session.is_remote), yes_no(remote?))
       ]}
    end
  end

  defp preview("add_sessions", %{"input" => %{"sessions" => [_ | _] = sessions}}, scope) do
    with {:ok, changes} <- all(sessions, &added_session(&1, scope)) do
      {:ok, [], List.flatten(changes)}
    end
  end

  defp preview("create_leave_request", %{"input" => input}, _scope) do
    with %{"starts_on" => starts_on, "ends_on" => ends_on, "reason" => reason} <- input,
         {:ok, starts_on} <- parse(&Date.from_iso8601/1, starts_on),
         {:ok, ends_on} <- parse(&Date.from_iso8601/1, ends_on),
         {:ok, reason} <- Map.fetch(@leave_reasons, reason),
         {:ok, note} <- text(input["note"]) do
      {:ok, [],
       [
         change(gettext("Period"), nil, "#{date(starts_on)}–#{date(ends_on)}"),
         change(gettext("Leave type"), nil, LeavePresentation.reason_label(reason)),
         change(gettext("Note"), nil, note)
       ]}
    else
      _invalid -> :error
    end
  end

  # The member is read again: the actor's was loaded at mount, before earlier approved changes.
  defp preview("update_profile", %{"input" => input}, scope) when is_map(input) do
    with {:ok, same?} <- boolean(input["is_same_correspondence_address"]),
         {:ok, _texts} <-
           all(Map.values(Map.delete(input, "is_same_correspondence_address")), &text/1),
         {:ok, user} <-
           result(Core.get_org_user(%{id: scope.actor.id}, scope: scope, load: [:member])) do
      input = Map.put(input, "is_same_correspondence_address", same?)

      changes =
        for {field, label} <- profile_fields(),
            value = input[Atom.to_string(field)],
            not is_nil(value),
            do:
              change(
                label,
                profile_value(field, Map.get(user.member, field)),
                profile_value(field, value)
              )

      changes =
        changes
        |> clear_correspondence_address(same?, user.member)
        |> Enum.reject(&(&1.from == &1.to))

      if changes == [], do: :unchanged, else: {:ok, [], changes}
    end
  end

  defp preview("create_sales_invoice_draft", %{"input" => input}, scope) when is_map(input) do
    with {:ok, invoice} <- invoice_input(input),
         # Skipping the draft in matching has no row on the card, so it cannot be approved.
         {:ok, draft} <-
           result(Invoicing.preview_sales_invoice(%{invoice: invoice}, scope: scope)) do
      if draft.skip_invoicing,
        do: :error,
        else: {:ok, counterparty_reference(nil, draft), invoice_changes(nil, draft)}
    end
  end

  defp preview("update_sales_invoice_draft", %{"id" => id, "input" => input}, scope) when is_map(input) do
    with {:ok, invoice} <- invoice_input(input),
         {:ok, saved} <-
           result(
             Invoicing.get_sales_invoice(id,
               scope: scope,
               load: [sales_invoice_items: [], counterparty: [:display_label]]
             )
           ),
         {:ok, revised} <-
           result(Invoicing.preview_sales_invoice(%{invoice_id: id, invoice: invoice}, scope: scope)),
         {:ok, unlinked} <- unlinked_counterparty(saved, revised) do
      references = counterparty_reference(saved, revised)
      changes = unlinked ++ invoice_changes(saved, revised)

      cond do
        # Compared on every reviewed field, not only those the card shows.
        snapshot(saved) == snapshot(revised) -> :unchanged
        # A revision whose only effect has no row on the card would be approved unseen.
        changes == [] and references == [] -> :error
        true -> {:ok, [{:sales, id} | references], changes}
      end
    end
  end

  defp preview(_name, _arguments, _scope), do: :error

  defp change(label, from, to), do: %{label: label, from: blank(from), to: blank(to)}

  defp blank(value) when value in [nil, ""], do: nil
  defp blank(value), do: value

  # An unreadable or missing record makes the plan unavailable; other failures are bugs.
  defp result({:ok, value}), do: {:ok, value}
  defp result({:error, %Forbidden{}}), do: :error
  defp result({:error, %Invalid{}}), do: :error
  defp result({:error, error}), do: raise(Ash.Error.to_error_class(error))

  defp read(kind, id, scope, loads \\ []) do
    read =
      case kind do
        :sales -> &Invoicing.list_sales_invoices/2
        :cost -> &Invoicing.list_cost_invoices/2
        :transaction -> &Finances.list_transactions/2
      end

    case result(read.(%{ids: [id]}, scope: scope, page: false, load: loads)) do
      {:ok, [record]} -> {:ok, record}
      _missing -> :error
    end
  end

  defp parse(parse, value) when is_binary(value) do
    case parse.(value) do
      {:ok, parsed} -> {:ok, parsed}
      {:ok, parsed, _offset} -> {:ok, parsed}
      {:error, _reason} -> :error
    end
  end

  defp parse(_parse, _value), do: :error

  # A tool argument the card shows as text; any other JSON value makes the card unavailable
  # instead of failing to render.
  defp text(value) when is_nil(value) or is_binary(value), do: {:ok, value}
  defp text(_value), do: :error

  defp optional(nil, _fun), do: {:ok, nil}
  defp optional(value, fun), do: fun.(value)

  defp all(values, fun) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
      case fun.(value) do
        {:ok, result} -> {:cont, {:ok, acc ++ [result]}}
        :error -> {:halt, :error}
      end
    end)
  end

  defp salary(%{salary_user_id: nil}, _scope), do: {:ok, nil}

  defp salary(%{salary_user_id: user_id, salary_month: month}, scope), do: salary(user_id, month, scope)

  defp salary(user_id, month, scope) do
    with {:ok, user} <-
           result(Core.get_org_user(%{id: user_id}, scope: scope, load: [member: :display_name])) do
      {:ok,
       gettext("%{employee} · %{month}",
         employee: user.member.display_name,
         month: Calendar.strftime(month, "%m.%Y")
       )}
    end
  end

  defp tags([]), do: nil

  defp tags(tags) do
    Enum.map_join(tags, ", ", fn
      %{kind: :project, tag_definition: %{name: name}} -> name
      %{kind: kind} -> category_label(kind)
    end)
  end

  defp category_label(:company), do: gettext("Company")
  defp category_label(:taxes), do: gettext("Taxes")
  defp category_label(:internal), do: gettext("Omitted")

  defp session_label(session) do
    [session.project && session.project.name, session.title]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" · ")
  end

  defp added_session(session, scope) do
    with %{"project_id" => project_id, "start_datetime" => from, "end_datetime" => to} <- session,
         {:ok, from} <- datetime(from),
         {:ok, to} <- datetime(to),
         {:ok, title} <- text(session["title"]),
         {:ok, remote?} <- boolean(session["is_remote"]),
         {:ok, project} <- result(Project.get(project_id, scope: scope)) do
      {:ok,
       [
         change(
           project.name,
           nil,
           gettext("%{date}, %{from}–%{to} · %{title}",
             date: Calendar.strftime(local(from), "%d.%m.%Y"),
             from: Calendar.strftime(local(from), "%H:%M"),
             to: Calendar.strftime(local(to), "%H:%M"),
             title: title
           )
         ),
         remote? && change(gettext("Remote work"), nil, gettext("Yes"))
       ]}
    else
      _invalid -> :error
    end
  end

  defp datetime(value), do: parse(&DateTime.from_iso8601/1, value)

  # Read as the action casts a boolean argument (Ash.Type.Boolean): "true" and "1" are true too; a
  # value it rejects makes the card unavailable rather than show a guess.
  defp boolean(value), do: Ecto.Type.cast(:boolean, value)

  defp local(datetime), do: DateTime.shift_zone!(datetime, @timezone)

  defp time(nil), do: nil
  defp time(datetime), do: Calendar.strftime(local(datetime), "%d.%m.%Y %H:%M")

  defp date(date), do: Calendar.strftime(date, "%d.%m.%Y")

  defp yes_no(true), do: gettext("Yes")
  defp yes_no(_value), do: gettext("No")

  defp profile_fields do
    [
      name: gettext("Full name"),
      phone: gettext("Phone"),
      slack_url: gettext("Slack"),
      bank_account_number: gettext("Bank account number"),
      birthday: gettext("Birthday"),
      birthday_visibility: gettext("Birthday visibility"),
      residence_address: gettext("Residence address"),
      correspondence_address: gettext("Correspondence address"),
      is_same_correspondence_address: gettext("Same correspondence address")
    ]
  end

  # The action clears the correspondence address when it is the same as the residence one,
  # whatever address the call carries.
  defp clear_correspondence_address(changes, true, member) do
    label = profile_fields()[:correspondence_address]

    Enum.reject(changes, &(&1.label == label)) ++
      [change(label, member.correspondence_address, nil)]
  end

  defp clear_correspondence_address(changes, _same?, _member), do: changes

  defp profile_value(_field, nil), do: nil
  defp profile_value(:birthday, %Date{} = birthday), do: date(birthday)
  defp profile_value(:birthday, birthday), do: birthday
  defp profile_value(:is_same_correspondence_address, value), do: yes_no(value)

  defp profile_value(:birthday_visibility, value) do
    case to_string(value) do
      "not_shared" -> gettext("Not shared")
      "day_with_month" -> gettext("Day and month")
      _full_date -> gettext("Full date")
    end
  end

  defp profile_value(_field, value), do: value

  # The draft actions take the invoice as fields beside an `input` (InvoiceInput) that
  # `ApplyInvoiceInput` applies over them; the preview takes the same invoice as one InvoiceInput.
  # A field on both levels makes the card unavailable: the action keeps the outer value when the
  # inner one is null and the field has a default, which one merged invoice cannot show. An inner
  # input that is not a map (the action also decodes a JSON string) makes it unavailable too.
  defp invoice_input(%{"input" => inner} = input) when is_map(inner) do
    outer = Map.delete(input, "input")

    if Enum.any?(Map.keys(inner), &is_map_key(outer, &1)),
      do: :error,
      else: {:ok, Map.merge(outer, inner)}
  end

  defp invoice_input(%{"input" => inner}) when not is_nil(inner), do: :error
  defp invoice_input(input), do: {:ok, Map.delete(input, "input")}

  # A draft is compared by the fields it writes that decide who is invoiced, for what and how
  # they pay.
  defp invoice_changes(saved, revised) do
    [
      {gettext("Seller"), & &1.seller_display_name},
      {gettext("Buyer"), & &1.buyer_full_name},
      {gettext("First name"), & &1.buyer_given_name},
      {gettext("Last name"), & &1.buyer_surname},
      {gettext("Display name"), & &1.buyer_display_name},
      {pgettext("sales invoice creator", "Identifier"), & &1.buyer_id},
      {gettext("Address"), & &1.buyer_address},
      {pgettext("sales invoice creator", "Country"), & &1.buyer_country},
      {gettext("Correspondence address"), & &1.buyer_mail_address},
      {gettext("Different correspondence address"), &flag(&1.buyer_is_different_mail_address)},
      {gettext("Email"), & &1.buyer_email},
      {gettext("Phone"), & &1.buyer_phone},
      {gettext("Description"), & &1.buyer_description},
      {gettext("Issue date"), &(&1.issue_date && date(&1.issue_date))},
      {gettext("Sale date"), &(&1.sale_date && date(&1.sale_date))},
      {gettext("Due date"), &(&1.due_date && date(&1.due_date))},
      {gettext("Payment method"), &payment_method(&1.payment_method)},
      {gettext("Bank account number"), & &1.seller_account_number},
      {gettext("Reverse charge"), &flag(&1.is_reverse_charge)},
      {gettext("VAT exemption"), &(&1.vat_exemption_type && VatExemption.label(&1.vat_exemption_type))},
      {gettext("Exemption basis"), & &1.vat_exemption_basis},
      {gettext("Invoice note"), & &1.invoice_note},
      {gettext("Internal note"), & &1.internal_note},
      {gettext("Email the invoice to the counterparty after receiving the KSeF number"), &flag(&1.should_send_emails)}
    ]
    |> Enum.map(fn {label, value} ->
      {label, saved && blank(value.(saved)), blank(value.(revised))}
    end)
    |> Enum.reject(fn {_label, before, later} -> before == later end)
    |> Enum.map(fn {label, before, later} -> change(label, before, later) end)
    |> Kernel.++(item_changes(saved, revised))
  end

  defp item_changes(saved, revised) do
    Enum.filter(
      [
        not same_items?(saved, revised) &&
          change(gettext("Items"), saved && items(saved), items(revised)),
        (is_nil(saved) or vat_rates(saved) != vat_rates(revised)) &&
          change(gettext("VAT"), saved && vat_rates(saved), vat_rates(revised))
      ],
      & &1
    )
  end

  # A linked counterparty is shown as its record when the call sets or changes it.
  defp counterparty_reference(saved, %{counterparty_id: id}) when is_binary(id) do
    if saved && saved.counterparty_id == id, do: [], else: [{:counterparty, id}]
  end

  defp counterparty_reference(_saved, _revised), do: []

  # Unlinking leaves no record to show, so the unlinked counterparty is a row; one the user cannot
  # read makes the card unavailable.
  defp unlinked_counterparty(%{counterparty_id: id} = saved, %{counterparty_id: nil}) when is_binary(id) do
    case saved.counterparty do
      %{display_label: label} -> {:ok, [change(gettext("Counterparty"), label, nil)]}
      nil -> :error
    end
  end

  defp unlinked_counterparty(_saved, _revised), do: {:ok, []}

  defp payment_method(nil), do: nil
  defp payment_method(:transfer), do: gettext("Transfer")
  defp payment_method(:cash), do: gettext("Cash")
  defp payment_method(:card), do: gettext("Card")
  defp payment_method(method), do: Atom.to_string(method)

  defp flag(true), do: gettext("Yes")
  defp flag(_value), do: nil

  # Every field a revision can write, plus the reviewed ones it refreshes. Decimals compare by
  # value: a saved 1.0 is the proposed 1.
  defp snapshot(invoice) do
    invoice
    |> Preview.review_snapshot()
    |> Map.merge(Map.take(invoice, Info.action(SalesInvoice, :revise).accept))
    |> Map.update!(:items, fn items ->
      Enum.map(items, &Map.new(&1, fn {key, value} -> {key, normalize(value)} end))
    end)
  end

  defp normalize(%Decimal{} = value), do: Decimal.normalize(value)
  defp normalize(value), do: value

  # Quantities and prices are compared as numbers: a saved 1.0 is the proposed 1.
  defp same_items?(nil, _revised), do: false

  defp same_items?(saved, revised) do
    length(saved.sales_invoice_items) == length(revised.sales_invoice_items) and
      Enum.all?(Enum.zip(saved.sales_invoice_items, revised.sales_invoice_items), fn {before, later} ->
        before.name == later.name and before.unit == later.unit and
          Decimal.eq?(before.quantity, later.quantity) and
          Decimal.eq?(before.unit_price, later.unit_price) and before.vat_rate == later.vat_rate
      end) and saved.currency == revised.currency
  end

  defp vat_rates(invoice), do: Enum.map_join(invoice.sales_invoice_items, "; ", &VatRate.label(&1.vat_rate))

  defp items(invoice) do
    Enum.map_join(invoice.sales_invoice_items, "; ", fn item ->
      gettext("%{name} · %{quantity} %{unit} × %{price} net",
        name: item.name,
        quantity: item.quantity,
        unit: item.unit,
        price: Money.new(invoice.currency, item.unit_price)
      )
    end)
  end
end
