defmodule FirmowidWeb.Core.Toast do
  @moduledoc """
  Toast styling, content and copy for `LiveToast.toast_group/1`.
  """

  use Phoenix.Component
  use Gettext, backend: Firmowid.Gettext

  @doc """
  Generates CSS classes for flash/toast messages based on the assigns.
  """
  def toast_class_fn(assigns) do
    [
      # base classes
      "group/toast z-100 pointer-events-auto relative w-full items-center justify-between origin-center overflow-hidden rounded-lg p-4 shadow-lg border col-start-1 col-end-1 row-start-1 row-end-2",
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
  Keeps toasts above the full-screen assistant on phones.
  """
  def group_class_fn(assigns), do: [LiveToast.group_class_fn(assigns), "max-md:z-60"]

  @doc """
  Renders toast content with LiveToast's default markup and a translated title for Phoenix flashes.

  LiveToast titles a flash with its capitalised kind, such as "Error", and offers no way to
  translate it. Toasts sent with `LiveToast.send_toast/3` keep the title they were given.
  """
  @spec toast_content(map()) :: Phoenix.LiveView.Rendered.t()
  def toast_content(assigns) do
    ~H"""
    <div class="flex grow flex-col items-start justify-center">
      <p
        :if={@title}
        data-part="title"
        class={["flex items-center text-sm/6 font-semibold", @icon && "mb-2"]}
      >
        {@icon && @icon.(assigns)}
        {if Phoenix.Flash.get(@flash, @kind), do: flash_title(@kind), else: @title}
      </p>
      <p class="text-sm/5">
        {@body}
      </p>
    </div>
    {@action && @action.(assigns)}
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
