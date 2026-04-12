defmodule Firmowid.Ash.Finances.BankAccountTest do
  @moduledoc false
  use Firmowid.DataCase

  alias Firmowid.Ash.Finances.BankAccount

  describe "AshOban queue routing" do
    test "keeps sync_transactions on bank_data queue" do
      assert :bank_data ==
               AshOban.Info.oban_trigger(BankAccount, :sync_transactions).queue
    end
  end
end
