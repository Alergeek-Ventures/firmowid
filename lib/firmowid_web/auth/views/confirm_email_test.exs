defmodule FirmowidWeb.Auth.Views.ConfirmEmailTest do
  use FirmowidWeb.ConnCase, async: false

  import Firmowid.AccountsFixtures
  import Firmowid.Test.Support.AuthEmailHelpers
  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias Firmowid.Ash.Blobs.Blob
  alias Firmowid.Ash.Core

  setup :set_swoosh_global

  test "user can confirm email from emailed link", %{conn: conn} do
    {:ok, registration_lv, _html} = live(conn, ~p"/zarejestruj")

    email = unique_user_email()

    registration_form =
      form(registration_lv, "#registration_form", user: valid_user_attributes(email: email))

    render_submit(registration_form)
    registration_conn = follow_trigger_action(registration_form, conn)

    assert redirected_to(registration_conn) == ~p"/czasosledz"

    user = Core.get_user_by_email!(email, authorize?: false)
    assert is_nil(user.confirmed_at)

    confirmation_token = extract_token_from_email!("/potwierdz-email/")

    assert {:ok, _confirm_lv, html} =
             live(build_conn(), ~p"/potwierdz-email/#{confirmation_token}")

    assert html =~ "Potwierdź założenie konta"
    assert html =~ "Zaloguj się"

    assert is_nil(Core.load_member(user).member)
    authenticated_conn = recycle(registration_conn)

    assert {:ok, confirm_lv, _html} =
             live(authenticated_conn, ~p"/potwierdz-email/#{confirmation_token}")

    assert has_element?(confirm_lv, "#confirm_email_form button", "Potwierdź założenie konta")

    confirm_conn =
      confirm_lv
      |> form("#confirm_email_form", user: %{"confirm" => confirmation_token})
      |> submit_form(authenticated_conn)

    assert redirected_to(confirm_conn) == ~p"/czasosledz"

    confirmed_user = Core.get_user_by_email!(email, authorize?: false)
    assert confirmed_user.confirmed_at
  end

  test "user without an organization confirms email without loading another tenant's avatar", %{
    conn: conn
  } do
    organization_id = user_fixture().member.organization_id

    blob =
      Ash.Seed.seed!(Blob, %{
        organization_id: organization_id,
        blob_path: "#{organization_id}/confirmation-avatar.png",
        blob_checksum: "confirmation-avatar",
        original_filename: "confirmation-avatar.png"
      })

    drain_sent_emails()
    user = Core.register_with_password!(valid_user_attributes(), authorize?: false, actor: %{})
    token = extract_token_from_email!("/potwierdz-email/")
    assert is_nil(Core.load_member(user).member)
    authenticated_conn = log_in_user(conn, user)

    assert {:ok, view, _html} = live(authenticated_conn, ~p"/potwierdz-email/#{token}")
    assert has_element?(view, "#confirm_email_form button", "Potwierdź założenie konta")
    refute has_element?(view, "img[src*='#{blob.blob_path}']")

    confirmed_conn =
      view
      |> form("#confirm_email_form", user: %{"confirm" => token})
      |> submit_form(authenticated_conn)

    assert redirected_to(confirmed_conn) == ~p"/czasosledz"
    confirmed_user = Core.get_user!(user.id, actor: Core.load_member(user))
    assert confirmed_user.confirmed_at
    assert is_nil(Core.load_member(confirmed_user).member)
  end

  test "user confirms an email change from account settings", %{conn: conn} do
    user = user_fixture()
    new_email = unique_user_email()
    authenticated_conn = log_in_user(conn, user)
    drain_sent_emails()

    {:ok, view, _html} = live(authenticated_conn, ~p"/ustawienia/konto")

    view
    |> element("button[aria-label='Edytuj dane dostępowe']")
    |> render_click()

    drain_sent_emails()

    view
    |> form("#email_form", user: %{email: new_email, current_password: valid_user_password()})
    |> render_submit()

    assert_email_sent(fn email ->
      send(self(), {:email_change_confirmation, email})
      email.to == [{"", new_email}]
    end)

    assert_receive {:email_change_confirmation, email}
    assert email.text_body =~ "Jeśli nie prosiłeś o zmianę adresu email, zignoruj tę wiadomość."

    [confirmation_token] =
      Regex.run(~r{/potwierdz-email/([^\s]+)}, email.text_body, capture: :all_but_first)

    assert {:ok, confirm_lv, html} =
             live(authenticated_conn, ~p"/potwierdz-email/#{confirmation_token}")

    assert html =~ "Aby zmienić adres email, kliknij poniższy przycisk."
    assert html =~ "Potwierdź zmianę adresu email"
    refute html =~ "Zaloguj się"

    confirm_conn =
      confirm_lv
      |> form("#confirm_email_form", user: %{"confirm" => confirmation_token})
      |> submit_form(authenticated_conn)

    assert redirected_to(confirm_conn) == ~p"/czasosledz"
    assert to_string(Core.get_user!(user.id, authorize?: false).email) == new_email
  end

  for avatar_tenant <- [:own, :foreign] do
    @avatar_tenant avatar_tenant
    test "email confirmation scopes the #{@avatar_tenant} tenant avatar", %{conn: conn} do
      user = user_fixture()
      token = extract_token_from_email!("/potwierdz-email/")

      organization_id =
        case @avatar_tenant do
          :own -> user.member.organization_id
          :foreign -> user_fixture().member.organization_id
        end

      blob =
        Ash.Seed.seed!(Blob, %{
          organization_id: organization_id,
          blob_path: "#{organization_id}/confirmation-avatar.png",
          blob_checksum: "confirmation-avatar",
          original_filename: "confirmation-avatar.png"
        })

      Ash.Seed.update!(user.member, %{avatar_blob_id: blob.id})
      authenticated_conn = log_in_user(conn, user)

      assert {:ok, view, _html} = live(authenticated_conn, ~p"/potwierdz-email/#{token}")
      assert has_element?(view, "#confirm_email_form button", "Potwierdź założenie konta")

      avatar_selector = "img[src*='#{blob.blob_path}']"

      case @avatar_tenant do
        :own -> assert has_element?(view, avatar_selector)
        :foreign -> refute has_element?(view, avatar_selector)
      end

      confirmed_conn =
        view
        |> form("#confirm_email_form", user: %{"confirm" => token})
        |> submit_form(authenticated_conn)

      assert redirected_to(confirmed_conn) == ~p"/czasosledz"
      assert Core.get_user!(user.id, actor: user).confirmed_at
    end
  end
end
