defmodule Firmowid.Analysis.OwnAccounts do
  @moduledoc """
  Recognizes transfers between the organization's own accounts, which the
  analysis leaves out. The company's other accounts are not always connected
  (a VAT account, another bank), so a transfer to or from the company's own
  name counts as one between its accounts too.
  """

  alias Firmowid.Analysis.CategoryReview
  alias Firmowid.Core
  alias Firmowid.Finances
  alias Firmowid.Finances.AccountNumber
  alias Firmowid.Finances.Transaction
  alias Firmowid.Scope

  @type t :: %{ibans: MapSet.t(String.t()), name: map() | nil}

  @doc "Loads the organization's connected bank accounts and the spellings of its name."
  @spec load(Scope.t()) :: t()
  def load(scope) do
    ibans =
      %{}
      |> Finances.list_bank_accounts!(scope: scope)
      |> MapSet.new(&AccountNumber.key(&1.iban))
      |> MapSet.delete(nil)

    %{ibans: ibans, name: own_name(Core.get_organization!(scope.tenant, scope: scope).name)}
  end

  # Spellings of the same legal form, as words joined without Polish letters.
  @legal_form_spellings [
    ~w(spolkazograniczonaodpowiedzialnoscia spzoo spolkazoo),
    ~w(spolkakomandytowa spk),
    ~w(spolkajawna spj),
    ~w(spolkaakcyjna sa),
    ~w(spolkakomandytowoakcyjna ska)
  ]

  # The organization's name split into the words before its legal form and the spellings of
  # that legal form, for comparing with names banks write on transfers. Without a legal form
  # at its end, the whole name must match. A name that ends with another legal form ("Acme
  # Sp. z o.o. Sp. k.") must keep its own, so the general partner does not match.
  defp own_name(organization_name) do
    {short_words, legal_form} = split_legal_form(CategoryReview.words(organization_name))

    if short_words != [] do
      %{
        short_words: short_words,
        legal_forms: Enum.find(@legal_form_spellings, [legal_form], &(legal_form in &1)),
        bare?: legal_form == "" or elem(split_legal_form(short_words), 1) == ""
      }
    end
  end

  # The longest legal form at the end of the words, in any of its spellings; all of them for a
  # name that is only a legal form, which leaves no name to match.
  defp split_legal_form(words) do
    Enum.find_value(0..(length(words) - 1)//1, {words, ""}, fn size ->
      {short_words, legal_form} = Enum.split(words, size)
      legal_form = Enum.join(legal_form)
      if Enum.any?(@legal_form_spellings, &(legal_form in &1)), do: {short_words, legal_form}
    end)
  end

  @doc "Returns whether a transaction moves money to or from the organization's own account or name."
  @spec transfer?(Transaction.t(), t()) :: boolean()
  def transfer?(%Transaction{amount: amount} = transaction, own_accounts) do
    {account, name} =
      cond do
        Money.positive?(amount) -> {transaction.debtor_account, transaction.debtor_name}
        Money.negative?(amount) -> {transaction.creditor_account, transaction.creditor_name}
        true -> {nil, nil}
      end

    MapSet.member?(own_accounts.ibans, AccountNumber.key(account)) or
      own_name?(name, own_accounts.name)
  end

  defp own_name?(name, own_name) when is_nil(name) or is_nil(own_name), do: false

  # Banks write the legal form in many ways and cut long names short, even mid-word and
  # joining lines ("ACME SPÓŁKA ZOGRANICZ"), so the name matches as the organization's name
  # without a legal form or followed by the start of any spelling of its own legal form.
  # Another legal form is another company of the same name ("ACME Sp. k." for "ACME Sp. z o.o.").
  defp own_name?(name, %{short_words: short_words, legal_forms: legal_forms, bare?: bare?}) do
    words = CategoryReview.words(name)
    rest = Enum.join(Enum.drop(words, length(short_words)))

    List.starts_with?(words, short_words) and (bare? or rest != "") and
      Enum.any?(legal_forms, &String.starts_with?(&1, rest))
  end
end
