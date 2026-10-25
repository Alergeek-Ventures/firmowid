defmodule Firmowid.Ash.Blobs.Utils.ProcessEmploymentContractBlob do
  @moduledoc "Processes employee documents into contract, declaration, or monthly payroll records."

  alias Firmowid.Ash.Blobs.Utils.ProcessBlobHelpers
  alias Firmowid.Ash.Payroll
  alias Firmowid.Ash.Payroll.MemberPayrollInput
  alias Firmowid.Ash.Payroll.MemberTaxDeclaration
  alias Firmowid.Ash.Payroll.UserEmploymentContract

  @employment_contract_system_prompt """
  Extract facts explicitly present in this employee document or document packet.

  Document classification:
  - Use "employment_contract" for an employment contract that is unsigned or has only one signature.
  - Use "signed_employment_contract" for an employment contract signed by both the employee and employer.
  - Use "employee_tax_declaration" for a standalone employee declaration, including PIT-2 or PPK declarations.
  - Use "payroll_statement" for a standalone payroll statement.
  - Use "invalid" only for an unrelated document.
  - A contract packet may also include a "tax_declaration" object and/or a "payroll_input" object.
    A standalone declaration or payroll statement must not be classified as an employment contract.

  Extraction rules:
  - Extract only facts explicitly stated in the document. Do not infer a member or organization identity.
  - Leave unknown values null or omit them. Never invent dates, zero balances, or false flags.
  - Declaration facts may be partial, and received_on or applies_from may be absent.
    Extract PIT-2 and PPK choices when they are explicitly stated.
  - Dates must use YYYY-MM-DD. A payroll salary_month is the first day of the explicitly stated month.
  - Extract payroll currency as a 3-letter ISO code only when explicitly stated. If the statement
    explicitly labels amounts as PLN or zł/złoty, return "PLN"; never assume PLN from the document's
    language, locale, employer, or country. Populate gross and other monetary payroll fields only
    when the currency is explicitly PLN. Leave them null/omitted for foreign or unknown currency.
  - Payroll monetary values are PLN amounts. Extract prior_taxable_income, prior_social_base,
    and prior_exempt_income only when the statement explicitly gives totals before this payout.
    Never use year-to-date totals that include the current payout as prior values, and never infer
    an all-payer social base from a single-employer statement.
  - Extract employer_ppk_income only when the actual transferred amount before/on payout is explicit;
    do not substitute the contribution accrued on this month's gross pay. Include its explicit date.
  - Set payout_date_basis to "planned" or "actual" only when the document states which it is.
  - For contract salary_amount, preserve the existing hourly storage convention: if salary is monthly,
    convert to an hourly amount using 160 hours for full time as before. This conversion is not a
    confirmed hourly rate. Set hourly_rate_confirmed to true only when the contract explicitly states
    an hourly rate, false when converting a stated monthly amount, and null when the basis is unknown.
  - Contract type must be one of "uop", "b2b", "uz", or "uod"; otherwise return null.
  - position is the stated job title or role; signed_at is the stated signing date.
  - For an explicit regular payment schedule, payout_day is the stated day of month (1-31).
    payout_month_offset is 0 for payment in the salary month, or 1 in the following month.
    If either part is not stated, leave it null. Do not invent a month-end payment date.
  - bank_account_number is the employee's own payment account, exactly as printed. Never return
    the employer's/company's account. Return null if the employee account is not explicit.
  """

  @employment_contract_schema %{
    type: "object",
    properties: %{
      document_type: %{
        type: "string",
        enum: [
          "employment_contract",
          "signed_employment_contract",
          "employee_tax_declaration",
          "payroll_statement",
          "invalid"
        ]
      },
      starts_at: %{type: "string", format: "date"},
      salary_amount: %{type: "number"},
      salary_currency: %{type: "string"},
      hourly_rate_confirmed: %{type: ["boolean", "null"]},
      payout_day: %{type: ["integer", "null"], minimum: 1, maximum: 31},
      payout_month_offset: %{type: ["integer", "null"], enum: [0, 1, nil]},
      contract_type: %{type: ["string", "null"], enum: ["uop", "b2b", "uz", "uod", nil]},
      position: %{type: ["string", "null"]},
      signed_at: %{type: ["string", "null"], format: "date"},
      bank_account_number: %{type: ["string", "null"]},
      tax_declaration: %{
        type: ["object", "null"],
        properties: %{
          received_on: %{type: ["string", "null"], format: "date"},
          applies_from: %{type: ["string", "null"], format: "date"},
          tax_residency: %{type: ["string", "null"], enum: ["poland", "other", nil]},
          pit2: %{
            type: ["string", "null"],
            enum: ["none", "one_twelfth", "one_twenty_fourth", "one_thirty_sixth", nil]
          },
          employee_costs: %{type: ["string", "null"], enum: ["none", "standard", "elevated", nil]},
          youth_relief: %{type: ["string", "null"], enum: ["apply", "waived", nil]},
          pit0: %{type: ["string", "null"], enum: ["none", "returning", "family", "senior", nil]},
          tax_mode: %{type: ["string", "null"], enum: ["standard", "higher", "no_advance", nil]},
          request_year: %{type: ["integer", "null"]},
          preferential: %{
            type: ["string", "null"],
            enum: ["none", "joint_below", "joint_above", "single_below", "single_above", nil]
          },
          student: %{type: ["boolean", "null"]},
          student_until: %{type: ["string", "null"], format: "date"},
          other_employment: %{
            type: ["string", "null"],
            enum: ["none", "below_minimum", "at_least_minimum", "other", nil]
          },
          own_employer: %{type: ["boolean", "null"]},
          sickness: %{type: ["boolean", "null"]},
          copyright_costs: %{type: ["boolean", "null"]},
          ppk: %{type: ["string", "null"], enum: ["none", "participant", nil]},
          ppk_employee_rate: %{type: ["number", "null"]}
        }
      },
      payroll_input: %{
        type: ["object", "null"],
        properties: %{
          currency: %{type: ["string", "null"]},
          salary_month: %{type: ["string", "null"], format: "date"},
          payout_date: %{type: ["string", "null"], format: "date"},
          payout_date_basis: %{type: ["string", "null"], enum: ["planned", "actual", nil]},
          gross: %{type: ["number", "null"]},
          prior_taxable_income: %{type: ["number", "null"]},
          prior_social_base: %{type: ["number", "null"]},
          prior_exempt_income: %{type: ["number", "null"]},
          employer_ppk_income: %{type: ["number", "null"]},
          employer_ppk_date: %{type: ["string", "null"], format: "date"},
          single_payment: %{type: ["boolean", "null"]},
          standard_pay: %{type: ["boolean", "null"]},
          insurance_unchanged: %{type: ["boolean", "null"]}
        },
        required: ["currency"]
      }
    },
    required: ["document_type"]
  }

  @tax_declaration_fields [
    :received_on,
    :applies_from,
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
    :ppk_employee_rate
  ]

  @payroll_input_fields [
    :currency,
    :salary_month,
    :payout_date,
    :payout_date_basis,
    :gross,
    :prior_taxable_income,
    :prior_social_base,
    :prior_exempt_income,
    :employer_ppk_income,
    :employer_ppk_date,
    :single_payment,
    :standard_pay,
    :insurance_unchanged
  ]

  @payroll_fact_fields @payroll_input_fields -- [:currency, :salary_month]

  def run_processing(blob_url, blob, opts) do
    with {:ok, extracted_metadata} <- extract_metadata(blob_url) do
      process_document(extracted_metadata, blob, opts)
    end
  rescue
    error ->
      {:error, error}
  end

  defp extract_metadata(blob_url) do
    ProcessBlobHelpers.reducto_client().extract(blob_url, @employment_contract_schema,
      system_prompt: @employment_contract_system_prompt
    )
  end

  defp process_document(%{"document_type" => type} = metadata, blob, opts)
       when type in ["employment_contract", "signed_employment_contract"] do
    with :ok <- ensure_employment_contract_document(metadata),
         :ok <- validate_salary_metadata(metadata),
         {:ok, :ok} <-
           Ash.transact(
             [UserEmploymentContract, MemberTaxDeclaration, MemberPayrollInput],
             fn ->
               with :ok <- create_employment_contract(metadata, blob, opts) do
                 import_supporting_documents(metadata, blob, opts)
               end
             end,
             tenant: blob.organization_id
           ) do
      :ok
    end
  end

  defp process_document(%{"document_type" => "employee_tax_declaration"} = metadata, blob, opts) do
    import_tax_declaration(metadata["tax_declaration"], blob, opts)
  end

  defp process_document(%{"document_type" => "payroll_statement"} = metadata, blob, opts) do
    import_payroll_input(metadata["payroll_input"], blob, opts)
  end

  defp process_document(_metadata, _blob, _opts), do: {:error, :invalid_document}

  defp ensure_employment_contract_document(metadata) do
    with {:ok, _date} <- valid_date(metadata["starts_at"]),
         :ok <- validate_signed_at(metadata["signed_at"]) do
      :ok
    else
      _ -> {:error, :invalid_document}
    end
  end

  defp create_employment_contract(extracted_metadata, blob, opts) do
    signed_at = parse_date(extracted_metadata["signed_at"])

    attrs =
      extracted_metadata
      |> Map.delete("document_type")
      |> Map.delete("salary_currency")
      |> Map.delete("salary_amount")
      |> Map.delete("tax_declaration")
      |> Map.delete("payroll_input")
      |> Map.update("contract_type", nil, &parse_contract_type/1)
      |> Map.put("signed_at", signed_at)
      |> Map.put("status", determine_status(extracted_metadata))
      |> Map.put(
        "salary",
        Money.new!(
          extracted_metadata["salary_currency"],
          Decimal.new(to_string(extracted_metadata["salary_amount"]))
        )
      )
      |> Map.put("blob_id", blob.id)
      |> Map.put("member_id", trusted_member_id(blob))
      |> Map.put("bank_account_number", extracted_metadata["bank_account_number"])

    case Payroll.create_employment_contract(attrs, opts) do
      {:ok, _contract} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp import_supporting_documents(metadata, blob, opts) do
    with :ok <- import_tax_declaration(metadata["tax_declaration"], blob, opts) do
      import_payroll_input(metadata["payroll_input"], blob, opts)
    end
  end

  defp import_tax_declaration(declaration, blob, opts) when is_map(declaration) do
    attrs = explicit_fields(declaration, @tax_declaration_fields)

    if map_size(attrs) == 0 do
      :ok
    else
      attrs =
        attrs
        |> Map.put(:member_id, trusted_member_id(blob))
        |> Map.put(:source_blob_id, blob.id)

      case MemberTaxDeclaration.import_from_document(attrs, opts) do
        {:ok, _declaration} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp import_tax_declaration(_declaration, _blob, _opts), do: :ok

  defp import_payroll_input(%{"currency" => "PLN"} = payroll_input, blob, opts) do
    attrs =
      payroll_input
      |> explicit_fields(@payroll_input_fields)
      |> Map.delete(:currency)

    case parse_salary_month(attrs[:salary_month]) do
      {:ok, salary_month} ->
        if Enum.any?(@payroll_fact_fields, &Map.has_key?(attrs, &1)) do
          attrs =
            attrs
            |> Map.put(:salary_month, salary_month)
            |> Map.put(:member_id, trusted_member_id(blob))
            |> Map.put(:source_blob_id, blob.id)

          case MemberPayrollInput.import_from_document(attrs, opts) do
            {:ok, _input} -> :ok
            {:error, reason} -> {:error, reason}
          end
        else
          :ok
        end

      :missing_month ->
        :ok
    end
  end

  defp import_payroll_input(_payroll_input, _blob, _opts), do: :ok

  defp explicit_fields(values, fields) do
    fields
    |> Map.new(fn field -> {field, values[Atom.to_string(field)]} end)
    |> Enum.reject(fn {_field, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp parse_salary_month(%Date{day: 1} = date), do: {:ok, date}

  defp parse_salary_month(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, %Date{day: 1} = date} -> {:ok, date}
      _ -> :missing_month
    end
  end

  defp parse_salary_month(_), do: :missing_month

  defp trusted_member_id(blob) do
    blob.processing_metadata["member_id"] || blob.processing_metadata[:member_id]
  end

  defp validate_salary_metadata(%{"salary_amount" => amount, "salary_currency" => currency})
       when is_binary(amount) and amount != "" and is_binary(currency) and currency != "" do
    :ok
  end

  defp validate_salary_metadata(%{"salary_amount" => amount, "salary_currency" => currency})
       when is_number(amount) and is_binary(currency) and currency != "" do
    :ok
  end

  defp validate_salary_metadata(_), do: {:error, :missing_salary_metadata}

  defp determine_status(%{"document_type" => "signed_employment_contract"}), do: :signed
  defp determine_status(_), do: :pending_signature

  defp parse_contract_type(nil), do: nil
  defp parse_contract_type(type) when is_atom(type), do: type
  defp parse_contract_type(type) when is_binary(type), do: String.to_existing_atom(type)

  defp validate_signed_at(nil), do: :ok

  defp validate_signed_at(value) do
    case valid_date(value) do
      {:ok, _date} -> :ok
      _ -> {:error, :invalid_document}
    end
  end

  defp valid_date(value) when is_binary(value), do: Date.from_iso8601(value)
  defp valid_date(_), do: {:error, :invalid_date}

  defp parse_date(nil), do: nil
  defp parse_date(date_string) when is_binary(date_string), do: Date.from_iso8601!(date_string)
  defp parse_date(%Date{} = date), do: date
end
