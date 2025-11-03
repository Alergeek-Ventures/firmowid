defmodule Firmowid.Repo.Migrations.AddInboundEmailNicknameToOrganizations do
  use Ecto.Migration

  import Ecto.Query

  def up do
    # Add the nickname column
    alter table(:organizations) do
      add :inbound_email_nickname, :text
    end

    # Backfill existing organizations with unique nicknames
    flush()
    backfill_nicknames()

    # Make the column required
    alter table(:organizations) do
      modify :inbound_email_nickname, :text, null: false
    end

    # Add unique constraint
    create unique_index(:organizations, [:inbound_email_nickname])
  end

  def down do
    drop index(:organizations, [:inbound_email_nickname])

    alter table(:organizations) do
      remove :inbound_email_nickname
    end
  end

  defp backfill_nicknames do
    # Get all organization IDs
    org_ids =
      from(o in "organizations", select: o.id)
      |> Firmowid.Repo.all(skip_organization_id: true)

    # Generate unique nickname for each organization
    Enum.each(org_ids, fn org_id ->
      nickname = generate_unique_nickname()

      from(o in "organizations", where: o.id == ^org_id)
      |> Firmowid.Repo.update_all([set: [inbound_email_nickname: nickname]],
        skip_organization_id: true
      )
    end)
  end

  defp generate_unique_nickname do
    generate_unique_nickname(10)
  end

  defp generate_unique_nickname(0) do
    raise "Failed to generate unique nickname after 10 attempts"
  end

  defp generate_unique_nickname(attempts_left) do
    nickname = HumanIDs.generate()

    # Check if this nickname already exists
    exists? =
      from(o in "organizations", where: o.inbound_email_nickname == ^nickname)
      |> Firmowid.Repo.exists?(skip_organization_id: true)

    if exists? do
      generate_unique_nickname(attempts_left - 1)
    else
      nickname
    end
  end
end
