defmodule Firmowid.Ash.Resource do
  @moduledoc """
  Shared macros for Firmowid Ash resources.

  Currently provides timestamp macros that match the existing Ecto schema
  conventions. Import or `require` this module in each resource that needs
  Firmowid-standard timestamps.

  ## Available macros

    * `firmowid_timestamps/0` — adds `:inserted_at` and `:updated_at` as
      `:utc_datetime` (not `:utc_datetime_usec`) with `public?: true`.

  ## Namespace plan

  The `Firmowid.Ash.*` namespace disambiguates Ash resources from the legacy
  Ecto contexts during migration (e.g. `Firmowid.Ash.Timetracker.Session` vs
  `Firmowid.Timetracker`). Once the migration is complete and the old contexts
  are removed, drop the `.Ash.` segment so domains live at their natural
  namespace: `Firmowid.Timetracker.Session`, `Firmowid.Payroll.UserSalary`, etc.
  """

  defmacro firmowid_timestamps do
    quote do
      create_timestamp(:inserted_at, type: :utc_datetime, public?: true)
      update_timestamp(:updated_at, type: :utc_datetime, public?: true)
    end
  end
end
