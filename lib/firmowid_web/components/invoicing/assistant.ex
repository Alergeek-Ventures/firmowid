defmodule FirmowidWeb.Components.Invoicing.Assistant do
  @moduledoc false
  use FirmowidWeb, :html

  alias FirmowidWeb.Helpers.TimeFormatter

  require Logger

  attr :loading, :boolean, default: false
  attr :input, :string, default: ""
  attr :myself, :any, default: nil

  def input(assigns) do
    ~H"""
    <form
      class="flex flex-row gap-2 border border-grey-300 h-12 py-2 px-4 mx-16 mb-8 rounded-md bg-white"
      phx-submit="send"
      phx-target={@myself}
    >
      <input
        name="message"
        value={@input}
        autocomplete="off"
        placeholder={if @loading, do: "Firmowid myśli...", else: "Napisz swoją wiadomość"}
        disabled={@loading}
        class={[
          "placeholder:text-grey-400 text-black w-full p-0 border-none focus:ring-0",
          "focus:outline-none disabled:opacity-50 disabled:cursor-not-allowed"
        ]}
      />
      <button
        type="submit"
        disabled={@loading}
        class="text-grey-400 disabled:opacity-50 disabled:cursor-not-allowed"
      >
        <%= if @loading do %>
          <.icon name="hero-arrow-path" class="animate-spin" />
        <% else %>
          <.icon name="hero-paper-airplane" />
        <% end %>
      </button>
    </form>
    """
  end

  def message(%{role: :user, text: text}, _myself, opts) do
    current_user = Keyword.fetch!(opts, :current_user)
    assigns = %{text: text, current_user: current_user}

    ~H"""
    <div class="flex flex-row gap-3 justify-end">
      <p class="px-4 py-2 bg-grey-200 rounded max-w-2xl">{@text}</p>
      <div class="w-10 h-10">
        <.avatar class="size-10">
          <.avatar_image src={@current_user.avatar_url} alt="Avatar" />
          <.avatar_fallback>
            {String.slice(@current_user.email, 0, 1) |> String.upcase()}
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
      <img src="/images/logo_firmowid.png" class="w-10 h-10 mt-2" />
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
    <div class="flex flex-row gap-2 items-center ml-[52px] py-2 px-4 flex-wrap max-w-2xl min-h-8 box-content">
      <p class="text-sm text-nowrap leading-none">Szukam transakcji</p>
      <div
        :if={@date_filter}
        class="py-1 px-3 bg-orange-100 text-orange-900 rounded whitespace-nowrap animate-fade-in"
      >
        data: <span class="font-semibold">{@date_filter}</span>
      </div>
      <div
        :if={@amount_filter}
        class="py-1 px-3 bg-orange-100 text-orange-900 rounded whitespace-nowrap animate-fade-in"
      >
        kwota: <span class="font-semibold">{@amount_filter}</span>
      </div>
      <div
        :if={@filters["currency"]}
        class="py-1 px-3 bg-orange-100 text-orange-900 rounded whitespace-nowrap animate-fade-in"
      >
        waluta: <span class="font-semibold">{@filters["currency"]}</span>
      </div>
      <div
        :if={@filters["query"]}
        class="py-1 px-3 bg-orange-100 text-orange-900 rounded whitespace-nowrap animate-fade-in"
      >
        fraza: <span class="font-semibold">{@filters["query"]}</span>
      </div>
      <div
        :if={not @filters["only_unmatched"]}
        class="py-1 px-3 bg-orange-100 text-orange-900 rounded whitespace-nowrap animate-fade-in"
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
      myself: myself
    }

    ~H"""
    <div class="ml-[52px] py-2 px-4 max-w-2xl -mt-12 flex flex-col gap-6">
      <p>{@message}</p>

      <ul class="gap-2 flex flex-col w-full">
        <li
          :for={transaction <- @transactions}
          class="py-1 px-3 flex flex-row gap-4 justify-between items-start bg-grey-50 rounded"
        >
          <div class="grid grid-cols-[min-content,1fr] gap-x-3">
            <span class="text-sm text-grey-700">Nadawca</span>
            <span class="text-black truncate">{transaction.debtor_name}</span>
            <span class="text-sm text-grey-700">Zaksięgowano</span>
            <span class="text-black">{TimeFormatter.format_date(transaction.booking_date)}</span>
          </div>
          <div class="flex flex-row gap-3 items-center">
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
    <div class="flex flex-row gap-2 items-center ml-[52px] py-2 px-4 flex-wrap -mt-12">
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
          <div class="flex flex-row gap-4 items-center">
            <div>🛠️ <b>{@name}</b> called</div>
            <div><pre>{inspect(@args)}</pre></div>
          </div>
          """

        %{role: :function_result, payload: %{name: _, result: _} = assigns} ->
          ~H"""
          <div class="flex flex-row gap-4 items-center">
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
