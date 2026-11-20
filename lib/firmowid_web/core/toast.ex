defmodule FirmowidWeb.Core.Toast do
  @moduledoc """
  Toast styling, content and copy for `LiveToast.toast_group/1`.
  """

  use Phoenix.Component
  use Gettext, backend: Firmowid.Gettext

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias Phoenix.LiveView.JS
  alias Phoenix.LiveView.Rendered

  @doc """
  Generates CSS classes for flash/toast messages based on the assigns.

  Two layouts, as Figma's "Toast" component (General components, Toasty
  [DESIGN.md]) measures them: a message with an action (Undo) sits on one
  centred line, 52px tall at least; a message with a title starts at the top,
  76px tall at least. LiveToast's own close button is hidden: `toast_content/1`
  renders the one from the design, and only when there is no action.
  """
  def toast_class_fn(assigns) do
    [
      # base classes
      "group/toast z-100 pointer-events-auto relative w-full min-h-13 items-center gap-3 origin-center overflow-hidden rounded-sm border border-grey-700/10 px-4 py-3 shadow-small col-start-1 col-end-1 row-start-1 row-end-2",
      "has-[[data-part=title]]:min-h-19 has-[[data-part=title]]:items-start has-[[data-part=title]]:py-4",
      "[&>button:not([data-part])]:hidden",
      # keep compositing stable while live_toast animates transform/opacity
      "will-change-transform backface-hidden",
      # used to hide the disconnected flashes
      if(assigns[:rest][:hidden] == true, do: "hidden", else: "flex"),
      # override styles per severity
      assigns[:kind] == :success && "bg-moss-200 text-moss-700",
      assigns[:kind] == :notice && "bg-teal-200 text-teal-800",
      assigns[:kind] == :info && "bg-grey-100 text-black",
      assigns[:kind] == :error && "!text-brick-700 !bg-brick-200"
    ]
  end

  @doc """
  Keeps toasts above every other layer, including modals, the assistant and the
  cookie banner, and 384px wide (the group's 16px padding on either side).
  """
  def group_class_fn(assigns) do
    classes =
      assigns
      |> LiveToast.group_class_fn()
      |> List.wrap()
      |> Enum.map(fn
        class when is_binary(class) -> String.replace(class, "md:max-w-[420px]", "md:max-w-104")
        class -> class
      end)

    [classes, "z-110!"]
  end

  @doc """
  Renders toast content: the icon of its kind, an optional title, the message,
  and either its action or a close button.

  LiveToast titles a flash with its capitalised kind, such as "Error", and offers no way to
  translate it. Toasts sent with `LiveToast.send_toast/3` keep the title they were given.
  An action is offered only when there is something to do with the message, such as
  `undo_action/1` after a step that can be undone.
  """
  @spec toast_content(map()) :: Rendered.t()
  def toast_content(assigns) do
    assigns =
      assign(assigns,
        flash?: Phoenix.Flash.get(assigns.flash, assigns.kind) != nil,
        # Info's icon is grey; every other one takes the colour of its text.
        icon_class: if(assigns.kind == :info, do: "flex shrink-0 text-grey-700", else: "flex shrink-0")
      )

    ~H"""
    <%!-- Next to a title the icon drops 2px to sit on its line. --%>
    <span class={[@title && "pt-0.5", @icon_class]} aria-hidden="true">
      <%= if @icon do %>
        {@icon.(assigns)}
      <% else %>
        <.kind_icon kind={@kind} />
      <% end %>
    </span>
    <div class="flex min-w-0 grow flex-col gap-1">
      <p :if={@title} data-part="title" class="text-sm/4.5 font-medium">
        {if @flash?, do: flash_title(@kind), else: @title}
      </p>
      <p class="text-sm/[1.35]">{@body}</p>
    </div>
    {@action && @action.(assigns)}
    <.button
      :if={!@action}
      type="button"
      variant="unstyled"
      data-part="close"
      aria-label={gettext("Close")}
      phx-click={
        if @flash?,
          do:
            JS.dispatch("flash-leave", to: "##{@id}")
            |> JS.push("lv:clear-flash", value: %{key: @kind}),
          else: LiveToast.dismiss()
      }
      class="flex size-5 shrink-0 cursor-pointer items-center justify-center rounded-sm"
    >
      <Lucideicons.x class="size-4" aria-hidden="true" />
    </.button>
    """
  end

  @doc """
  The action of a toast after a step that can be undone: "Undo" with the return
  arrow. Toasts of other steps have no action.
  """
  attr :on_click, JS,
    required: true,
    doc: "undoes the step; the toast closes on its own"

  @spec undo_action(map()) :: Rendered.t()
  def undo_action(assigns) do
    ~H"""
    <.button
      type="button"
      variant="unstyled"
      data-part="action"
      phx-click={@on_click |> LiveToast.dismiss()}
      class="inline-flex shrink-0 cursor-pointer items-center gap-1 text-sm/4.5 font-medium text-grey-700 group-data-[kind=error]/toast:text-brick-700 hover:text-grey-900 group-data-[kind=error]/toast:hover:text-brick-800"
    >
      {gettext("Undo")}
      <svg
        class="size-4"
        viewBox="0 0 16 16"
        fill="none"
        stroke="currentColor"
        stroke-width="1.33"
        stroke-linecap="round"
        stroke-linejoin="round"
        aria-hidden="true"
      >
        <path d="M6 9.333 3.333 6.667 6 4" />
        <path d="M3.333 6.667h7.334a2.667 2.667 0 0 1 0 5.333H10" />
      </svg>
    </.button>
    """
  end

  @doc """
  The action of a toast that points to what it reports: "View" with a chevron,
  as Figma's small text link.
  """
  attr :navigate, :string, required: true

  @spec view_action(map()) :: Rendered.t()
  def view_action(assigns) do
    ~H"""
    <.link kind="text" size="small" navigate={@navigate} class="shrink-0">
      {gettext("View")}<Lucideicons.chevron_right aria-hidden="true" />
    </.link>
    """
  end

  attr :kind, :atom, required: true

  # Lucide's icons, but for info and the undo arrow, drawn on the design's own
  # 16px grid.
  defp kind_icon(%{kind: :success} = assigns), do: ~H'<Lucideicons.circle_check_big class="size-4" />'

  defp kind_icon(%{kind: :notice} = assigns), do: ~H'<Lucideicons.inbox class="size-4" />'
  defp kind_icon(%{kind: :error} = assigns), do: ~H'<Lucideicons.circle_alert class="size-4" />'

  defp kind_icon(assigns) do
    ~H"""
    <svg
      class="size-4"
      viewBox="0 0 16 16"
      fill="none"
      stroke="currentColor"
      stroke-width="1.33"
      stroke-linecap="round"
      stroke-linejoin="round"
    >
      <circle cx="8" cy="8" r="6" />
      <path d="M8 10.4V8M8 5.6h.006" />
    </svg>
    """
  end

  defp flash_title(:info), do: pgettext("toast title", "Information")
  defp flash_title(:error), do: pgettext("toast title", "Error")
  defp flash_title(:success), do: pgettext("toast title", "Success")
  defp flash_title(:notice), do: pgettext("toast title", "Notice")

  @doc """
  Returns translated copy for LiveToast's lost-connection notices.

  LiveToast translates its own copy only through a separate `live_toast` Gettext domain that
  our extraction and Accent catalog do not cover.
  """
  @spec connection_notifications() :: map()
  def connection_notifications do
    %{
      client_error: %{
        title: gettext("We can't find the internet"),
        body: gettext("Attempting to reconnect")
      },
      server_error: %{
        title: gettext("Something went wrong!"),
        body: gettext("Hang in there while we get back on track")
      }
    }
  end
end
