defmodule Firmowid.Payroll.Actions.ImportMemberTaxDeclaration do
  @moduledoc "Imports explicit employee declaration facts and merges them with known versions."

  use Ash.Resource.Actions.Implementation

  alias Firmowid.Payroll
  alias Firmowid.Payroll.MemberTaxDeclaration
  alias Firmowid.Scope

  @declaration_fields [
    :received_on,
    :tax_residency,
    :pit2,
    :employee_costs,
    :youth_relief,
    :pit0,
    :tax_mode,
    :request_year,
    :preferential,
    :student,
    :student_until,
    :other_employment,
    :own_employer,
    :sickness,
    :copyright_costs,
    :ppk,
    :ppk_employee_rate,
    :applies_from
  ]

  @date_fields [:received_on, :applies_from, :student_until]
  @import_fields [:member_id, :source_blob_id | @declaration_fields]
  @string_fields Map.new(@import_fields, &{Atom.to_string(&1), &1})

  @impl true
  def run(input, _opts, context) do
    scope = Scope.new!(context.actor, context.tenant)

    with {:ok, attrs} <- normalize_attrs(input.arguments.attrs_map),
         {:ok, attrs} <- validate_identity(attrs),
         {:ok, source_declaration} <- read_by_source(attrs.source_blob_id, scope),
         :ok <- validate_source_member(source_declaration, attrs.member_id) do
      import(attrs, source_declaration, scope)
    end
  end

  defp normalize_attrs(attrs_map) do
    attrs =
      Enum.reduce(attrs_map, %{}, fn {key, value}, attrs ->
        case declaration_field(key) do
          nil -> attrs
          _field when is_nil(value) -> attrs
          field -> Map.put(attrs, field, value)
        end
      end)

    Enum.reduce_while(@date_fields, {:ok, attrs}, fn field, {:ok, attrs} ->
      case Map.fetch(attrs, field) do
        :error ->
          {:cont, {:ok, attrs}}

        {:ok, value} ->
          case parse_date(value) do
            {:ok, date} -> {:cont, {:ok, Map.put(attrs, field, date)}}
            :error -> {:halt, {:error, {:invalid_date, field}}}
          end
      end
    end)
  end

  defp declaration_field(field) when field in @import_fields, do: field
  defp declaration_field(field) when is_binary(field), do: Map.get(@string_fields, field)
  defp declaration_field(_), do: nil

  defp parse_date(%Date{} = date), do: {:ok, date}

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      _ -> :error
    end
  end

  defp parse_date(_), do: :error

  defp validate_identity(attrs) do
    with {:ok, member_id} when is_binary(member_id) <-
           Ash.Type.cast_input(:uuid, attrs[:member_id]),
         {:ok, source_blob_id} when is_binary(source_blob_id) <-
           Ash.Type.cast_input(:uuid, attrs[:source_blob_id]) do
      {:ok, Map.merge(attrs, %{member_id: member_id, source_blob_id: source_blob_id})}
    else
      _ -> {:error, :invalid_document_identity}
    end
  end

  defp read_by_source(source_blob_id, scope) do
    with {:ok, declarations} <-
           Payroll.list_tax_declarations(%{source_blob_id: source_blob_id}, scope: scope),
         do: {:ok, List.first(declarations)}
  end

  defp validate_source_member(nil, _member_id), do: :ok

  defp validate_source_member(%{member_id: current_member_id}, member_id) when current_member_id == member_id, do: :ok

  defp validate_source_member(_declaration, _member_id), do: {:error, :member_mismatch}

  defp import(attrs, source_declaration, scope) do
    case source_declaration do
      %MemberTaxDeclaration{} = declaration ->
        update_declaration(declaration, attrs, scope)

      nil ->
        import_without_source(attrs, scope)
    end
  end

  defp import_without_source(%{applies_from: %Date{} = applies_from} = attrs, scope) do
    with {:ok, same_date} <- read_by_member_and_date(attrs.member_id, applies_from, scope) do
      case same_date do
        %MemberTaxDeclaration{} = declaration ->
          update_declaration(declaration, attrs, scope)

        nil ->
          create_version(
            attrs,
            latest_effective_declaration(attrs.member_id, applies_from, scope),
            scope
          )
      end
    end
  end

  defp import_without_source(attrs, scope), do: create_version(attrs, nil, scope)

  defp update_declaration(declaration, attrs, scope) do
    inherited =
      if (is_nil(declaration.applies_from) or is_nil(declaration.received_on)) and
           match?(%Date{}, attrs[:applies_from]) do
        latest_effective_declaration(declaration.member_id, attrs.applies_from, scope)
      end

    attrs =
      inherited
      |> inherited_values()
      |> Enum.filter(fn {field, _value} -> is_nil(Map.get(declaration, field)) end)
      |> Map.new()
      |> Map.merge(attrs)
      |> Map.delete(:member_id)

    MemberTaxDeclaration.update_imported_tax_declaration(declaration, attrs, scope: scope)
  end

  defp create_version(attrs, inherited, scope) do
    attrs =
      inherited
      |> inherited_values()
      |> Map.merge(attrs)

    MemberTaxDeclaration.create_imported_tax_declaration(attrs, scope: scope)
  end

  defp read_by_member_and_date(member_id, applies_from, scope) do
    with {:ok, declarations} <-
           Payroll.list_tax_declarations(%{member_id: member_id},
             query: [filter: [applies_from: applies_from]],
             scope: scope
           ),
         do: {:ok, List.first(declarations)}
  end

  defp latest_effective_declaration(member_id, applies_from, scope) do
    %{member_id: member_id, as_of: applies_from}
    |> Payroll.list_tax_declarations!(scope: scope)
    |> List.first()
  end

  defp inherited_values(nil), do: %{}

  defp inherited_values(declaration) do
    declaration
    |> declaration_values()
    |> Map.drop([:received_on, :applies_from])
  end

  defp declaration_values(declaration) do
    @declaration_fields
    |> Map.new(fn field -> {field, Map.get(declaration, field)} end)
    |> Enum.reject(fn {_field, value} -> is_nil(value) end)
    |> Map.new()
  end
end
