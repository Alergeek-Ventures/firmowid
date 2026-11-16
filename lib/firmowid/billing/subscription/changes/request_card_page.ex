defmodule Firmowid.Billing.Subscription.Changes.RequestCardPage do
  @moduledoc """
  Opens Tpay's card page for the owner of the organization before the subscription is written.

  If Tpay fails, nothing is written. The page's URL comes back as the record's `:card_page_url`
  metadata; its tokenization id is stored, so the notification finds the subscription.

  Tpay brings the payer back to `CardReturn` with the `wynik` the options name: `:saved` after
  the card was entered (default `"zapisana"`), `:failed` after an error (default `"blad"`).
  """

  use Ash.Resource.Change

  alias Firmowid.Billing.Tpay.Client
  alias Firmowid.Core
  alias FirmowidWeb.Billing.Utilities.Navigation
  alias FirmowidWeb.Core.Endpoint

  @doc "Asks Tpay for the card page right before the insert."
  @spec change(Ash.Changeset.t(), keyword(), Ash.Resource.Change.Context.t()) :: Ash.Changeset.t()
  @impl true
  def change(changeset, opts, context) do
    Ash.Changeset.before_action(changeset, &request_card_page(&1, opts, context))
  end

  defp request_card_page(changeset, opts, context) do
    read_opts = Ash.Context.to_opts(context, load: [owner: [member: [:display_name]]])

    with {:ok, organization} <- Core.get_organization(changeset.tenant, read_opts),
         {:ok, %{id: tokenization_id, url: card_page_url}} <-
           Client.create_card_token(card_token_params(organization.owner, opts)) do
      changeset
      |> Ash.Changeset.force_change_attribute(:tokenization_id, tokenization_id)
      |> Ash.Changeset.after_action(fn _changeset, subscription ->
        {:ok, Ash.Resource.put_metadata(subscription, :card_page_url, card_page_url)}
      end)
    else
      {:error, error} -> Ash.Changeset.add_error(changeset, error)
    end
  end

  defp card_token_params(owner, opts) do
    base_url = Endpoint.url()
    card_return_url = base_url <> Navigation.card_return_path()

    %{
      payer: %{name: owner.member.display_name, email: to_string(owner.email)},
      callback_url: base_url <> "/webhooks/tpay",
      success_url: card_return_url <> "?wynik=" <> Keyword.get(opts, :saved, "zapisana"),
      error_url: card_return_url <> "?wynik=" <> Keyword.get(opts, :failed, "blad")
    }
  end
end
