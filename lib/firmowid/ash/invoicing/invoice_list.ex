defmodule Firmowid.Ash.Invoicing.InvoiceList do
  @moduledoc "Authorized, bounded listing of sales and cost invoices through one action."

  use Ash.Resource,
    domain: Firmowid.Ash.Invoicing,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Checks.AtLeastRole
  alias Firmowid.Ash.Invoicing.Services.InvoiceListing

  code_interface do
    define :list, action: :list
  end

  actions do
    action :list, :map do
      description "List sales and cost invoices with bounded, filter-bound cursor pagination."

      argument :type, :atom do
        allow_nil? false
        default :all
        constraints one_of: [:all, :sales, :cost]
      end

      argument :query, :string, constraints: [max_length: 500]
      argument :date_from, :date
      argument :date_to, :date
      argument :currency, :string, constraints: [max_length: 3]

      argument :sort, :atom do
        allow_nil? false
        default :newest
        constraints one_of: [:newest, :oldest]
      end

      argument :limit, :integer do
        allow_nil? false
        default 25
        constraints min: 1, max: 100
      end

      argument :cursor, :string, constraints: [max_length: 2048]

      run fn input, context -> InvoiceListing.list(input.arguments, context) end
    end
  end

  policies do
    policy action(:list) do
      authorize_if {AtLeastRole, role: :invoicing}
    end
  end
end
