defmodule FirmowidWeb.Organization.Components.CompanyCard do
  @moduledoc """
  The company card of onboarding: a sheet of paper with the company's register
  data that collects ink stamps as the setup steps are done.
  """
  use FirmowidWeb, :html

  alias FirmowidWeb.Analysis.Utilities.Industry
  alias Phoenix.LiveView.Rendered

  @legal_forms ~r/\s+(spółka z ograniczoną odpowiedzialnością|sp\. z o\.o\.|spółka akcyjna|s\.a\.|prosta spółka akcyjna|spółka komandytowa|sp\. k\.|spółka jawna|sp\. j\.|spółka cywilna|s\.c\.)$/iu

  # Lucide icon paths drawn inside the stamps' own SVG.
  @icons %{
    clock: ~s(<circle cx="12" cy="12" r="10"/><path d="M12 6v6l4 2"/>),
    receipt:
      ~s(<path d="M13 16H8M14 8H8M16 12H8"/><path d="M4 3a1 1 0 0 1 1-1 1.3 1.3 0 0 1 .7.2l.933.6a1.3 1.3 0 0 0 1.4 0l.934-.6a1.3 1.3 0 0 1 1.4 0l.933.6a1.3 1.3 0 0 0 1.4 0l.933-.6a1.3 1.3 0 0 1 1.4 0l.934.6a1.3 1.3 0 0 0 1.4 0l.933-.6A1.3 1.3 0 0 1 19 2a1 1 0 0 1 1 1v18a1 1 0 0 1-1 1 1.3 1.3 0 0 1-.7-.2l-.933-.6a1.3 1.3 0 0 0-1.4 0l-.934.6a1.3 1.3 0 0 1-1.4 0l-.933-.6a1.3 1.3 0 0 0-1.4 0l-.933.6a1.3 1.3 0 0 1-1.4 0l-.934-.6a1.3 1.3 0 0 0-1.4 0l-.933.6a1.3 1.3 0 0 1-.7.2 1 1 0 0 1-1-1z"/>),
    plug: ~s(<path d="M12 22v-5M9 8V2M15 8V2M18 8v5a4 4 0 0 1-4 4h-4a4 4 0 0 1-4-4V8Z"/>),
    landmark: ~s(<path d="M3 22h18M6 18v-7M10 18v-7M14 18v-7M18 18v-7M12 2l8 5H4Z"/>),
    users:
      ~s(<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75"/>)
  }

  @doc """
  Renders the card. Without a `name` it is the blank card of a company that does
  not exist yet. Rows marked `fresh` are highlighted as just filled in.
  """
  @spec company_card(map()) :: Rendered.t()
  attr :id, :string, required: true
  attr :name, :string, default: nil

  attr :rows, :list,
    default: [],
    doc: "`%{label:, value:, fresh: boolean}` maps; nil values render as blanks"

  attr :class, :any, default: nil
  slot :stamps

  def company_card(assigns) do
    assigns = assign(assigns, split_name(assigns.name))

    ~H"""
    <article
      id={@id}
      class={[
        "relative w-full rounded-sm bg-white px-8 pt-10 pb-8 shadow-[0_1px_1px_rgba(0,0,0,.05),0_18px_40px_-18px_rgba(0,0,0,.25),0_60px_120px_-60px_rgba(0,0,0,.25)] sm:px-14 sm:pt-14 lg:-rotate-1",
        is_nil(@name) && "bg-grey-50",
        @class
      ]}
    >
      <svg
        class={[
          "pointer-events-none absolute inset-3 size-[calc(100%-1.5rem)] fill-none",
          if(@name, do: "stroke-grey-900", else: "stroke-grey-400")
        ]}
        viewBox="0 0 748 568"
        preserveAspectRatio="none"
        aria-hidden="true"
      >
        <path
          stroke-width="1.1"
          vector-effect="non-scaling-stroke"
          d="M3 4C180 2 560 5 745 3c2 180-1 380 1 562-200 2-560-1-742 1C1 380 4 180 3 4Z"
        />
        <path
          stroke-width="1.1"
          vector-effect="non-scaling-stroke"
          opacity=".35"
          d="M7 8c200-2 540 1 734-1-1 180 2 370-1 554-190-1-540 2-732-1 2-180-2-360-1-552Z"
        />
      </svg>
      <svg width="0" height="0" class="absolute" aria-hidden="true">
        <defs>
          <filter id={"#{@id}-ink"} x="-5%" y="-5%" width="110%" height="110%">
            <feTurbulence type="fractalNoise" baseFrequency=".85" numOctaves="2" seed="4" result="n" />
            <feDisplacementMap
              in="SourceGraphic"
              in2="n"
              scale="2.4"
              xChannelSelector="R"
              yChannelSelector="G"
              result="d"
            />
            <feTurbulence type="fractalNoise" baseFrequency="2.2" seed="9" result="g" />
            <feColorMatrix
              in="g"
              type="matrix"
              values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 -1.3 1.55"
              result="m"
            />
            <feComposite in="d" in2="m" operator="in" />
          </filter>
          <path id={"#{@id}-ring"} d="M75 75m-52 0a52 52 0 1 1 104 0a52 52 0 1 1-104 0" />
        </defs>
      </svg>

      <div class="relative">
        <%= if @name do %>
          <%!-- A long word breaks rather than leave the card. --%>
          <h2 class="text-3xl/tight font-semibold tracking-tight wrap-anywhere text-grey-900 sm:text-[2.875rem]/[1.05]">
            {@base_name}
            <span
              :if={@legal_form}
              class="mt-2 block text-lg font-medium text-grey-500 sm:text-[1.375rem]"
            >
              {@legal_form}
            </span>
          </h2>
        <% else %>
          <p class="text-3xl font-semibold tracking-tight text-grey-300 sm:text-[2.875rem]/[1.05]">
            {gettext("Your company")}
          </p>
        <% end %>

        <dl class="mt-8 grid grid-cols-[6rem_1fr] gap-y-3 text-base sm:mt-10 sm:grid-cols-[9rem_1fr]">
          <%= for {row, index} <- Enum.with_index(@rows) do %>
            <dt class="pt-0.5 text-sm text-grey-500">{row.label}</dt>
            <dd :if={row.value} class="text-grey-900">
              <%!-- Inline and cloned per line, so a value that wraps is marked on every line. --%>
              <span
                class={[
                  row[:fresh] &&
                    "bg-[linear-gradient(transparent_60%,var(--color-moss-200)_60%)] box-decoration-clone bg-no-repeat motion-safe:animate-marker"
                ]}
                style={row[:fresh] && "animation-delay: #{150 + index * 90}ms"}
              >
                {row.value}
              </span>
            </dd>
            <dd :if={is_nil(row.value)} class="mt-1.5 h-3 w-48 max-w-full rounded-full bg-grey-100">
            </dd>
          <% end %>
        </dl>

        <div
          :if={@stamps != []}
          class="mt-8 ml-auto grid max-w-md grid-cols-3 items-center gap-1.5 sm:mt-10"
        >
          {render_slot(@stamps, @id)}
        </div>
      </div>
    </article>
    """
  end

  @doc "An applied ink stamp: `text` runs around the ring, `icon` sits in the middle."
  @spec stamp(map()) :: Rendered.t()
  attr :card, :string,
    required: true,
    doc: "the card id, whose ink filter and ring the stamp uses"

  attr :text, :string, required: true
  attr :icon, :atom, required: true, values: [:clock, :receipt, :plug, :landmark, :users]
  attr :rotate, :integer, default: 0
  attr :pressed, :boolean, default: false, doc: "animates the stamp being pressed onto the card"
  attr :class, :any, default: nil

  # sobelow_skip ["XSS.Raw"]
  # The raw markup is one of the SVG paths in the module's @icons constant, picked by
  # an icon atom the attr restricts to that list; no user input reaches it.
  def stamp(assigns) do
    assigns =
      assigns
      |> assign(:icon_paths, Map.fetch!(@icons, assigns.icon))
      |> assign(:ring_text, ring_text(assigns.text))

    ~H"""
    <svg
      viewBox="0 0 150 150"
      class={[
        "h-auto w-full",
        if(@pressed, do: "motion-safe:animate-stamp-press motion-reduce:animate-fade-in"),
        @class
      ]}
      style={"--stamp-rotate: #{@rotate}deg; rotate: var(--stamp-rotate)"}
      role="img"
      aria-label={@text}
    >
      <g filter={"url(##{@card}-ink)"} fill="none" stroke="var(--color-moss-800)">
        <circle cx="75" cy="75" r="66" stroke-width="3.6" />
        <circle cx="75" cy="75" r="40" stroke-width="1.6" />
        <text fill="var(--color-moss-800)" stroke="none" class="text-xs font-bold tracking-[.14em]">
          <textPath href={"##{@card}-ring"}>
            {@ring_text}
          </textPath>
        </text>
        <g
          transform="translate(57 57) scale(1.5)"
          stroke-width="1.6"
          stroke-linecap="round"
          stroke-linejoin="round"
        >
          {Phoenix.HTML.raw(@icon_paths)}
        </g>
      </g>
    </svg>
    """
  end

  # The ring holds about 34 letters. A short text repeats to fill it like a real
  # stamp's; dots separate the repeats, so none dangles at the end of the ring.
  @ring_letters 34

  defp ring_text(text) do
    copies = max(div(@ring_letters, String.length(text) + 3), 1)
    text |> List.duplicate(copies) |> Enum.join(" · ")
  end

  @doc """
  A place for a stamp that is not there yet. `state` `:active` marks the step at
  hand, `:pending` draws the stamp being inked while work runs in the background.
  """
  @spec stamp_slot(map()) :: Rendered.t()
  attr :label, :string, required: true
  attr :hint, :string, required: true
  attr :state, :atom, default: :waiting, values: [:waiting, :active, :pending]
  attr :class, :any, default: nil

  def stamp_slot(assigns) do
    ~H"""
    <svg
      viewBox="0 0 150 150"
      class={["h-auto w-full", @class]}
      role="img"
      aria-label={"#{@label}: #{@hint}"}
    >
      <circle
        cx="75"
        cy="75"
        r="64"
        stroke-dasharray="5 6"
        class={[
          @state == :waiting && "fill-none stroke-grey-400",
          @state == :active && "fill-grey-50 stroke-black",
          @state == :pending && "fill-grey-50 stroke-grey-200"
        ]}
        stroke-width="1.5"
      />
      <circle
        :if={@state == :pending}
        cx="75"
        cy="75"
        r="64"
        fill="none"
        stroke="var(--color-moss-700)"
        stroke-width="3.6"
        stroke-linecap="round"
        stroke-dasharray="150 252"
        class="origin-center [animation-duration:2.8s] motion-safe:animate-spin"
      />
      <text
        x="75"
        y="72"
        text-anchor="middle"
        class={[
          "text-[22px] font-semibold",
          if(@state == :waiting, do: "fill-grey-500", else: "fill-grey-900")
        ]}
      >
        {@label}
      </text>
      <text
        x="75"
        y="94"
        text-anchor="middle"
        class={[
          "text-xs",
          if(@state == :pending, do: "fill-moss-700 font-medium", else: "fill-grey-600")
        ]}
      >
        {@hint}
      </text>
    </svg>
    """
  end

  @doc "Text of the billing stamp: the industry, and hourly billing when the company bills by the hour."
  @spec billing_stamp_text(atom(), boolean()) :: String.t()
  def billing_stamp_text(industry, true),
    do: String.upcase(gettext("%{industry} · hourly billing", industry: Industry.label(industry)))

  def billing_stamp_text(industry, _bills_hourly), do: String.upcase(Industry.label(industry))

  @doc "Icon of the billing stamp."
  @spec billing_icon(boolean()) :: :clock | :receipt
  def billing_icon(true), do: :clock
  def billing_icon(_bills_hourly), do: :receipt

  @doc "Groups the ten digits of a NIP the way it is printed: `616 152 58 11`."
  @spec format_nip(String.t()) :: String.t()
  def format_nip(<<a::binary-size(3), b::binary-size(3), c::binary-size(2), d::binary-size(2)>>),
    do: "#{a} #{b} #{c} #{d}"

  def format_nip(nip), do: nip

  @doc """
  Suggests the short name the app shows: the registered name without its legal
  form, with shouted words softened (`ALLEGRO` → `Allegro`, `JAN` → `Jan`) except
  two-letter ones, which are usually acronyms (`CD`).
  """
  @spec suggested_display_name(String.t()) :: String.t()
  def suggested_display_name(name) do
    %{base_name: base_name} = split_name(name)
    base_name |> String.split(" ", trim: true) |> Enum.map_join(" ", &soften/1)
  end

  defp soften(word) do
    if String.length(word) > 2 and word == String.upcase(word),
      do: String.capitalize(word),
      else: word
  end

  defp split_name(nil), do: %{base_name: nil, legal_form: nil}

  # Registered names may hold non-breaking or repeated spaces, which the legal
  # forms would not match, so the name is split with its spaces made plain.
  defp split_name(name) do
    name = name |> String.replace(~r/\s+/u, " ") |> String.trim()

    case Regex.run(@legal_forms, name) do
      [suffix, legal_form] ->
        %{
          base_name: binary_part(name, 0, byte_size(name) - byte_size(suffix)),
          legal_form: legal_form
        }

      nil ->
        %{base_name: name, legal_form: nil}
    end
  end
end
