defmodule FirmowidWeb.Settings.Components.SettingsPage do
  @moduledoc """
  Shared shell for the settings screens.
  """

  use FirmowidWeb, :html

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.UploadErrors
  import FirmowidWeb.Settings.Components.Helpers, only: [initial: 1]

  alias Phoenix.LiveView.Rendered

  @doc """
  Renders a settings page with its title.
  """
  @spec settings_page(map()) :: Rendered.t()
  attr :title, :string, default: nil

  attr :back, :string,
    default: nil,
    doc: "The page a subpage goes back to, shown above its title."

  attr :description, :string, default: nil, doc: "One line under the title."

  slot :inner_block, required: true
  slot :actions, doc: "Shown next to the title."
  slot :icon, doc: "A logo before the title, such as an integration's."

  def settings_page(assigns) do
    ~H"""
    <section class="mx-auto flex w-full max-w-6xl flex-col gap-8 py-4">
      <.back :if={@back} patch={@back} class="-mb-4 self-start" />
      <div class="flex flex-wrap items-center justify-between gap-4">
        <div class="flex items-center gap-4">
          {render_slot(@icon)}
          <div class="flex flex-col gap-1">
            <h1 class="text-2xl font-semibold text-grey-900">{@title}</h1>
            <p :if={@description} class="text-sm/snug text-grey-700">{@description}</p>
          </div>
        </div>
        {render_slot(@actions)}
      </div>
      {render_slot(@inner_block)}
    </section>
    """
  end

  @doc "Renders an avatar upload within its settings page."
  @spec settings_avatar(map()) :: Rendered.t()
  attr :upload, :any, required: true
  attr :name, :string, required: true
  attr :blob, Firmowid.Blobs.Blob, default: nil, doc: "the picture, with `:url` loaded"
  attr :label, :string, required: true
  attr :class, :any, default: nil

  def settings_avatar(assigns) do
    ~H"""
    <form
      id={"settings-#{@upload.name}-form"}
      phx-submit="upload"
      phx-change="upload"
      class={["flex flex-wrap items-center gap-4", @class]}
    >
      <.live_file_input upload={@upload} class="sr-only" aria-label={@label} />
      <.avatar class="size-20 border border-grey-100 bg-grey-100">
        <.avatar_image :if={@blob} blob={@blob} sizes="80px" alt={@name} class="object-contain" />
        <.avatar_fallback class="text-2xl font-medium text-grey-700">
          {initial(@name)}
        </.avatar_fallback>
      </.avatar>
      <.button as="label" for={@upload.ref} variant="outline" size="small">{@label}</.button>
      <.upload_error_messages
        upload={@upload}
        not_accepted={gettext("Only JPG, JPEG and PNG images are allowed.")}
        class="basis-full"
      />
    </form>
    """
  end
end
