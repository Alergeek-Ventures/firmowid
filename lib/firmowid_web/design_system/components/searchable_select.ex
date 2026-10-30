defmodule FirmowidWeb.DesignSystem.Components.SearchableSelect do
  @moduledoc """
  Select field for long option lists: the user types to narrow the options and picks one with the
  mouse or the keyboard.
  """

  use FirmowidWeb, :html

  alias Phoenix.HTML.FormField
  alias Phoenix.LiveView.Rendered

  @doc """
  Renders a searchable select for a form field.

  Options use the `Phoenix.HTML.Form.options_for_select/2` shapes `{label, value}` and
  `{group_label, [{label, value}]}`. The chosen value travels in a hidden input, so the form
  receives it like a regular select and `phx-change` fires on every choice.
  """
  @spec searchable_select(map()) :: Rendered.t()
  attr :field, FormField, required: true
  attr :options, :list, required: true
  attr :prompt, :string, default: nil
  attr :rest, :global, include: ~w(required)

  def searchable_select(%{field: field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []
    selected = to_string(field.value || "")

    assigns =
      assign(assigns,
        id: field.id,
        value: selected,
        label: selected_label(assigns.options, selected),
        errors: Enum.map(errors, &translate_error/1)
      )

    ~H"""
    <div id={"#{@id}-searchable"} phx-hook=".SearchableSelect">
      <%!-- A hidden text input instead of type="hidden", so LiveView treats the field as unused
      until a choice and does not show its errors early. --%>
      <input
        type="text"
        hidden
        tabindex="-1"
        name={@field.name}
        value={@value}
        data-searchable-value
      />
      <div class="relative">
        <input
          id={@id}
          type="text"
          role="combobox"
          autocomplete="off"
          spellcheck="false"
          autocapitalize="off"
          aria-autocomplete="list"
          aria-expanded="false"
          aria-controls={"#{@id}-listbox"}
          aria-invalid={to_string(@errors != [])}
          value={@label}
          placeholder={@prompt}
          data-searchable-input
          class="w-full rounded-lg border border-grey-200 bg-grey-50 px-3 py-1.5 pr-10 text-base/tight text-grey-900 placeholder:text-grey-300 focus:border-grey-700 focus:ring-0 aria-invalid:border-brick-700"
          {@rest}
        />
        <Lucideicons.chevron_down class="pointer-events-none absolute top-1/2 right-3 size-4 -translate-y-1/2 text-grey-700" />
        <div
          id={"#{@id}-listbox"}
          role="listbox"
          hidden
          class="absolute inset-x-0 top-full z-20 mt-1 max-h-72 overflow-y-auto rounded-lg border border-grey-200 bg-white p-1 shadow-lg"
        >
          <%= for option <- @options do %>
            <%= case option do %>
              <% {group, group_options} when is_list(group_options) -> %>
                <div role="group" aria-label={group} data-searchable-group>
                  <p
                    aria-hidden="true"
                    class="px-2 pt-2 pb-1 text-xs font-medium tracking-wide text-grey-600 uppercase"
                  >
                    {group}
                  </p>
                  <.option
                    :for={{label, value} <- group_options}
                    id={@id}
                    label={label}
                    value={value}
                    selected={value == @value}
                  />
                </div>
              <% {label, value} -> %>
                <.option id={@id} label={label} value={value} selected={value == @value} />
            <% end %>
          <% end %>
          <p
            hidden
            data-searchable-empty
            aria-live="polite"
            class="px-2 py-1.5 text-sm text-grey-600"
          >
            {gettext("No matches found.")}
          </p>
        </div>
      </div>
      <.error :for={msg <- @errors}>{msg}</.error>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".SearchableSelect">
        // Matches regardless of case and Polish diacritics, so "lotwa" finds "Łotwa".
        const normalize = (text) =>
          text.normalize("NFD").replace(/\p{M}/gu, "").replace(/ł/gi, "l").toLowerCase();

        export default {
          mounted() {
            this.input = this.el.querySelector("[data-searchable-input]");
            this.hidden = this.el.querySelector("[data-searchable-value]");
            this.list = this.el.querySelector("[role=listbox]");
            this.query = null;
            this.active = null;

            this.input.addEventListener("focus", () => this.open());
            this.input.addEventListener("click", () => this.query === null && this.open());
            // The typed text is only a search query, so the form must not see it as a change.
            this.input.addEventListener("input", (event) => {
              event.stopPropagation();
              this.filter(this.input.value);
            });
            this.input.addEventListener("change", (event) => event.stopPropagation());
            this.input.addEventListener("keydown", (event) => this.onKeydown(event));
            this.input.addEventListener("blur", () => this.close());
            // Keeps focus in the input so a click does not close the list before it selects.
            this.list.addEventListener("mousedown", (event) => event.preventDefault());
            this.list.addEventListener("click", (event) => {
              const option = event.target.closest("[role=option]");
              if (option) this.choose(option);
            });
          },
          updated() {
            this.render();
            if (this.query === null) this.input.value = this.selectedLabel();
          },
          options() {
            return [...this.list.querySelectorAll("[role=option]")];
          },
          visibleOptions() {
            return this.options().filter((option) => !option.hidden);
          },
          selectedLabel() {
            const selected = this.options().find((option) => option.dataset.value === this.hidden.value);
            return selected ? selected.dataset.label : "";
          },
          open() {
            this.input.select();
            this.filter("");
            const selected = this.options().find((option) => option.dataset.value === this.hidden.value);
            if (selected) this.activate(selected);
          },
          filter(query) {
            this.query = query;
            this.active = null;
            this.render();
            if (query.trim() !== "") this.activate(this.visibleOptions()[0]);
          },
          close() {
            this.query = null;
            this.active = null;
            this.input.value = this.selectedLabel();
            this.render();
          },
          render() {
            const query = normalize((this.query || "").trim());

            this.options().forEach((option) => {
              const label = normalize(option.dataset.label);
              const words = label.split(/[\s-]+/);
              option.hidden =
                query !== "" &&
                !label.startsWith(query) &&
                !words.some((word) => word.startsWith(query)) &&
                option.dataset.value.toLowerCase() !== query;
              option.toggleAttribute("data-active", option === this.active);
            });

            this.list.querySelectorAll("[data-searchable-group]").forEach((group) => {
              group.hidden = !group.querySelector("[role=option]:not([hidden])");
            });

            const empty = this.visibleOptions().length === 0;
            this.list.querySelector("[data-searchable-empty]").hidden = !empty;
            this.list.hidden = this.query === null;
            this.input.setAttribute("aria-expanded", String(this.query !== null));

            if (this.active) {
              this.input.setAttribute("aria-activedescendant", this.active.id);
            } else {
              this.input.removeAttribute("aria-activedescendant");
            }
          },
          activate(option) {
            this.active = option || null;
            this.render();
            this.active?.scrollIntoView({block: "nearest"});
          },
          move(step) {
            const options = this.visibleOptions();
            const index = options.indexOf(this.active);
            const next = index === -1 ? (step > 0 ? 0 : options.length - 1) : index + step;
            if (options[next]) this.activate(options[next]);
          },
          choose(option) {
            this.options().forEach((each) => each.setAttribute("aria-selected", String(each === option)));

            if (this.hidden.value !== option.dataset.value) {
              this.hidden.value = option.dataset.value;
              this.hidden.dispatchEvent(new Event("input", {bubbles: true}));
            }

            this.close();
          },
          onKeydown(event) {
            if (event.key === "ArrowDown" || event.key === "ArrowUp") {
              event.preventDefault();
              if (this.query === null) this.open();
              this.move(event.key === "ArrowDown" ? 1 : -1);
            } else if (event.key === "Enter" && this.query !== null) {
              event.preventDefault();
              const option = this.active || this.visibleOptions()[0];
              if (option) this.choose(option);
            } else if (event.key === "Escape" && this.query !== null) {
              // Closes only the list, not a modal around it.
              event.preventDefault();
              event.stopPropagation();
              this.close();
            }
          },
        };
      </script>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :selected, :boolean, required: true

  defp option(assigns) do
    ~H"""
    <div
      id={"#{@id}-option-#{@value}"}
      role="option"
      aria-selected={to_string(@selected)}
      data-value={@value}
      data-label={@label}
      class="group flex cursor-pointer items-center justify-between gap-2 rounded-md px-2 py-1.5 text-sm text-grey-700 hover:bg-grey-100 data-active:bg-grey-100"
    >
      <span class="min-w-0">{@label}</span>
      <.icon name="hero-check-mini" class="invisible size-4 shrink-0 group-aria-selected:visible" />
    </div>
    """
  end

  defp selected_label(options, value) do
    options
    |> Enum.flat_map(fn
      {_group, group_options} when is_list(group_options) -> group_options
      option -> [option]
    end)
    |> Enum.find_value("", fn {label, option_value} -> if option_value == value, do: label end)
  end
end
