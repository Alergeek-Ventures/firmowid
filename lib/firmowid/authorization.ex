defmodule Firmowid.Authorization do
  alias Firmowid.Accounts.User

  def authorize(%User{system_role: "superuser"} = _user), do: true

  def authorize(_user), do: false
end
