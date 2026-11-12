defmodule FirmowidWeb.Management.Components.Roles do
  @moduledoc """
  Organization roles and invitations: role badges, the invitation and role
  change modals and the rows of active invitations.

  The hosting LiveView handles their events: `create_organization_invite`,
  `copy_organization_invite`, `delete_organization_invite`, `update_user_role`
  and `clear_selected_user`.
  """

  use FirmowidWeb, :html

  import FirmowidUI.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Core.UserRole
  alias Firmowid.TimeFormatter
  alias Phoenix.LiveView.JS
  alias Phoenix.LiveView.Rendered

  @doc "Renders the label of a member role; the slot adds trailing content such as an icon."
  @spec role_badge(map()) :: Rendered.t()
  attr :role, :atom, required: true
  attr :class, :any, default: nil
  slot :inner_block

  def role_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex min-w-28 items-center justify-center gap-1 rounded-sm px-3 py-1 text-sm leading-[1.35]",
      role_badge_styles(@role),
      @class
    ]}>
      {UserRole.label(@role)}{render_slot(@inner_block)}
    </span>
    """
  end

  @doc "Returns the invitations that can still be used, the soonest to expire first."
  @spec active_invites([map()]) :: [map()]
  def active_invites(invites) do
    now = DateTime.utc_now()

    invites
    |> Enum.filter(fn invite ->
      is_nil(invite.consumed_at) and DateTime.after?(invite.expires_at, now)
    end)
    |> Enum.sort_by(&DateTime.to_unix(&1.expires_at))
  end

  @doc "Renders one active invitation with its code to copy and a delete action."
  @spec invite_row(map()) :: Rendered.t()
  attr :invite, :map, required: true
  attr :class, :any, default: nil

  def invite_row(assigns) do
    ~H"""
    <div class={["grid grid-cols-[minmax(0,1fr)_1fr_auto] items-center gap-4 rounded-lg", @class]}>
      <p class="text-sm">
        <span class="text-grey-500">{gettext("Generated:")}</span> {TimeFormatter.format_date(
          @invite.inserted_at
        )} | {invite_issuer(@invite)}
      </p>

      <.button
        type="button"
        variant="unstyled"
        size="small"
        class="flex w-full max-w-80 cursor-pointer items-center justify-between gap-5 rounded bg-teal-100 p-1 py-2 pl-3 text-sm text-teal-700"
        phx-click="copy_organization_invite"
        phx-value-code={@invite.invite_code}
      >
        {@invite.invite_code}
        <Lucideicons.copy class="size-5" />
      </.button>

      <div class="flex items-center gap-4">
        <.role_badge role={@invite.role} />

        <.button
          type="button"
          variant="unstyled"
          phx-click="delete_organization_invite"
          phx-value-id={@invite.id}
          aria-label={gettext("Delete invitation")}
        >
          <Lucideicons.trash_2 class="text-grey-500 transition-all hover:text-grey-700" />
        </.button>
      </div>
    </div>
    """
  end

  @doc "Renders the modal that generates an invitation code for a chosen role."
  @spec invite_modal(map()) :: Rendered.t()
  def invite_modal(assigns) do
    ~H"""
    <.modal
      id="organization_invite_modal"
      on_cancel={hide_modal("organization_invite_modal")}
      class="max-w-lg"
    >
      <div class="space-y-8">
        <h3 class="text-xl font-medium">{gettext("Invite a new employee")}</h3>
        <p>
          {gettext(
            "Choose a role, then generate a code. An employee who enters it when creating an account will automatically join your organization."
          )}
        </p>

        <.form
          for={%{}}
          phx-submit="create_organization_invite"
          id="organization_invite_form"
          class="flex flex-col gap-8"
        >
          <.role_row_input
            :for={role <- UserRole.roles()}
            role={role}
            checked={role == :employee}
          />

          <div class="flex flex-col-reverse gap-4 sm:flex-row sm:justify-end">
            <.button
              type="button"
              variant="tertiary"
              size="small"
              phx-click={hide_modal("organization_invite_modal")}
            >
              {gettext("Cancel")}
            </.button>

            <.button
              type="submit"
              variant="primary"
              accent="teal"
              size="small"
              phx-click={hide_modal("organization_invite_modal")}
            >
              {gettext("Generate code")}
            </.button>
          </div>
        </.form>
      </div>
    </.modal>
    """
  end

  @doc "Renders the modal that changes the role of `user`."
  @spec update_role_modal(map()) :: Rendered.t()
  attr :user, :map, required: true

  def update_role_modal(assigns) do
    current_role = assigns.user.member.role

    assigns =
      assigns
      |> assign(:current_role, current_role)
      |> assign(:other_roles, Enum.reject(UserRole.roles(), &(&1 == current_role)))

    ~H"""
    <.modal
      id="update_role_modal"
      show
      on_cancel={JS.push("clear_selected_user")}
      class="max-w-lg"
    >
      <div class="space-y-8">
        <h3 class="text-xl font-medium">{gettext("Changing the role")}</h3>
        <p>
          {gettext("You are changing the role of user %{user}. Their current role is:",
            user: present(@user.member.name || to_string(@user.email))
          )}
        </p>

        <.form
          for={%{}}
          phx-submit="update_user_role"
          id="update_role_form"
          class="flex flex-col gap-8"
        >
          <input type="hidden" name="user_id" value={@user.id} />

          <.role_row_input role={@current_role} checked />
          <.role_row_input :for={role <- @other_roles} role={role} />

          <div class="flex flex-col-reverse gap-4 sm:flex-row sm:justify-end">
            <.button
              type="button"
              variant="tertiary"
              size="small"
              phx-click={JS.push("clear_selected_user") |> hide_modal("update_role_modal")}
            >
              {gettext("Cancel")}
            </.button>

            <.button
              type="submit"
              variant="primary"
              accent="teal"
              size="small"
            >
              {gettext("Change role")}
            </.button>
          </div>
        </.form>
      </div>
    </.modal>
    """
  end

  attr :role, :atom, required: true
  attr :checked, :boolean, default: false

  defp role_row_input(assigns) do
    ~H"""
    <.label class="flex cursor-pointer flex-row items-start gap-2">
      <input
        name="role"
        type="radio"
        value={UserRole.param(@role)}
        checked={@checked}
        class="size-5 shrink-0 appearance-none rounded-full border-2 border-grey-300 bg-white text-teal-700 checked:bg-teal-700 focus:outline-none"
      />
      <div>
        <span class="font-medium capitalize">{UserRole.label(@role)}</span>
        <p class="text-sm">{role_desc(@role)}</p>
      </div>
    </.label>
    """
  end

  defp invite_issuer(%{issued_by: %{email: email}}) when not is_nil(email), do: to_string(email)
  defp invite_issuer(_invite), do: gettext("administrator")

  defp role_desc(:admin) do
    gettext(
      "Full access to the \"Management\" tab, including managing employees, counterparties and projects. This role also gives full access to invoices and to uploading invoices from outside KSeF."
    )
  end

  defp role_desc(:employee) do
    gettext(
      "Basic access to the organization, including the Time Tracker (working time tracking). The ability to submit leave requests and upload documents."
    )
  end

  defp role_desc(:invoicing) do
    gettext("Invoicing access in view-only mode, without the ability to add or edit.")
  end

  defp role_desc(:accountant) do
    gettext("Full invoicing access (viewing, adding and editing), except for adding invoices from outside KSeF.")
  end

  defp role_badge_styles(:admin), do: "bg-teal-200 text-teal-700"
  defp role_badge_styles(:accountant), do: "bg-moss-200 text-moss-700"
  defp role_badge_styles(:invoicing), do: "bg-rust-200 text-rust-700"
  defp role_badge_styles(_role), do: "bg-grey-200 text-grey-700"

  defp present(nil), do: "—"
  defp present(""), do: "—"
  defp present(value), do: to_string(value)
end
