defmodule FirmowidWeb.CoreComponents do
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

  Icons are provided by [heroicons](https://heroicons.com). See `icon/1` for usage.
  """
  use Phoenix.Component
  use Gettext, backend: FirmowidWeb.Gettext

  import Tails

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
  attr :class, :string, default: nil
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
      <div id={"#{@id}-bg"} class="bg-black/60 fixed inset-0 transition-opacity" aria-hidden="true" />
      <div
        class="fixed inset-0 overflow-y-auto"
        aria-labelledby={"#{@id}-title"}
        aria-describedby={"#{@id}-description"}
        role="dialog"
        aria-modal="true"
        tabindex="0"
      >
        <div class="flex min-h-full items-center justify-center">
          <div class={classes(["w-full max-w-3xl p-4 sm:p-6 lg:py-8", @class])}>
            <.focus_wrap
              id={"#{@id}-container"}
              phx-window-keydown={JS.exec("data-cancel", to: "##{@id}")}
              phx-key="escape"
              phx-click-away={JS.exec("data-cancel", to: "##{@id}")}
              class="shadow-darkGrey/10 ring-darkGrey/10 relative hidden
              rounded-md bg-white p-10 shadow-lg ring-1 transition"
            >
              <div class="absolute top-6 right-5">
                <button
                  phx-click={JS.exec("data-cancel", to: "##{@id}")}
                  type="button"
                  class="-m-3 flex-none p-3 opacity-20 hover:opacity-40"
                  aria-label={gettext("close")}
                >
                  <.icon name="hero-x-mark-solid" class="h-5 w-5" />
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
  Buttons allow users to take actions, and make choices, with a single tap.

  ## Examples

  ```heex
  <.button>
    Click me
  </.button>
  ```

  """

  attr :class, :any, doc: "Extend existing styles applied to the component."

  attr :rest, :global, include: ~w(disabled form name value)

  attr :color, :string,
    doc: "The button color.",
    default: "black",
    values: ["black", "green", "red", "orange", "grey", "light_grey", "light_orange", "special", "none", "turquoise"]

  attr :size, :string, default: "medium", values: ["medium", "small"]

  attr :type, :string,
    default: "submit",
    doc: "The button type.",
    values: ["submit", "button", "reset"]

  attr :variant, :string, default: "solid", values: ["outline", "solid", "ghost"]
  attr :new, :boolean, default: false

  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <button type={@type} class={button_styles(assigns)} {@rest}>
      {render_slot(@inner_block)}
    </button>
    """
  end

  def button_styles do
    button_styles(%{})
  end

  def button_styles(%{new: true} = assigns) do
    classes([
      "phx-submit-loading:opacity-75 phx-click-loading:opacity-75 phx-click-loading:cursor-default",
      "transition duration-100 ease-out",
      "inline-flex flex-row items-center justify-center",
      "cursor-pointer disabled:pointer-events-none border border-transparent whitespace-nowrap",
      button_styles(:color_new, assigns),
      button_styles(:size_new, assigns),
      assigns[:class]
    ])
  end

  def button_styles(assigns) do
    classes([
      "phx-submit-loading:opacity-75 phx-click-loading:opacity-75 phx-click-loading:cursor-default cursor-pointer rounded-md transition-all",
      "duration-200 border py-1 px-2 leading-6 rounded-lg",
      "text-sm disabled:opacity-40 disabled:pointer-events-none active:text-white/80",
      button_styles(:color, assigns),
      button_styles(:size, assigns),
      assigns[:class]
    ])
  end

  defp button_styles(:size_new, %{size: "medium"}) do
    "text-base/tight font-medium h-11 rounded-lg py-2 px-2.75 gap-2.5 [&>svg]:size-6"
  end

  defp button_styles(:size_new, %{size: "small"}) do
    "text-sm/tight font-medium rounded-md py-1.5 px-2 gap-1.5 [&>svg]:size-4"
  end

  defp button_styles(:size, %{size: "medium", variant: "solid"}) do
    "text-base py-1 px-2"
  end

  defp button_styles(:size, %{size: "small", variant: "solid"}) do
    "text-sm px-2 py-1"
  end

  defp button_styles(:size, %{size: "medium"}) do
    "text-base py-2 px-3"
  end

  defp button_styles(:size, %{size: "small"}) do
    "text-sm px-2 py-1"
  end

  defp button_styles(:size, _) do
    button_styles(:size, %{size: "medium"})
  end

  defp button_styles(:color_new, %{color: "special"}) do
    "text-white bg-black hover:bg-orange-700 active:bg-orange-800 disabled:bg-grey-400 disabled:text-grey-400"
  end

  defp button_styles(:color_new, %{color: "orange"}) do
    "text-white bg-orange-700 hover:bg-orange-800 active:bg-orange-900 disabled:bg-orange-400"
  end

  defp button_styles(:color_new, %{color: "turquoise"}) do
    "text-white bg-turquoise-700 hover:bg-turquoise-800 active:bg-turquoise-900 disabled:bg-turquoise-400"
  end

  defp button_styles(:color_new, %{color: "grey"}) do
    "text-white bg-grey-700 hover:bg-grey-800 active:bg-grey-900 disabled:bg-grey-600 disabled:text-grey-300"
  end

  defp button_styles(:color_new, %{color: "light_grey"}) do
    "text-grey-900 bg-grey-200 hover:bg-grey-300 active:bg-grey-400 disabled:bg-grey-100 disabled:text-grey-600"
  end

  defp button_styles(:color_new, %{variant: "outline"}) do
    "text-grey-900 border-grey-200 hover:bg-grey-200 active:bg-grey-300 disabled:text-grey-600 box-border"
  end

  defp button_styles(:color_new, %{variant: "ghost"}) do
    "text-grey-900 hover:bg-grey-200 active:bg-grey-700 active:text-white disabled:text-grey-600"
  end

  defp button_styles(:color, %{color: "none"}) do
    "hover:border-transparent border border-transparent text-darkGrey"
  end

  defp button_styles(:color, %{color: "light_orange"}) do
    "bg-orangeBg text-orangeText border-none hover:bg-[#f0e0d8] focus:outline-hidden focus:ring-1 focus:ring-orangeText"
  end

  defp button_styles(:color, %{color: "grey", variant: "outline"}) do
    classes([button_styles(:color, %{color: "black", variant: "outline"}), "font-normal"])
  end

  defp button_styles(:color, %{color: "grey"}) do
    "text-white border-darkGrey bg-darkGrey disabled:cursor-default disabled:text-white hover:opacity-60 disabled:bg-darkGrey"
  end

  defp button_styles(:color, %{variant: "outline", color: "light_grey"}) do
    "border border-greyButtonBg text-darkGrey hover:bg-greyButtonBg"
  end

  defp button_styles(:color, %{variant: "outline", color: "black"}) do
    "border-darkGrey text-darkGrey bg-transparent hover:text-white hover:bg-darkGrey disabled:cursor-default disabled:text-darkGrey disabled:bg-transparent"
  end

  defp button_styles(:color, %{variant: "outline", color: "green"}) do
    "border-blueText text-blueText bg-transparent hover:text-blueText hover:bg-greyButtonBg disabled:text-blueText disabled:cursor-default disabled:bg-transparent"
  end

  defp button_styles(:color, %{variant: "outline", color: "red"}) do
    "border-redText text-redText bg-transparent hover:text-white hover:bg-redText disabled:cursor-default disabled:bg-transparent"
  end

  defp button_styles(:color, %{variant: "outline", color: "orange"}) do
    "text-orangeText hover:bg-orangeBg disabled:pointer-events-none phx-click-loading:pointer-events-none"
  end

  defp button_styles(:color, %{color: "green"}) do
    "bg-blueText text-white hover:text-black hover:bg-greyButtonBg disabled:bg-blueText disabled:text-white disabled:cursor-default"
  end

  defp button_styles(:color, %{color: "black"}) do
    "text-white bg-black hover:bg-greyButtonBg hover:text-black disabled:cursor-default disabled:bg-black disabled:text-white"
  end

  defp button_styles(:color, %{color: "orange"}) do
    "text-white border-none bg-orangeText hover:bg-orangeBg hover:text-orangeText disabled:cursor-default disabled:bg-orangeText disabled:text-white phx-click-loading:bg-orangeText phx-click-loading:text-white"
  end

  defp button_styles(:color, %{color: "light_grey"}) do
    "bg-greyButtonBg hover:border-transparent Grey border border-transparent text-darkGrey"
  end

  defp button_styles(:color, %{variant: "outline"}), do: button_styles(:color, %{color: "black", variant: "outline"})

  defp button_styles(:color, _), do: button_styles(:color, %{color: "black"})

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
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as hidden and radio,
  are best written directly in your templates.

  ## Examples

      <.input field={@form[:email]} type="email" />
      <.input name="my-input" errors={["oh no!"]} />
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               range search select tel text textarea time url week hidden radio)

  attr :field, FormField, doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"

  attr :input_class, :string, default: nil, doc: "the class to apply to the input tag"
  attr :container_class, :string, default: nil, doc: "the class to apply to the container div"

  attr :color, :string,
    default: nil,
    values: [nil, "black", "green", "red", "orange", "light_grey", "light_orange"]

  attr :size, :string,
    default: nil,
    values: [nil, "medium", "small"]

  attr :input_size, :integer, default: nil

  attr :new, :boolean, default: false, doc: "new redesigned input"

  attr :is_tooltip, :boolean, default: false

  attr :rest, :global, include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input
      type="hidden"
      name={@name}
      id={@id}
      value={Form.normalize_value(@type, @value)}
      {@rest}
    />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div>
      <label
        phx-disable-with=""
        class={
          classes([
            "relative cursor-pointer has-[:disabled]:opacity-50 has-[:disabled]:cursor-default flex items-center font-normal text-darkGrey",
            @rest[:class]
          ])
        }
      >
        <input type="hidden" name={@name} value="false" disabled={@rest[:disabled]} />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          phx-disable-with=""
          checked={@checked}
          disabled={@rest[:disabled]}
          class="w-4 h-4 border text-darkGrey border-darkGrey rounded-[3px] focus:ring-0"
          {@rest}
        />
        <span class="ml-1 text-darkGrey text-sm">{@label}</span>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select", new: true} = assigns) do
    ~H"""
    <div class={@container_class}>
      <.label :if={@label} for={@id} class="mb-2">{@label}</.label>
      <div class="relative">
        <select
          id={@id}
          name={@name}
          class={
            classes([
              "py-1.5 px-3 pr-10 border rounded-lg border-grey-200 bg-grey-50 text-grey-900 text-base/tight w-full bg-none peer",
              @rest[:class]
            ])
          }
          multiple={@multiple}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Form.options_for_select(@options, @value)}
        </select>
        <Lucideicons.chevron_down class="absolute right-3 top-1/2 -translate-y-1/2 pointer-events-none size-4 text-grey-700 peer-disabled:text-grey-300" />
      </div>
      <.error :for={msg <- @errors} is_tooltip={@is_tooltip} target={@id}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class={@container_class}>
      <.label :if={@label} for={@id} class="mb-2">{@label}</.label>
      <select
        id={@id}
        name={@name}
        class={
          classes([
            "block w-full rounded border border-gray-300 bg-white focus:border-zinc-400 focus:ring-0 sm:text-sm",
            @rest[:class],
            @color && button_styles(:color, %{color: @color}),
            @size && button_styles(:size, %{size: @size})
          ])
        }
        multiple={@multiple}
        {@rest}
      >
        <option :if={@prompt} value="">{@prompt}</option>
        {Form.options_for_select(@options, @value)}
      </select>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea", new: true} = assigns) do
    ~H"""
    <div class={@rest[:class]}>
      <.label :if={@label} for={@id} class="mb-2">{@label}</.label>
      <textarea
        id={@id}
        name={@name}
        class={
          classes([
            "py-1.5 px-3 border rounded-lg bg-white text-grey-900 placeholder:text-grey-500 leading-tight w-full min-h-[3rem] resize-none",
            "border-grey-200 focus:border-grey-400 [&[aria-invalid=\"true\"]]:border-rose-400"
          ])
        }
        aria-invalid={to_string(not Enum.empty?(@errors))}
        {@rest}
      ><%= Form.normalize_value("textarea", @value) %></textarea>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div>
      <.label for={@id}>{@label}</.label>
      <textarea
        id={@id}
        name={@name}
        class={
          classes([
            "mt-2 block w-full rounded text-zinc-900 focus:ring-0 sm:text-sm sm:leading-6 min-h-[6rem]",
            @errors == [] && "border-zinc-300 focus:border-zinc-400",
            @errors != [] && "border-rose-400 focus:border-rose-400",
            @rest[:class]
          ])
        }
        {@rest}
      ><%= Form.normalize_value("textarea", @value) %></textarea>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(%{new: true} = assigns) do
    ~H"""
    <div class={@rest[:class]}>
      <.label :if={@label} for={@id} class={classes(["mb-2", @rest[:class]])}>{@label}</.label>
      <input
        type={@type}
        name={@name}
        id={@id}
        size={@input_size}
        value={Form.normalize_value(@type, @value)}
        aria-invalid={to_string(not Enum.empty?(@errors))}
        class={
          classes([
            "py-1.5 px-3 border rounded-lg bg-white text-grey-900 placeholder:text-grey-500 leading-tight w-full border-grey-200 focus:border-grey-400 [&[aria-invalid=\"true\"]]:border-rose-400",
            @type == "number" &&
              "[appearance:textfield] [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none",
            @input_class
          ])
        }
        {@rest}
      />
    </div>
    """
  end

  def input(assigns) do
    ~H"""
    <div class={@rest[:class]}>
      <.label :if={@label} for={@id} class={classes(["mb-2", @rest[:class]])}>{@label}</.label>
      <input
        type={@type}
        name={@name}
        id={@id}
        size={@input_size}
        value={Form.normalize_value(@type, @value)}
        class={
          classes([
            "block w-full rounded text-zinc-900 focus:ring-0 sm:text-sm sm:leading-6 read-only:cursor-default read-only:bg-gray-100",
            @errors == [] && "border-zinc-300 focus:border-zinc-400",
            @errors != [] && "border-rose-400 focus:border-rose-400",
            @input_class
          ])
        }
        {@rest}
      />
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  @doc """
  Renders a label.
  """
  attr :for, :string, default: nil
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def label(assigns) do
    ~H"""
    <label for={@for} class={classes(["block text-sm leading-6
      text-zinc-800", @class])}>
      {render_slot(@inner_block)}
    </label>
    """
  end

  @doc """
  Generates a generic error message.
  """
  attr :target, :string, default: nil, doc: "ID of an element that error will bind to"
  attr :is_tooltip, :boolean, default: false
  slot :inner_block, required: true

  def error(%{is_tooltip: true} = assigns) do
    ~H"""
    <div
      :if={@target}
      id={"error_msg_#{@target}"}
      phx-hook="FloatingUIError"
      data-for={@target}
      class="
        absolute top-0 left-0
        bg-[#A22A2A]
        text-[#FBF4F4]
        text-sm font-normal
        px-3 py-1.5
        rounded
        flex justify-center items-center
        shadow-[0_2px_8px_rgba(0,0,0,0.15)]
        w-40 h-18
      "
    >
      <div class="flex items-center gap-2">
        <.icon name="hero-information-circle" class="mt-0.5 h-5 w-5 flex-none" />
        {render_slot(@inner_block)}
      </div>

      <div
        id={"arrow_#{@target}"}
        class="
      absolute
      w-2.5 h-2.5
      bg-[#A22A2A]
      rotate-45
      left-1/2 -translate-x-1/2
      -bottom-[5px]
    "
      >
      </div>
    </div>
    """
  end

  def error(assigns) do
    ~H"""
    <p class="mt-3 flex gap-3 text-sm leading-6 text-rose-600">
      <.icon name="hero-exclamation-circle-mini" class="mt-0.5 h-5 w-5 flex-none" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  attr :id, :string, required: true
  slot :inner_block, required: true
  slot :trigger, required: true, doc: "the slot for the trigger element"

  def dropdown(assigns) do
    ~H"""
    <div class="relative">
      <button
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
        class="duration-75 inline-flex"
      >
        {render_slot(@trigger)}
      </button>
      <div
        id={"dropdown_menu_#{@id}"}
        style="display: none"
        class="absolute right-0 top-1 z-20 max-w-[calc(100vw-2rem)]"
      >
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  attr :class, :string, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def avatar(assigns) do
    ~H"""
    <div class={classes(["relative overflow-hidden rounded-full", @class])} {@rest}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :class, :string, default: nil
  attr :src, :string
  attr :rest, :global

  def avatar_image(assigns) do
    ~H"""
    <img
      class={
        classes([
          "aspect-square h-full w-full object-cover ",
          (!@src || @src === "") && "hidden",
          @class
        ])
      }
      src={@src}
      {@rest}
    />
    """
  end

  attr :class, :string, default: nil
  attr :rest, :global
  slot :inner_block, required: false

  def avatar_fallback(assigns) do
    ~H"""
    <span
      class={
        classes([
          "flex h-full w-full items-center justify-center rounded-full bg-lightGreyBg",
          @class
        ])
      }
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
  attr :class, :string, default: nil

  slot :radio, required: true do
    attr :value, :string, required: true
  end

  slot :inner_block

  def radio_group(assigns) do
    ~H"""
    <div class={classes(["flex gap-2 ", @class])}>
      {render_slot(@inner_block)}
      <div :for={{%{value: value} = rad, idx} <- Enum.with_index(@radio)} }>
        <label
          for={"#{@field.id}-#{idx}"}
          class="relative cursor-pointer has-[:disabled]:opacity-50 has-[:disabled]:cursor-default flex items-center"
        >
          <input
            type="radio"
            name={@field.name}
            id={"#{@field.id}-#{idx}"}
            phx-disable-with=""
            value={value}
            checked={to_string(@field.value) == to_string(value)}
            class="hidden"
          />
          <div class="w-4 h-4 border text-darkGrey border-darkGrey rounded-[3px] flex items-center justify-center">
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
          <span class="ml-1 text-darkGrey text-sm">{render_slot(rad)}</span>
        </label>
      </div>
    </div>
    """
  end

  @doc """
  Renders a header with title.
  """
  attr :class, :string, default: nil

  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={classes([@actions != [] && "flex items-center justify-between gap-6", @class])}>
      <div>
        <h1 class="text-lg font-semibold leading-8 text-zinc-800">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="mt-2 text-sm leading-6 text-zinc-600">
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
  attr :class, :string, default: nil
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
    <table class={classes([@class])}>
      <thead class="text-sm text-left leading-6 text-zinc-500">
        <tr>
          <th :for={col <- @col} class="p-0 pr-2 font-normal uppercase
            text-darkGrey">
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
        class="relative divide-y divide-lightGreyBg border-t border-lightGreyBg text-sm leading-6 text-zinc-700"
      >
        <tr
          :for={row <- @rows}
          id={@row_id && @row_id.(row)}
          class="group hover:bg-white transition-colors"
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
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title"><%= @post.title %></:item>
        <:item title="Views"><%= @post.views %></:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <div class="mt-14">
      <dl class="-my-4 divide-y divide-zinc-100">
        <div :for={item <- @item} class="flex gap-4 py-4 text-sm leading-6 sm:gap-8">
          <dt class="w-1/4 flex-none text-zinc-500">{item.title}</dt>
          <dd class="text-zinc-700">{render_slot(item)}</dd>
        </div>
      </dl>
    </div>
    """
  end

  @doc """
  Renders a back navigation link.

  ## Examples

      <.back navigate={~p"/posts"}>Back to posts</.back>
  """
  attr :navigate, :any, required: true
  slot :inner_block, required: true

  def back(assigns) do
    ~H"""
    <div class="mt-16">
      <.link navigate={@navigate} class="text-sm font-semibold leading-6 hover:text-darkGrey">
        <.icon name="hero-arrow-left-solid" class="h-3 w-3" />
        {render_slot(@inner_block)}
      </.link>
    </div>
    """
  end

  attr :active_months, :list, default: nil
  attr :selected_date, :string, required: true
  attr :disabled, :boolean, default: false
  attr :rest, :global
  attr :class, :string, default: nil
  attr :value, :string, default: nil

  def date_picker(assigns) do
    ~H"""
    <label class={
      classes([
        button_styles(%{color: "light_grey", size: "medium", new: true}),
        "w-44 justify-start group max-md:hidden has-disabled:bg-grey-100 has-disabled:text-grey-600",
        @class
      ])
    }>
      <Lucideicons.calendar_1 />
      <input
        type="button"
        phx-hook="AirDatepicker"
        value={@value}
        data-enabled-months={
          @active_months && @active_months |> Enum.map(&Date.to_iso8601/1) |> Enum.join(",")
        }
        data-initial-date={@selected_date}
        disabled={@disabled}
        {@rest}
      />
    </label>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in your `assets/tailwind.config.js`.

  ## Examples

      <.icon name="hero-x-mark-solid" />
      <.icon name="hero-arrow-path" class="ml-1 w-3 h-3 animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :string, default: nil

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  attr :id, :string, required: true
  attr :reference_id, :string, required: true
  attr :class, :string, default: nil

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
        class={classes(["absolute w-max top-0 left-0 z-50 pointer-events-auto hidden", @class])}
        role="dialog"
        phx-hook="Popover"
        phx-remove={hide_popover(@id)}
        phx-click-away={hide_popover(@id)}
        phx-window-keydown={hide_popover(@id)}
        phx-key="escape"
        id={@id}
        data-reference={@reference_id}
        data-placement={@placement}
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
  attr :class, :string, default: nil
  attr :disabled, :boolean, default: false
  attr :color, :string, values: ["orange", "turquoise"], default: "orange"
  attr :rest, :global

  slot :label_slot

  def switch(assigns) do
    ~H"""
    <label class={classes(["inline-flex items-center gap-2 cursor-pointer", @class])}>
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
        class="sr-only peer"
        disabled={@disabled}
        {@rest}
      />
      <div class={[
        "p-[3px] relative w-[49px] h-[26px] bg-grey-200 rounded-full disabled:opacity-50
                  transition-colors after:transition-transform
                  duration-200 ease-out after:duration-200 after:ease-out
                  peer-checked:after:translate-x-[23px]
                  after:content-[''] after:absolute after:rounded-full after:size-5 after:bg-white",
        @color == "orange" && "peer-checked:bg-orange-700",
        @color == "turquoise" && "peer-checked:bg-turquoise-700"
      ]}>
      </div>
      <span :if={@label} class="text-grey-900">{@label}</span>
      <%!-- hack: label_slot is a list of slots --%>
      <span :if={Enum.any?(@label_slot)} class="text-grey-900 flex flex-row">
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

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(FirmowidWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(FirmowidWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end

  @doc "Top-level navbar container. Pair with `navbar_logo/1`."
  attr :class, :any, default: nil
  attr :rest, :global

  slot :inner_block

  def navbar(assigns) do
    ~H"""
    <nav class={["px-4 sm:px-6 lg:px-8 bg-black text-white", @class]} {@rest}>
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
  attr :class, :string, default: nil
  attr :rest, :global

  def navbar_logo(assigns) do
    ~H"""
    <%= if @navigate do %>
      <.link
        navigate={@navigate}
        class={[
          "font-extrabold text-xl inline-block tracking-wide text-offwhite",
          @class
        ]}
        {@rest}
      >
        Firmowid
      </.link>
    <% else %>
      <span
        class={[
          "font-extrabold text-xl inline-block tracking-wide text-offwhite",
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
