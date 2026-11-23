defmodule Firmowid.Core.NipRegisters do
  @moduledoc """
  What each public register said about a Polish NIP in its last check
  (`Firmowid.Invoicing.NipRegistration`), kept next to the overall status so the
  UI can tell which register a conclusion comes from. A nil register was not asked:
  an earlier one already answered, or there was no way to look the NIP up in it.
  """

  use Ash.Resource, data_layer: :embedded, embed_nil_values?: false

  attributes do
    attribute :white_list, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:active, :exempt, :not_registered, :absent, :invalid]],
      description: """
      VAT white list (WL2) status code: C `:active`, Z `:exempt`, N `:not_registered`
      (in the list, but not or no longer a VAT payer), B `:absent` (never in the VAT
      register), I `:invalid` (the list rejects the NIP).
      """

    attribute :krs_number, :string,
      public?: true,
      description: "KRS number the VAT white list gives for the NIP; KRS itself cannot be searched by NIP."

    attribute :krs, :atom,
      public?: true,
      constraints: [one_of: [:entered, :struck_off, :not_found, :other_nip]],
      description: """
      Current KRS extract of `krs_number`: `:entered` with this NIP, `:struck_off`,
      `:not_found` in the registers of entrepreneurs and of associations, or
      `:other_nip` when the extract belongs to another NIP. Nil when not asked.
      """

    attribute :ceidg, :atom,
      public?: true,
      constraints: [one_of: [:listed, :deregistered, :absent]],
      description: """
      CEIDG, the register of sole proprietorships: `:listed` with a business that is
      not deregistered (active or suspended), `:deregistered` when all its businesses
      are, `:absent` when it has none. Nil when not asked.
      """
  end
end
