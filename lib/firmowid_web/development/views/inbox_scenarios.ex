defmodule FirmowidWeb.Development.Views.InboxScenarios do
  @moduledoc """
  Development-only preview of the inbox in prepared situations: for the
  company layer an empty queue, a usual day, blocked integrations, many
  approvals, many overdue invoices, long texts and so on; for the member's own
  layer things to do next to a running session, or nothing at all.

  It renders the real inbox template with made-up items, so design changes to
  the inbox show here without preparing data in the database. Decisions only
  take the item off the preview. Like the design system catalog, its route
  exists only in the development environment.
  """
  use FirmowidWeb, :live_view

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Timetracker.Session
  alias FirmowidWeb.Delegations.Utilities.DelegationPresentation
  alias FirmowidWeb.Inbox.Views.Index
  alias FirmowidWeb.Timetracker.Utilities.LeavePresentation

  # Dev-only route: verified routes would warn in environments without it.
  @path "/development/skrzynka"

  @scenarios [
    {"zwykly-dzien", "Zwykły dzień"},
    {"wszystko-zrobione", "Wszystko zrobione"},
    {"pilne", "Pilne: KSeF i bank"},
    {"ksef-niepodlaczony", "KSeF niepodłączony"},
    {"duzo-wnioskow", "Dużo wniosków"},
    {"duzo-faktur", "Dużo zaległych faktur"},
    {"ksiegowa", "Widok księgowej"},
    {"dlugie-teksty", "Długie teksty"},
    {"nowa-firma", "Nowa firma"},
    {"duzy-zespol", "Duży zespół"},
    {"wszystko-naraz", "Wszystko naraz"},
    {"ty-sprawy", "Ty: sprawy i sesja"},
    {"ty-wszystko-zrobione", "Ty: wszystko zrobione"},
    {"ty-bez-sesji", "Ty: bez sesji"},
    {"ty-duzy-zespol", "Ty: duży zespół, zdalnie"},
    {"ty-duzo-zadan", "Ty: dużo zadań"},
    {"ty-dlugie-teksty", "Ty: długie teksty"},
    {"ty-sam", "Ty: sama w firmie"}
  ]

  # Trips the live button files for the member, one after another.
  @trips [
    "Targi w Poznaniu",
    "Spotkanie z klientem w Gdańsku",
    "Szkolenie we Wrocławiu",
    "Konferencja w Berlinie",
    "Audyt u klienta w Łodzi"
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Skrzynka: scenariusze",
       scenarios: @scenarios,
       path: @path,
       no_padding: true,
       hide_floating_assistant: true
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    key =
      if List.keymember?(@scenarios, params["scenariusz"], 0),
        do: params["scenariusz"],
        else: "zwykly-dzien"

    today = socket.assigns.timezone |> DateTime.now!() |> DateTime.to_date()
    scenario = scenario(key, today)

    {:noreply,
     assign(socket,
       scenario: key,
       layer: Map.get(scenario, :layer, :company),
       today: today,
       items: scenario.items,
       presence: scenario.presence,
       month: scenario.month,
       month_duration: Map.get(scenario, :month_duration),
       fresh: MapSet.new(),
       query: "",
       expanded: MapSet.new(),
       session: Map.get(scenario, :session),
       last_session: Map.get(scenario, :last_session)
     )}
  end

  @impl true
  # Plays what an open inbox does when a new task of the member's arrives,
  # such as a business trip that has just ended.
  def handle_event("simulate_new", _params, %{assigns: %{layer: :me}} = socket) do
    n = System.unique_integer([:positive])
    ends_on = Date.add(socket.assigns.today, -1)
    status = if rem(n, 3) == 0, do: :awaiting_signature, else: :in_progress

    item =
      personal_delegation(
        "new-#{n}",
        Enum.at(@trips, rem(n, length(@trips))),
        Date.add(ends_on, -rem(n, 4)),
        ends_on,
        status
      )

    {:noreply, assign(socket, items: [item | socket.assigns.items], fresh: MapSet.new([item.id]))}
  end

  # Plays what an open inbox does when someone files a request elsewhere.
  def handle_event("simulate_new", _params, socket) do
    n = System.unique_integer([:positive])

    item =
      leave(
        "new-#{n}",
        Enum.random(["Ewa Wójcik", "Jan Kowalczyk", "Zosia Nowak"]),
        :vacation,
        socket.assigns.today,
        7,
        3
      )

    {:noreply, assign(socket, items: [item | socket.assigns.items], fresh: MapSet.new([item.id]))}
  end

  def handle_event(event, params, socket) when event in ["toggle_group", "search"],
    do: Index.handle_event(event, params, socket)

  def handle_event("set_workplace", %{"remote" => remote}, %{assigns: %{session: %Session{}}} = socket) do
    {:noreply, update(socket, :session, &%{&1 | is_remote: remote == "true"})}
  end

  def handle_event("stop_session", _params, %{assigns: %{session: %Session{} = session}} = socket) do
    {:noreply, assign(socket, session: nil, last_session: session)}
  end

  def handle_event("start_session", _params, %{assigns: %{session: nil, last_session: %Session{} = last}} = socket) do
    {:noreply, assign(socket, :session, %{last | start_datetime: DateTime.utc_now()})}
  end

  # A second click that arrives before the page shows the first one's result.
  def handle_event(event, _params, socket) when event in ["set_workplace", "stop_session", "start_session"],
    do: {:noreply, socket}

  def handle_event("decide_item", %{"id" => id, "decision" => decision}, socket) do
    LiveToast.send_toast(
      :info,
      if(decision == "accept_leave_request",
        do: "Wniosek zaakceptowany (podgląd, nic nie zapisano).",
        else: "Wniosek odrzucony (podgląd, nic nie zapisano)."
      )
    )

    {:noreply, update(socket, :items, &Enum.reject(&1, fn item -> item.id == id end))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col">
      <nav
        aria-label="Scenariusze skrzynki"
        class="mx-4 mt-4 flex flex-wrap items-center gap-1.5 rounded-sm border border-dashed border-grey-300 p-2 md:mx-10"
      >
        <span class="px-1 text-xs font-medium text-grey-500 uppercase">Podgląd</span>
        <.link
          :for={{key, label} <- @scenarios}
          kind="unstyled"
          patch={"#{@path}?scenariusz=#{key}"}
          aria-current={@scenario == key && "page"}
          class={[
            "rounded-full px-2.5 py-1 text-xs transition-colors",
            if(@scenario == key,
              do: "bg-grey-900 text-white",
              else: "bg-white text-grey-700 hover:bg-grey-200"
            )
          ]}
        >
          {label}
        </.link>
        <%!-- An accountant never receives approvals, so nothing arrives in that scenario. --%>
        <.button
          :if={@scenario != "ksiegowa"}
          type="button"
          size="small"
          variant="tertiary"
          phx-click="simulate_new"
          class="ms-auto"
        >
          <Lucideicons.plus class="size-4" aria-hidden="true" />
          {if @layer == :me, do: "Nowe zadanie na żywo", else: "Nowy wniosek na żywo"}
        </.button>
      </nav>
      {Index.render(assigns)}
    </div>
    """
  end

  # Scenarios

  defp scenario("ty-sprawy", today) do
    %{
      layer: :me,
      items: [
        personal_delegation("1", "Targi w Poznaniu", Date.add(today, -3), Date.add(today, -1)),
        contract()
      ],
      session: session(13),
      last_session: nil,
      month_duration: 49 * 3600 + 43 * 60,
      presence: presence(1, 0, 11),
      month: []
    }
  end

  defp scenario("ty-wszystko-zrobione", _today) do
    %{
      layer: :me,
      items: [],
      session: session(13),
      last_session: nil,
      month_duration: 49 * 3600 + 43 * 60,
      presence: presence(1, 1, 3),
      month: []
    }
  end

  defp scenario("ty-bez-sesji", today) do
    %{
      layer: :me,
      items: [
        personal_delegation(
          "1",
          "Konferencja w Gdańsku",
          Date.add(today, -10),
          Date.add(today, -8)
        )
      ],
      session: nil,
      last_session: session(90),
      month_duration: 12 * 3600,
      presence: presence(2, 1, 4),
      month: []
    }
  end

  defp scenario("ty-duzy-zespol", today) do
    %{
      layer: :me,
      items: [
        personal_delegation("1", "Targi w Poznaniu", Date.add(today, -3), Date.add(today, -1)),
        contract()
      ],
      session: %{session(187) | is_remote: true},
      last_session: nil,
      month_duration: 112 * 3600 + 5 * 60,
      presence: presence(9, 6, 14),
      month: []
    }
  end

  defp scenario("ty-duzo-zadan", today) do
    trips =
      @trips
      |> Enum.with_index(1)
      |> Enum.map(fn {title, i} ->
        ends_on = Date.add(today, -i * 3)

        personal_delegation(
          "#{i}",
          title,
          Date.add(ends_on, -2),
          ends_on,
          if(i == 2, do: :awaiting_signature, else: :in_progress)
        )
      end)

    %{
      layer: :me,
      items: trips ++ [contract()],
      session: session(48),
      last_session: nil,
      month_duration: 64 * 3600 + 30 * 60,
      presence: presence(4, 2, 5),
      month: []
    }
  end

  defp scenario("ty-dlugie-teksty", today) do
    %{
      layer: :me,
      items: [
        personal_delegation(
          "1",
          "Wizyta u kontrahenta w Kędzierzynie-Koźlu, przegląd wdrożenia i szkolenie zespołu księgowego",
          Date.add(today, -40),
          Date.add(today, -5)
        ),
        contract()
      ],
      session: %Session{
        title: "Przegląd i poprawki modułu rozliczeń delegacji zagranicznych po zmianie przepisów",
        project: %{name: "Acme Sp. z o.o. — wdrożenie systemu rozliczeń"},
        is_remote: false,
        start_datetime: DateTime.shift(DateTime.utc_now(), minute: -(10 * 60 + 7))
      },
      last_session: nil,
      month_duration: 168 * 3600,
      presence: [
        %{name: "Maria Konstancja Wielogórska-Przybyszewska", status: :office},
        %{name: nil, status: :remote}
        | presence(0, 0, 3)
      ],
      month: []
    }
  end

  defp scenario("ty-sam", _today) do
    %{
      layer: :me,
      items: [],
      session: session(2),
      last_session: nil,
      month_duration: 0,
      presence: [%{name: "Kinga Nowak", status: :office}],
      month: []
    }
  end

  defp scenario("zwykly-dzien", today) do
    %{
      items: [
        leave("1", "Kinga Nowak", :vacation, today, 14, 5),
        hours_change("1", "Tomasz Wiśniewski", today, "Zapomniałem dodać sobotniego dyżuru."),
        delegation("1", :submitted, "Marta Zielińska", "Targi w Poznaniu"),
        overdue("1", :sales, "Studio Lumen sp. z o.o.", "4 920,00 zł", today, -6),
        overdue("2", :cost, "Orange Polska S.A.", "189,99 zł", today, -2)
      ],
      presence: presence(6, 1, 1),
      month: month("48 200 zł", "21 450 zł")
    }
  end

  defp scenario("wszystko-zrobione", _today) do
    %{items: [], presence: presence(4, 2, 0), month: month("62 900 zł", "18 300 zł")}
  end

  defp scenario("pilne", today) do
    %{
      items: [
        ksef(:expired),
        bank("1", "mBank firmowy", ~D[2026-10-28]),
        bank("2", "Santander VAT", nil),
        leave("1", "Kinga Nowak", :vacation, today, 3, 2),
        overdue("1", :cost, "PGE Obrót S.A.", "612,40 zł", today, -11)
      ],
      presence: presence(5, 1, 0),
      month: month("31 040 zł", "27 980 zł")
    }
  end

  defp scenario("ksef-niepodlaczony", today) do
    %{
      items: [
        ksef(:disconnected),
        overdue("1", :sales, "Kowalski i Wspólnicy", "1 230,00 zł", today, -3)
      ],
      presence: presence(2, 0, 0),
      month: month("3 690 zł", "0 zł")
    }
  end

  defp scenario("duzo-wnioskow", today) do
    names = [
      "Kinga Nowak",
      "Tomasz Wiśniewski",
      "Marta Zielińska",
      "Piotr Kamiński",
      "Ola Lewandowska"
    ]

    leaves =
      names
      |> Enum.with_index(1)
      |> Enum.map(fn {name, i} ->
        reason = Enum.at([:vacation, :sick, :unpaid, :rest, :other], i - 1)
        leave("#{i}", name, reason, today, i * 3, rem(i, 3) + 1)
      end)

    %{
      items:
        leaves ++
          [
            hours_change("1", "Piotr Kamiński", today, "Nadgodziny z wdrożenia."),
            hours_change("2", "Ola Lewandowska", today, "Błędnie wpisany urlop 3.11."),
            delegation("1", :pending, "Marta Zielińska", "Spotkanie z klientem w Gdańsku"),
            delegation("2", :submitted, "Tomasz Wiśniewski", "Konferencja Infoshare")
          ],
      presence: presence(5, 2, 3),
      month: month("48 200 zł", "21 450 zł")
    }
  end

  defp scenario("duzo-faktur", today) do
    counterparties = [
      {"Studio Lumen sp. z o.o.", :sales},
      {"Orange Polska S.A.", :cost},
      {"Kowalski i Wspólnicy", :sales},
      {"PGE Obrót S.A.", :cost},
      {"Biuro Rachunkowe Cyfrowe", :cost},
      {"Hotel Mercure Kraków", :cost},
      {"Agencja Pixel", :sales},
      {"Allegro.pl sp. z o.o.", :cost},
      {"Fundacja Otwarte Dane", :sales},
      {"OVHcloud", :cost},
      {"Piekarnia Pod Lipami", :sales},
      {"Google Ireland Ltd.", :cost}
    ]

    items =
      counterparties
      |> Enum.with_index(1)
      |> Enum.map(fn {{name, side}, i} ->
        overdue(
          "#{i}",
          side,
          name,
          "#{i * 731},#{(i * 37) |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")} zł",
          today,
          -(i * 4)
        )
      end)

    %{items: items, presence: presence(3, 1, 0), month: month("12 480 zł", "9 960 zł")}
  end

  defp scenario("ksiegowa", today) do
    %{
      items: [
        overdue("1", :sales, "Studio Lumen sp. z o.o.", "4 920,00 zł", today, -6),
        overdue("2", :cost, "Orange Polska S.A.", "189,99 zł", today, -2),
        overdue("3", :cost, "OVHcloud", "86,10 zł", today, -1)
      ],
      presence: presence(6, 1, 1),
      month: month("48 200 zł", "21 450 zł")
    }
  end

  defp scenario("dlugie-teksty", today) do
    %{
      items: [
        bank(
          "1",
          "Rachunek pomocniczy do rozliczeń z kontrahentami zagranicznymi w EUR",
          ~D[2026-09-30]
        ),
        leave("1", "Aleksandra Konstancja Wierzbicka-Szczepańska", :unpaid, today, 30, 14),
        hours_change(
          "1",
          "Maksymilian Grzegorz Brzęczyszczykiewicz",
          today,
          "W październiku pracowałem przy wdrożeniu u klienta w Rzeszowie i część godzin wpisałem do złego projektu, a dwa dni zdalne zostały oznaczone jako biuro."
        ),
        delegation(
          "1",
          :pending,
          "Marta Zielińska",
          "Wyjazd na międzynarodowe targi technologii finansowych oraz spotkania z partnerami w Berlinie i Monachium"
        ),
        overdue(
          "1",
          :sales,
          "Przedsiębiorstwo Handlowo-Usługowo-Produkcyjne „Mazowsze” Spółka z ograniczoną odpowiedzialnością sp. k.",
          "1 234 567,89 zł",
          today,
          -120
        )
      ],
      presence: [
        %{name: "Aleksandra Konstancja Wierzbicka-Szczepańska", status: :office},
        %{name: "Maksymilian Grzegorz Brzęczyszczykiewicz", status: :remote},
        %{name: nil, status: :away}
      ],
      month: month("1 234 567 zł", "987 654 zł")
    }
  end

  defp scenario("nowa-firma", _today) do
    %{items: [ksef(:disconnected)], presence: [], month: month("0 zł", "0 zł")}
  end

  defp scenario("duzy-zespol", today) do
    %{
      items: [leave("1", "Kinga Nowak", :vacation, today, 14, 5)],
      presence: presence(14, 6, 5),
      month: month("312 800 zł", "198 450 zł")
    }
  end

  defp scenario("wszystko-naraz", today) do
    ["pilne", "duzo-wnioskow", "duzo-faktur"]
    |> Enum.map(&scenario(&1, today))
    |> Enum.reduce(fn s, acc -> %{acc | items: acc.items ++ s.items} end)
    |> Map.update!(:items, &Enum.uniq_by(&1, fn item -> item.id end))
  end

  # Items, shaped like `FirmowidWeb.Inbox.Utilities.Queue.items/3`

  defp ksef(status) do
    %{
      id: "ksef",
      tier: :urgent,
      icon: "unplug",
      title:
        if(status == :expired,
          do: gettext("The KSeF connection has expired"),
          else: gettext("KSeF is not connected")
        ),
      context: gettext("Cost invoices do not arrive on their own and sales invoices cannot be sent to KSeF."),
      person: nil,
      action: gettext("Connect"),
      href: "#"
    }
  end

  defp bank(id, name, last_sync) do
    %{
      id: "bank-#{id}",
      tier: :urgent,
      icon: "landmark",
      title: gettext("%{account}: synchronization stopped", account: name),
      context:
        if(last_sync,
          do:
            gettext("Transactions were last fetched on %{date}.",
              date: Calendar.strftime(last_sync, "%d.%m")
            ),
          else: gettext("No transactions have been fetched from this account yet.")
        ),
      person: nil,
      action: gettext("Renew consent"),
      href: "#"
    }
  end

  defp leave(id, person, reason, today, starts_in, days) do
    starts_on = Date.add(today, starts_in)
    ends_on = Date.add(starts_on, days - 1)
    reject? = reason in [:vacation, :sick, :unpaid]

    %{
      id: "leave-#{id}",
      tier: :people,
      icon: "calendar-days",
      title: gettext("Leave request"),
      date_range: "#{Calendar.strftime(starts_on, "%d.%m")}–#{Calendar.strftime(ends_on, "%d.%m")}",
      context:
        Enum.join(
          [
            LeavePresentation.reason_label(reason),
            ngettext("%{count} calendar day", "%{count} calendar days", days)
          ],
          " · "
        ),
      person: person,
      action: gettext("Review"),
      href: "#",
      decisions:
        Enum.filter(
          [
            %{
              action: :accept_leave_request,
              record_id: id,
              label: pgettext("inbox decision", "Accept"),
              icon: "check",
              show_label?: true
            },
            reject? &&
              %{
                action: :decline_leave_request,
                record_id: id,
                label: gettext("Reject"),
                icon: "x",
                show_label?: false
              }
          ],
          & &1
        )
    }
  end

  defp hours_change(id, person, today, reason) do
    month = today |> Date.beginning_of_month() |> Date.add(-1)

    %{
      id: "hours-change-#{id}",
      tier: :people,
      icon: "clipboard-list",
      title: gettext("Timesheet change request, %{month}", month: Calendar.strftime(month, "%m.%Y")),
      context: reason,
      person: person,
      action: gettext("Review"),
      href: "#"
    }
  end

  defp delegation(id, status, person, title) do
    %{
      id: "delegation-#{id}",
      tier: :people,
      icon: "plane",
      title:
        if(status == :pending,
          do: gettext("Business trip order awaiting approval"),
          else: gettext("Business trip settlement awaiting review")
        ),
      context: title,
      person: person,
      action: gettext("Review"),
      href: "#"
    }
  end

  defp personal_delegation(id, title, starts_on, ends_on, status \\ :in_progress) do
    %{
      id: "delegation-#{id}",
      tier: :personal,
      icon: "plane",
      title: gettext("Business trip settlement: %{title}", title: title),
      context:
        if(status == :awaiting_signature,
          do: gettext("waiting for your signature"),
          else:
            gettext("settle by %{date}",
              date: ends_on |> Date.add(14) |> Calendar.strftime("%d.%m")
            )
        ),
      person: DelegationPresentation.format_range(starts_on, ends_on),
      action: if(status == :awaiting_signature, do: gettext("Sign"), else: gettext("Settle")),
      href: "#"
    }
  end

  defp contract do
    %{
      id: "contract-1",
      tier: :personal,
      icon: "file-signature",
      title: gettext("Your employment contract is waiting for your signature"),
      context: gettext("Download the contract, sign it and upload the signed document."),
      person: nil,
      action: gettext("Sign"),
      href: "#"
    }
  end

  defp session(minutes_ago) do
    %Session{
      title: "Poprawki [kod]",
      project: %{name: "Acme"},
      is_remote: false,
      start_datetime: DateTime.shift(DateTime.utc_now(), minute: -minutes_ago)
    }
  end

  defp overdue(id, side, counterparty, amount, today, due_in) do
    due = Date.add(today, due_in)

    number =
      if side == :sales,
        do: "FV/#{id}/#{Calendar.strftime(due, "%m/%Y")}",
        else: "F/#{1000 + String.to_integer(id)}"

    %{
      id: "overdue-#{side}-#{id}",
      tier: :books,
      side: side,
      due_date: due,
      days_late: -due_in,
      icon: "file-chart-column",
      title:
        if(side == :sales,
          do: gettext("Overdue sales invoice %{number}", number: number),
          else: gettext("Overdue cost invoice %{number}", number: number)
        ),
      context:
        gettext("%{amount} · due %{date}",
          amount: amount,
          date: Calendar.strftime(due, "%d.%m.%Y")
        ),
      person: counterparty,
      action: gettext("Review"),
      href: "#"
    }
  end

  @names ~w(Kinga Tomasz Marta Piotr Ola Bartek Ewa Jan Zosia Michał Natalia Kuba Iga Adam Julia Paweł Lena Filip Maja Igor Hania Oskar Nina Wiktor Ala)

  defp presence(office, remote, absent) do
    statuses =
      List.duplicate(:office, office) ++
        List.duplicate(:remote, remote) ++ List.duplicate(:leave, absent) ++ [:away]

    statuses
    |> Enum.with_index()
    |> Enum.map(fn {status, i} ->
      %{name: "#{Enum.at(@names, rem(i, length(@names)))} #{surname(i)}", status: status}
    end)
  end

  defp surname(i), do: Enum.at(~w(Nowak Wiśniewski Zielińska Kamiński Lewandowska Wójcik Kowalczyk), rem(i, 7))

  defp month(income, costs) do
    [
      %{label: gettext("Income"), value: income, side: :sales},
      %{label: gettext("Costs"), value: costs, side: :cost}
    ]
  end
end
