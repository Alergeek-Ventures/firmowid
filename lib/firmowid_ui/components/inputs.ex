defmodule FirmowidUI.Components.Inputs do
  @moduledoc "Shared form inputs, labels, validation messages and icons."

  use FirmowidUI, :html

  alias Phoenix.HTML.Form
  alias Phoenix.HTML.FormField
  alias Phoenix.LiveView.Rendered

  @doc "Renders an input with label and error messages, optionally from a form field."
  @spec input(map()) :: Rendered.t()
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

  attr :selected_labels, :map,
    default: %{},
    doc: "alternate labels keyed by select option value"

  attr :input_class, :any, default: nil, doc: "the class to apply to the input tag"
  attr :container_class, :string, default: nil, doc: "the class to apply to the container div"

  attr :is_tooltip, :boolean, default: false

  attr :show_error, :boolean,
    default: true,
    doc:
      "when set to false, error messages will not be displayed, but the input will still be marked as invalid (useful for custom error message)"

  attr :rest, :global, include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  slot :label_slot

  def input(%{field: %FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> field.name end)
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
        class={[
          "relative flex cursor-pointer items-center font-normal text-grey-700 has-disabled:cursor-default has-disabled:opacity-50",
          @rest[:class]
        ]}
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
          class="size-4 rounded-[3px] border border-grey-700 text-grey-700 focus:ring-0 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-(--focus-ring)"
          {@rest}
        />
        <span class="ml-1 text-sm text-grey-700">{@label}</span>
      </label>
      <.error :for={msg <- @errors} :if={@show_error}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class={@container_class}>
      <.label :if={@label} for={@id} class="mb-2">{@label}</.label>
      <div class="relative">
        <select
          id={@id}
          name={@name}
          phx-hook={@selected_labels != %{} && "SelectLabelOverride"}
          data-prompt={@prompt}
          data-selected-labels={Jason.encode!(@selected_labels)}
          class={[
            "peer w-full rounded-lg border border-grey-200 bg-grey-50 bg-none px-3 py-1.5 pr-10 text-base/tight focus:border-grey-700 focus:ring-0",
            if(@selected_labels != %{},
              do: "text-transparent",
              else: if(@prompt && @value in [nil, ""], do: "text-grey-300", else: "text-grey-900")
            ),
            @input_class,
            @rest[:class]
          ]}
          {@rest}
        >
          <option :if={@prompt} value="" disabled selected={@value in [nil, ""]} hidden>
            {@prompt}
          </option>
          {Form.options_for_select(@options, @value)}
        </select>
        <span
          :if={@selected_labels != %{}}
          aria-hidden="true"
          data-select-label-override
          class={[
            "pointer-events-none absolute top-1/2 left-3 -translate-y-1/2 text-base/tight",
            if(@value in [nil, ""], do: "text-grey-300", else: "text-grey-900")
          ]}
        >
          {if(@value in [nil, ""],
            do: @prompt,
            else: Map.get(@selected_labels, @value, selected_option_label(@options, @value))
          )}
        </span>
        <Lucideicons.chevron_down class="pointer-events-none absolute top-1/2 right-3 size-4 -translate-y-1/2 text-grey-700 peer-disabled:text-grey-300" />
      </div>
      <.error :for={msg <- @errors} :if={@show_error} is_tooltip={@is_tooltip} target={@id}>
        {msg}
      </.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class={@rest[:class]}>
      <.label :if={@label} for={@id} class="mb-2">{@label}</.label>
      <textarea
        id={@id}
        name={@name}
        class={[
          "min-h-12 w-full resize-none rounded-lg border border-grey-200 bg-white px-3 py-1.5 leading-tight text-grey-900 placeholder:text-grey-500 focus:border-grey-700 focus:ring-0 aria-invalid:border-brick-700",
          @input_class
        ]}
        aria-invalid={to_string(not Enum.empty?(@errors))}
        {@rest}
      ><%= Form.normalize_value("textarea", @value) %></textarea>
      <.error :for={msg <- @errors} :if={@show_error} is_tooltip={@is_tooltip} target={@id}>
        {msg}
      </.error>
    </div>
    """
  end

  def input(assigns) do
    ~H"""
    <div class={@rest[:class]}>
      <.label :if={@label || Enum.any?(@label_slot)} for={@id} class={["mb-2", @rest[:class]]}>
        {if Enum.any?(@label_slot), do: render_slot(@label_slot), else: @label}
      </.label>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Form.normalize_value(@type, @value)}
        aria-invalid={to_string(not Enum.empty?(@errors))}
        class={[
          "w-full rounded-lg border border-grey-200 bg-white px-3 py-1.5 leading-tight text-grey-900 placeholder:text-grey-500 focus:border-grey-700 focus:ring-0 aria-invalid:border-brick-700",
          @type == "number" &&
            "[appearance:textfield] [&::-webkit-inner-spin-button]:appearance-none [&::-webkit-outer-spin-button]:appearance-none",
          @input_class
        ]}
        {@rest}
      />
      <.error :for={msg <- @errors} :if={@show_error} is_tooltip={@is_tooltip} target={@id}>
        {msg}
      </.error>
    </div>
    """
  end

  defp selected_option_label(options, value) do
    Enum.find_value(options, fn
      {label, ^value} -> label
      option when option == value -> option
      _option -> nil
    end)
  end

  @doc "Renders a label."
  @spec label(map()) :: Rendered.t()
  attr :for, :string, default: nil
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def label(assigns) do
    ~H"""
    <label for={@for} class={["block text-sm/6 text-grey-900", @class]}>
      {render_slot(@inner_block)}
    </label>
    """
  end

  @doc "Generates a generic error message."
  @spec error(map()) :: Rendered.t()
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
      class="absolute top-0 left-0 z-10 flex items-center justify-center rounded bg-brick-700 px-4 py-3 text-sm font-normal text-brick-100 shadow-[0_2px_8px_rgba(0,0,0,0.15)]"
    >
      <div class="flex items-center gap-2">
        <.icon name="hero-information-circle" class="mt-0.5 size-5 flex-none" />
        {render_slot(@inner_block)}
      </div>

      <div
        id={"arrow_#{@target}"}
        class="absolute bottom-[-5px] left-1/2 size-2.5 -translate-x-1/2 rotate-45 bg-brick-700"
      >
      </div>
    </div>
    """
  end

  def error(assigns) do
    ~H"""
    <p class="mt-3 flex gap-3 text-sm/6 text-brick-600">
      <.icon name="hero-exclamation-circle-mini" class="mt-0.5 size-5 flex-none" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc "Renders a Heroicon using its bundled CSS class."
  @spec icon(map()) :: Rendered.t()
  attr :name, :string, required: true
  attr :class, :any, default: nil

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  @doc "Translates an error message using gettext."
  @spec translate_error({String.t(), keyword()}) :: String.t()
  def translate_error({msg, opts}) do
    translated =
      if count = opts[:count] do
        Gettext.dngettext(Firmowid.Gettext, "errors", msg, msg, count, opts)
      else
        Gettext.dgettext(Firmowid.Gettext, "errors", msg, opts)
      end

    localize_common_error(translated, opts)
  end

  defp localize_common_error("is required", _opts), do: "jest wymagane"
  defp localize_common_error("must be present", _opts), do: "jest wymagane"
  defp localize_common_error("can't be blank", _opts), do: "nie może być puste"
  defp localize_common_error("is invalid", _opts), do: "jest nieprawidłowe"
  defp localize_common_error("has invalid format", _opts), do: "ma nieprawidłowy format"
  defp localize_common_error("has already been taken", _opts), do: "jest już zajęte"
  defp localize_common_error("must be accepted", _opts), do: "musi zostać zaakceptowane"

  defp localize_common_error("does not match confirmation", _opts), do: "nie zgadza się z potwierdzeniem"

  defp localize_common_error("is reserved", _opts), do: "jest zarezerwowane"
  defp localize_common_error("has an invalid entry", _opts), do: "zawiera nieprawidłowy element"

  defp localize_common_error("is still associated with this entry", _opts), do: "jest nadal powiązane z tym wpisem"

  defp localize_common_error("are still associated with this entry", _opts), do: "są nadal powiązane z tym wpisem"

  defp localize_common_error("should be %{count} character(s)", opts),
    do: interpolate_error("powinno mieć %{count} znak(ów)", opts)

  defp localize_common_error("should be at least %{count} character(s)", opts),
    do: interpolate_error("powinno mieć co najmniej %{count} znak(ów)", opts)

  defp localize_common_error("should be at most %{count} character(s)", opts),
    do: interpolate_error("powinno mieć co najwyżej %{count} znak(ów)", opts)

  defp localize_common_error("should be %{count} byte(s)", opts),
    do: interpolate_error("powinno mieć %{count} bajt(ów)", opts)

  defp localize_common_error("should be at least %{count} byte(s)", opts),
    do: interpolate_error("powinno mieć co najmniej %{count} bajt(ów)", opts)

  defp localize_common_error("should be at most %{count} byte(s)", opts),
    do: interpolate_error("powinno mieć co najwyżej %{count} bajt(ów)", opts)

  defp localize_common_error("should have %{count} item(s)", opts),
    do: interpolate_error("powinno mieć %{count} element(ów)", opts)

  defp localize_common_error("should have at least %{count} item(s)", opts),
    do: interpolate_error("powinno mieć co najmniej %{count} element(ów)", opts)

  defp localize_common_error("should have at most %{count} item(s)", opts),
    do: interpolate_error("powinno mieć co najwyżej %{count} element(ów)", opts)

  defp localize_common_error("must be less than %{number}", opts),
    do: interpolate_error("musi być mniejsze niż %{number}", opts)

  defp localize_common_error("must be greater than %{number}", opts),
    do: interpolate_error("musi być większe niż %{number}", opts)

  defp localize_common_error("must be less than or equal to %{number}", opts),
    do: interpolate_error("musi być mniejsze lub równe %{number}", opts)

  defp localize_common_error("must be greater than or equal to %{number}", opts),
    do: interpolate_error("musi być większe lub równe %{number}", opts)

  defp localize_common_error("must be equal to %{number}", opts), do: interpolate_error("musi być równe %{number}", opts)

  defp localize_common_error("length must be greater than or equal to %{min}", opts),
    do: interpolate_error("długość musi być większa lub równa %{min}", opts)

  defp localize_common_error("length must be less than or equal to %{max}", opts),
    do: interpolate_error("długość musi być mniejsza lub równa %{max}", opts)

  defp localize_common_error("must match the pattern %{regex}", opts),
    do: interpolate_error("musi pasować do wzorca %{regex}", opts)

  defp localize_common_error(message, _opts) when is_binary(message) do
    cond do
      Regex.match?(~r/^length must be greater than or equal to \d+$/, message) ->
        String.replace_prefix(
          message,
          "length must be greater than or equal to ",
          "długość musi być większa lub równa "
        )

      Regex.match?(~r/^length must be less than or equal to \d+$/, message) ->
        String.replace_prefix(
          message,
          "length must be less than or equal to ",
          "długość musi być mniejsza lub równa "
        )

      true ->
        message
    end
  end

  defp interpolate_error(message, opts) do
    Regex.replace(~r"%\{(\w+)\}", message, fn _, key ->
      opts
      |> stringify_error_opts()
      |> Map.get(key, key)
      |> to_string()
    end)
  end

  defp stringify_error_opts(opts) do
    Map.new(opts, fn {key, value} -> {to_string(key), value} end)
  end

  @doc "Translates the errors for a field from a keyword list of errors."
  @spec translate_errors(keyword(), atom()) :: [String.t()]
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
