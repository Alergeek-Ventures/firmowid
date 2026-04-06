defmodule FirmowidWeb.Invoicing.Components.Assistant do
  @moduledoc false
  use FirmowidWeb, :html

  alias FirmowidWeb.Infrastructure.Utilities.TimeFormatter

  require Logger

  attr :loading, :boolean, default: false
  attr :input, :string, default: ""
  attr :myself, :any, default: nil

  def input(assigns) do
    ~H"""
    <form
      class="border-grey-200 mx-16 mb-8 flex h-10 flex-row gap-2 rounded-lg border bg-white px-4 py-1"
      phx-submit="send"
      phx-target={@myself}
    >
      <input
        name="message"
        value={@input}
        autocomplete="off"
        placeholder={if @loading, do: "Firmowid myśli...", else: "Napisz swoją wiadomość"}
        disabled={@loading}
        class="placeholder:text-grey-200 w-full border-none p-0 text-black focus:ring-0 focus:outline-hidden disabled:cursor-not-allowed disabled:opacity-50"
      />
      <button
        type="submit"
        disabled={@loading}
        class={[
          "transition-colors duration-300 disabled:cursor-not-allowed",
          if(@loading, do: "text-black", else: "text-grey-200")
        ]}
      >
        <%= if @loading do %>
          <.icon name="hero-arrow-path" class="animate-spin" />
        <% else %>
          <Lucideicons.send class="size-6" />
        <% end %>
      </button>
    </form>
    """
  end

  def message(%{role: :user, text: text}, _myself, opts) do
    current_user = Keyword.fetch!(opts, :current_user)
    assigns = %{text: text, current_user: current_user}

    ~H"""
    <div class="flex flex-row justify-end gap-3">
      <p class="bg-grey-200 max-w-2xl rounded px-4 py-2">{@text}</p>
      <div class="size-10">
        <.avatar class="size-10">
          <.avatar_image
            :if={@current_user.avatar_blob && @current_user.avatar_blob.url}
            src={@current_user.avatar_blob && @current_user.avatar_blob.url}
            alt="Avatar"
          />
          <.avatar_fallback>
            {to_string(@current_user.email) |> String.slice(0, 1) |> String.upcase()}
          </.avatar_fallback>
        </.avatar>
      </div>
    </div>
    """
  end

  def message(%{role: :assistant, text: text}, _myself, _opts) do
    assigns = %{text: text}

    ~H"""
    <div class="flex flex-row gap-3">
      <img src="/images/logo_firmowid.png" class="mt-2 size-10" />
      <div class="prose prose-p:p-2 prose-p:text-black prose-p:whitespace-pre-wrap max-w-2xl">
        {render_content(@text)}
      </div>
    </div>
    """
  end

  def message(%{role: :function_call, payload: %{name: "search_transactions", args: args}}, _myself, _opts) do
    filters =
      args
      |> Map.get("filters", %{})
      |> Map.put_new("date_from", nil)
      |> Map.put_new("date_to", nil)
      |> Map.put_new("amount_gt", nil)
      |> Map.put_new("amount_lt", nil)
      |> Map.put_new("currency", nil)
      |> Map.put_new("only_unmatched", true)
      |> Map.put_new("query", nil)

    date_filter =
      [
        if(filters["date_from"], do: "od #{filters["date_from"]}"),
        if(filters["date_to"], do: "do #{filters["date_to"]}")
      ]
      |> Enum.reject(&is_nil/1)
      |> case do
        [] -> nil
        list -> Enum.join(list, " ")
      end

    amount_filter =
      [filters["amount_gt"], filters["amount_lt"]]
      |> Enum.reject(&is_nil/1)
      |> case do
        [] -> nil
        list -> Enum.join(list, " - ")
      end

    assigns = %{filters: filters, date_filter: date_filter, amount_filter: amount_filter}

    ~H"""
    <div class="ml-[52px] box-content flex min-h-8 max-w-2xl flex-row flex-wrap items-center gap-2 px-4 py-2">
      <p class="text-sm leading-none text-nowrap">Szukam transakcji</p>
      <div
        :if={@date_filter not in ["", nil]}
        class="animate-fade-in rounded bg-orange-100 px-3 py-1 whitespace-nowrap text-orange-900"
      >
        data: <span class="font-semibold">{@date_filter}</span>
      </div>
      <div
        :if={@amount_filter not in ["", nil]}
        class="animate-fade-in rounded bg-orange-100 px-3 py-1 whitespace-nowrap text-orange-900"
      >
        kwota: <span class="font-semibold">{@amount_filter}</span>
      </div>
      <div
        :if={@filters["currency"] not in ["", nil]}
        class="animate-fade-in rounded bg-orange-100 px-3 py-1 whitespace-nowrap text-orange-900"
      >
        waluta: <span class="font-semibold">{@filters["currency"]}</span>
      </div>
      <div
        :if={@filters["query"] not in ["", nil]}
        class="animate-fade-in rounded bg-orange-100 px-3 py-1 whitespace-nowrap text-orange-900"
      >
        fraza: <span class="font-semibold">{@filters["query"]}</span>
      </div>
      <div
        :if={not @filters["only_unmatched"]}
        class="animate-fade-in rounded bg-orange-100 px-3 py-1 whitespace-nowrap text-orange-900"
      >
        również dopasowane
      </div>
    </div>
    """
  end

  def message(
        %{
          role: :function_call,
          payload: %{name: name, args: %{"message" => assistant_message}},
          transactions: transactions
        } = message,
        myself,
        _opts
      )
      when name in ["link_cost_invoice_to_transaction", "link_sales_invoice_to_transaction"] do
    assigns = %{
      id: message.id,
      message: assistant_message,
      transactions: transactions,
      myself: myself,
      displayed_party: if(name == "link_cost_invoice_to_transaction", do: "Odbiorca", else: "Nadawca")
    }

    ~H"""
    <div class="-mt-12 ml-[52px] flex max-w-2xl flex-col gap-6 px-4 py-2">
      <p>{@message}</p>

      <ul class="flex w-full flex-col gap-2">
        <li
          :for={transaction <- @transactions}
          class="bg-grey-50 flex flex-row items-start justify-between gap-4 rounded px-3 py-1"
        >
          <div class="grid grid-cols-[min-content_1fr] gap-x-3">
            <span class="text-grey-700 text-sm">
              {@displayed_party}
            </span>
            <span class="truncate text-black">
              {case @displayed_party do
                "Nadawca" -> transaction.debtor_name
                "Odbiorca" -> transaction.creditor_name
                _ -> ""
              end}
            </span>
            <span class="text-grey-700 text-sm">Zaksięgowano</span>
            <span class="text-black">{TimeFormatter.format_date(transaction.booking_date)}</span>
          </div>
          <div class="flex flex-row items-center gap-3">
            {transaction.amount}
            <.icon name="hero-credit-card-micro" class="text-grey-700" />
          </div>
        </li>
      </ul>
    </div>
    """
  end

  def message(%{role: :function_result, payload: %{name: "search_transactions", result: result}}, _myself, _opts) do
    text =
      case result do
        transactions when is_list(transactions) ->
          text =
            case length(transactions) do
              0 -> "Nie znalazłem żadnych transakcji"
              1 -> "Znalazłem 1 transakcję"
              count when count < 5 -> "Znalazłem #{count} transakcje"
              count -> "Znalazłem #{count} transakcji"
            end

          text

        _ ->
          "Nie znalazłem żadnych transakcji"
      end

    assigns = %{text: text}

    ~H"""
    <div class="-mt-12 ml-[52px] flex flex-row flex-wrap items-center gap-2 px-4 py-2">
      <p class="text-sm">{@text}</p>
    </div>
    """
  end

  def message(message, _, opts) do
    Logger.warning("Unknown message type in assistant: #{inspect(message)}")

    if Keyword.get(opts, :debug, false) do
      case message do
        %{role: :function_call, payload: %{name: _, args: _} = assigns} ->
          ~H"""
          <div class="flex flex-row items-center gap-4">
            <div>🛠️ <b>{@name}</b> called</div>
            <div><pre>{inspect(@args)}</pre></div>
          </div>
          """

        %{role: :function_result, payload: %{name: _, result: _} = assigns} ->
          ~H"""
          <div class="flex flex-row items-center gap-4">
            <div>🛠️ <b>{@name}</b> result</div>
            <div><pre>{inspect(@result)}</pre></div>
          </div>
          """

        %{role: _, text: _, payload: _} = assigns ->
          ~H"""
          <div>[{to_string(@role)}] {render_content(@text)} {inspect(@payload)}</div>
          """

        %{type: _} = assigns ->
          ~H"""
          <div>[{to_string(@type)}] {render_content(@content)} {inspect(@metadata)}</div>
          """
      end
    else
      assigns = %{}

      ~H"""
      """
    end
  end

  defp render_content(nil), do: "failed to render content"

  # sobelow_skip ["XSS.Raw"]
  # This is safe because MDEx outputs typography tags, not script tags
  defp render_content(content) do
    content |> MDEx.to_html!() |> raw()
  end
end
