defmodule FirmowidWeb.DesignSystem.Components.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as modals, tables, and
  forms. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The default components use Tailwind CSS, a utility-first CSS framework.
  See the [Tailwind CSS documentation](https://tailwindcss.com) to learn
  how to customize them or feel free to swap in another framework altogether.

  Icons are provided by [heroicons](https://heroicons.com). See `FirmowidUI.Components.Inputs.icon/1` for usage.
  """
  use Phoenix.Component
  use Gettext, backend: Firmowid.Gettext

  import FirmowidUI.Components.Inputs

  alias Phoenix.HTML.Form
  alias Phoenix.HTML.FormField
  alias Phoenix.LiveView.JS

  @doc """
  Renders a modal.

  ## Examples

      <.modal id="confirm-modal">
        This is a modal.
      </.modal>

  JS commands may be passed to the `:on_cancel` to configure
  the closing/cancel event, for example:

      <.modal id="confirm" on_cancel={JS.navigate(~p"/posts")}>
        This is another modal.
      </.modal>

  """
  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :on_cancel, JS, default: %JS{}
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def modal(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={@show && show_modal(@id)}
      phx-remove={hide_modal(@id)}
      phx-show={show_modal(@id)}
      data-cancel={JS.exec(@on_cancel, "phx-remove")}
      class="relative z-50 hidden"
    >
      <div id={"#{@id}-bg"} class="fixed inset-0 bg-black/60 transition-opacity" aria-hidden="true" />
      <div
        class="fixed inset-0 overflow-y-auto"
        aria-labelledby={"#{@id}-title"}
        aria-describedby={"#{@id}-description"}
        role="dialog"
        aria-modal="true"
        tabindex="0"
      >
        <div class="flex min-h-full items-center justify-center">
          <div class={["w-full max-w-3xl p-4 sm:p-6 lg:py-8", @class]}>
            <.focus_wrap
              id={"#{@id}-container"}
              phx-window-keydown={JS.exec("data-cancel", to: "##{@id}")}
              phx-key="escape"
              phx-click-away={JS.exec("data-cancel", to: "##{@id}")}
              class="relative hidden rounded-md bg-white p-10 shadow-lg ring-1 shadow-grey-700/10 ring-grey-700/10 transition"
            >
              <div class="absolute top-6 right-5">
                <button
                  phx-click={JS.exec("data-cancel", to: "##{@id}")}
                  type="button"
                  class="-m-3 flex-none p-3 opacity-20 hover:opacity-40"
                  aria-label={gettext("close")}
                >
                  <.icon name="hero-x-mark-solid" class="size-5" />
                </button>
              </div>
              <div id={"#{@id}-content"}>
                {render_slot(@inner_block)}
              </div>
            </.focus_wrap>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a simple form.

  ## Examples

      <.simple_form for={@form} phx-change="validate" phx-submit="save">
        <.input field={@form[:email]} label="Email"/>
        <.input field={@form[:username]} label="Username" />
        <:actions>
          <.button>Save</.button>
        </:actions>
      </.simple_form>
  """
  attr :for, :any, required: true, doc: "the data structure for the form"
  attr :as, :any, default: nil, doc: "the server side parameter to collect all input under"

  attr :rest, :global,
    include: ~w(autocomplete name rel action enctype method novalidate target multipart),
    doc: "the arbitrary HTML attributes to apply to the form tag"

  slot :inner_block, required: true
  slot :actions, doc: "the slot for form actions, such as a submit button"

  def simple_form(assigns) do
    ~H"""
    <.form :let={f} for={@for} as={@as} {@rest}>
      <div class="mt-10 space-y-8">
        {render_slot(@inner_block, f)}
        <div :for={action <- @actions} class="mt-2 flex items-center justify-between gap-6">
          {render_slot(action, f)}
        </div>
      </div>
    </.form>
    """
  end

  @doc """
  Renders a visually hidden live file input inside a drag-and-drop area.
  """
  attr :upload, :any, required: true
  attr :prompt, :string, required: true
  attr :class, :string, default: nil
  attr :content_class, :string, default: "text-center"
  attr :prompt_class, :string, default: nil
  attr :error_formatter, :any, default: nil
  attr :show_errors, :boolean, default: true
  attr :disabled, :boolean, default: false
  attr :phx_change, :string, default: nil

  def file_upload(assigns) do
    ~H"""
    <label
      class={[
        "flex w-full cursor-pointer justify-center rounded-md border-2 border-dashed border-rust-700 px-6 py-8",
        @disabled && "cursor-not-allowed border-grey-200",
        @class
      ]}
      phx-drop-target={unless @disabled, do: @upload.ref}
    >
      <div class={["text-sm text-rust-700", @disabled && "text-grey-200", @content_class]}>
        <div :if={Enum.empty?(@upload.entries)} class={@prompt_class}>
          {@prompt}
        </div>

        <Phoenix.Component.live_file_input
          upload={@upload}
          class="sr-only"
          disabled={@disabled}
          phx-change={@phx_change}
        />

        <div :if={!Enum.empty?(@upload.entries)}>
          <%= for entry <- @upload.entries do %>
            <p>{entry.client_name}</p>
            <p :for={error <- if(@show_errors, do: upload_errors(@upload, entry), else: [])}>
              {format_upload_error(error, @error_formatter)}
            </p>
          <% end %>
        </div>

        <p :for={error <- if(@show_errors, do: upload_errors(@upload), else: [])}>
          {format_upload_error(error, @error_formatter)}
        </p>
      </div>
    </label>
    """
  end

  defp format_upload_error(error, nil), do: to_string(error)
  defp format_upload_error(error, formatter), do: formatter.(error)

  @doc """
  Renders an editable control, or a value-preserving fallback, but never both.

  The essence of the component is a form control that presents as normal-looking
  content while its editability is conditional. When hidden, a carrier input is
  rendered automatically (from `field`, or `value` override) so the field's value
  still reaches the surrounding form. Both slots accept arbitrary markup so
  callers can use the native input type and form behavior they require.
  """
  attr :show, :boolean, default: true, doc: "whether to render the editable control"

  attr :field, FormField,
    default: nil,
    doc: "form field whose value must be submitted even while the control is hidden"

  attr :value, :any,
    default: nil,
    doc: "overrides the field's value in the carrier input"

  slot :input, required: true, doc: "the editable control"
  slot :fallback, doc: "the control shown while the editable control is hidden"

  def hidden_input(%{show: false} = assigns) do
    carrier_value =
      if assigns.field, do: assigns[:value] || assigns.field.value, else: assigns[:value]

    assigns =
      assign(assigns,
        carrier_name: assigns.field && assigns.field.name,
        carrier_value: carrier_value
      )

    ~H"""
    <input :if={@field} type="hidden" name={@carrier_name} value={@carrier_value} />
    {render_slot(@fallback)}
    """
  end

  def hidden_input(assigns) do
    ~H"""
    {render_slot(@input)}
    """
  end

  @doc """
  Classes that make an input read as normal text until interacted with.

  Pair with `readonly` toggling or transparent styling to implement
  inline-editable fields that blend into surrounding content. Add `truncate`
  via `extra` for single-line inputs; leave it off for multiline textareas.
  """
  @spec text_like_input_styles(extra :: [String.t()]) :: [String.t()]
  def text_like_input_styles(extra \\ []) do
    [
      "-ml-1 min-w-0 rounded border-none p-1 transition",
      "bg-transparent hover:bg-grey-200 focus:bg-grey-200 focus:ring-0"
      | extra
    ]
  end

  attr :id, :string, required: true
  attr :class, :any, default: nil
  slot :inner_block, required: true
  slot :trigger, required: true, doc: "the slot for the trigger element"

  def dropdown(assigns) do
    ~H"""
    <div class={["relative", @class]}>
      <button
        type="button"
        phx-click={
          JS.toggle(
            to: "#dropdown_menu_#{@id}",
            in: {"transition-all duration-75", "opacity-0 scale-95", "opacity-100 scale-100"},
            out:
              {"transition-all duration-75", "opacity-100 translate-y-0 sm:scale-100",
               "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"},
            display: "flex"
          )
        }
        id={"dropdown_button_#{@id}"}
        phx-click-away={hide("#dropdown_menu_#{@id}")}
        phx-window-keydown={hide("#dropdown_menu_#{@id}")}
        phx-key="Escape"
        class="inline-flex duration-75"
      >
        {render_slot(@trigger)}
      </button>
      <div
        id={"dropdown_menu_#{@id}"}
        style="display: none"
        class="absolute top-1 right-0 z-20 max-w-[calc(100vw-2rem)]"
      >
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def avatar(assigns) do
    ~H"""
    <div class={["relative overflow-hidden rounded-full", @class]} {@rest}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :class, :any, default: nil
  attr :src, :string
  attr :alt, :string, default: ""
  attr :rest, :global

  def avatar_image(assigns) do
    ~H"""
    <img
      class={[
        "aspect-square size-full rounded-full object-cover",
        (!@src || @src === "") && "hidden",
        @class
      ]}
      src={@src}
      alt={@alt}
      {@rest}
    />
    """
  end

  attr :class, :any, default: nil
  attr :bg_color, :string, default: "grey-100"
  attr :rest, :global
  slot :inner_block, required: false

  def avatar_fallback(assigns) do
    ~H"""
    <span
      class={[
        "flex size-full items-center justify-center rounded-full",
        @bg_color && "bg-#{@bg_color}",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </span>
    """
  end

  @doc """
  Provides a radio group input for a given form field.

  ## Examples

      <.radio_group field={@form[:tip]}>
        <:radio value="0">No Tip</:radio>
        <:radio value="10">10%</:radio>
        <:radio value="20">20%</:radio>
      </.radio_group>
  """
  attr :field, FormField, required: true
  attr :class, :any, default: nil

  slot :radio, required: true do
    attr :value, :string, required: true
  end

  slot :inner_block

  def radio_group(assigns) do
    ~H"""
    <div class={["flex gap-2", @class]}>
      {render_slot(@inner_block)}
      <div :for={{%{value: value} = rad, idx} <- Enum.with_index(@radio)}>
        <label
          for={"#{@field.id}-#{idx}"}
          class="relative flex cursor-pointer items-center has-disabled:cursor-default has-disabled:opacity-50"
        >
          <input
            type="radio"
            name={@field.name}
            id={"#{@field.id}-#{idx}"}
            phx-disable-with=""
            value={value}
            checked={to_string(@field.value) == to_string(value)}
            class="peer sr-only"
          />
          <div class="flex size-4 items-center justify-center rounded-[3px] border border-grey-700 text-grey-700 peer-focus-visible:outline-2 peer-focus-visible:outline-offset-2 peer-focus-visible:outline-(--focus-ring)">
            <svg
              :if={to_string(@field.value) == to_string(value)}
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="2.5"
              stroke="currentColor"
              class="size-6"
            >
              <path stroke-linecap="round" stroke-linejoin="round" d="m4.5 12.75 6 6 9-13.5" />
            </svg>
          </div>
          <span class="ml-1 text-sm text-grey-700">{render_slot(rad)}</span>
        </label>
      </div>
    </div>
    """
  end

  @doc """
  Renders a header with title.
  """
  attr :class, :any, default: nil

  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", @class]}>
      <div>
        <h1 class="text-lg/8 font-semibold text-grey-900">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="mt-2 text-sm/6 text-grey-700">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc ~S"""
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id"><%= user.id %></:col>
        <:col :let={user} label="username"><%= user.username %></:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :class, :any, default: nil
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <table class={[@class]}>
      <thead class="text-left text-sm/6 text-grey-600">
        <tr>
          <th :for={col <- @col} class="p-0 pr-2 font-normal text-grey-700 uppercase">
            {col[:label]}
          </th>
          <th :if={@action != []} class="relative p-0 pb-4">
            <span class="sr-only">{gettext("Actions")}</span>
          </th>
        </tr>
      </thead>
      <tbody
        id={@id}
        phx-update={match?(%Phoenix.LiveView.LiveStream{}, @rows) && "stream"}
        class="relative divide-y divide-grey-100 border-t border-grey-100 text-sm/6 text-grey-700"
      >
        <tr
          :for={row <- @rows}
          id={@row_id && @row_id.(row)}
          class="group transition-colors hover:bg-white"
        >
          <td :for={col <- @col} phx-click={@row_click && @row_click.(row)} class="py-1">
            {render_slot(col, @row_item.(row))}
          </td>
          <td :if={@action != []} class="relative w-14 p-0">
            <span :for={action <- @action}>
              {render_slot(action, @row_item.(row))}
            </span>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  @doc """
  Renders a filled back navigation link.

  ## Examples

      <.back navigate={~p"/posts"} />
      <.back patch={~p"/faktury/kreator?krok=1"} icon_only />
  """
  attr :navigate, :any, default: nil
  attr :patch, :any, default: nil
  attr :class, :any, default: nil
  attr :icon_only, :boolean, default: false
  attr :aria_label, :string, default: "Wróć"
  attr :rest, :global
  slot :inner_block

  def back(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      patch={@patch}
      aria-label={@icon_only && @aria_label}
      class={["inline-flex items-center gap-2 text-sm", @class]}
      {@rest}
    >
      <span class="inline-flex size-6 items-center justify-center rounded-full bg-black text-white">
        <Lucideicons.chevron_left class="size-4" />
      </span>
      <.back_label :if={!@icon_only} blocks={@inner_block} />
    </.link>
    """
  end

  attr :blocks, :list, required: true

  defp back_label(assigns) do
    ~H"""
    <%= if @blocks == [] do %>
      Wróć
    <% else %>
      {render_slot(@blocks)}
    <% end %>
    """
  end

  attr :id, :string, required: true
  attr :reference_id, :string, required: true
  attr :strategy, :string, default: "absolute", values: ["absolute", "fixed"]
  attr :class, :any, default: nil

  attr :placement, :string,
    default: "bottom",
    values: [
      "top",
      "top-start",
      "top-end",
      "right",
      "right-start",
      "right-end",
      "bottom",
      "bottom-start",
      "bottom-end",
      "left",
      "left-start",
      "left-end"
    ]

  slot :inner_block, required: true

  def popover(assigns) do
    ~H"""
    <.focus_wrap id={"#{@id}-focus-wrap"}>
      <div
        class={["pointer-events-auto absolute top-0 left-0 z-50 hidden w-max", @class]}
        role="dialog"
        phx-hook="Popover"
        phx-remove={hide_popover(@id)}
        phx-click-away={hide_popover(@id)}
        phx-window-keydown={hide_popover(@id)}
        phx-key="escape"
        id={@id}
        data-reference={@reference_id}
        data-placement={@placement}
        data-strategy={@strategy}
      >
        {render_slot(@inner_block)}
      </div>
    </.focus_wrap>
    """
  end

  @doc """
  Renders a toggle switch
  """

  attr :field, FormField, required: true
  attr :label, :string, default: nil
  attr :class, :any, default: nil
  attr :disabled, :boolean, default: false
  attr :color, :string, values: ["rust", "teal"], default: "rust"
  attr :rest, :global

  slot :label_slot

  def switch(assigns) do
    ~H"""
    <label class={["inline-flex cursor-pointer items-center gap-2", @class]}>
      <input
        type="hidden"
        name={@field.name}
        value="false"
        disabled={@disabled}
      />
      <input
        type="checkbox"
        name={@field.name}
        id={@field.id}
        checked={Form.normalize_value("checkbox", @field.value)}
        value="true"
        class="peer sr-only"
        disabled={@disabled}
        {@rest}
      />
      <div class={[
        "relative h-[24px] w-[38px] rounded-full bg-grey-200 p-[4px] transition-colors duration-200 ease-out after:absolute after:size-[16px] after:rounded-full after:bg-white after:transition-transform after:duration-200 after:ease-out after:content-[''] peer-checked:after:translate-x-[14px] disabled:opacity-50",
        @color == "rust" && "peer-checked:bg-rust-700",
        @color == "teal" && "peer-checked:bg-teal-700"
      ]}>
      </div>
      <span :if={@label} class="text-grey-900">{@label}</span>
      <%!-- hack: label_slot is a list of slots --%>
      <span :if={Enum.any?(@label_slot)} class="flex flex-row items-center text-grey-900">
        {render_slot(@label_slot)}
      </span>
    </label>
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all transform ease-out duration-300", "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all transform ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  def show_modal(js \\ %JS{}, id) when is_binary(id) do
    js
    |> JS.show(to: "##{id}")
    |> JS.show(
      to: "##{id}-bg",
      time: 300,
      transition: {"transition-all transform ease-out duration-300", "opacity-0", "opacity-100"}
    )
    |> show("##{id}-container")
    |> JS.add_class("overflow-hidden", to: "body")
    |> JS.focus_first(to: "##{id}-content")
  end

  def hide_modal(js \\ %JS{}, id) do
    js
    |> JS.hide(
      to: "##{id}-bg",
      transition: {"transition-all transform ease-in duration-200", "opacity-100", "opacity-0"}
    )
    |> hide("##{id}-container")
    |> JS.hide(to: "##{id}", transition: {"block", "block", "hidden"})
    |> JS.remove_class("overflow-hidden", to: "body")
    |> JS.pop_focus()
  end

  def show_popover(js \\ %JS{}, id) do
    js
    # |> show("##{id}")
    |> JS.show(to: "##{id}")
    |> JS.dispatch("showPopover", to: "##{id}")
    |> JS.focus_first(to: "##{id}")
  end

  def hide_popover(js \\ %JS{}, id) do
    js
    # |> hide("##{id}")
    |> JS.hide(to: "##{id}")
    |> JS.dispatch("hidePopover", to: "##{id}")
    |> JS.pop_focus()
  end

  @doc "Top-level navbar container. Pair with `navbar_logo/1`."
  attr :class, :any, default: nil
  attr :rest, :global

  slot :inner_block

  def navbar(assigns) do
    ~H"""
    <nav
      class={[
        "bg-black px-4 text-white select-none [--focus-ring:var(--color-white)] sm:px-6 lg:px-8",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </nav>
    """
  end

  @doc """
  Firmowid logo. Renders as `<.link>` when `navigate` is set, `<span>` otherwise.

  Uses conditional rendering (configuration) rather than composition because
  there are only two branches and they share the same styling. This is an
  intentional deviation from the "composition over configuration" guideline.
  """
  attr :navigate, :string, default: nil
  attr :class, :any, default: nil
  attr :rest, :global

  def navbar_logo(assigns) do
    ~H"""
    <%= if @navigate do %>
      <.link
        navigate={@navigate}
        class={[
          "inline-block text-xl font-extrabold tracking-wide text-grey-100",
          @class
        ]}
        {@rest}
      >
        Firmowid
      </.link>
    <% else %>
      <span
        class={[
          "inline-block text-xl font-extrabold tracking-wide text-grey-100",
          @class
        ]}
        {@rest}
      >
        Firmowid
      </span>
    <% end %>
    """
  end
end
