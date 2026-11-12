defmodule Firmowid.Invoicing.SalesInvoice.Numbering do
  @moduledoc """
  Sales invoice numbers: the supported numbering formats, organization initials
  used as a yearly prefix, the organization's existing numbers and the next free
  number of a sequence.
  """

  alias Firmowid.Invoicing.SalesInvoice

  require Ash.Query

  @type sequence :: {:monthly | :yearly, String.t() | nil}

  @monthly_number_regex ~r/^(\d+)\/(\d+)\/(\d+)(?:\/(.+))?$/
  @yearly_number_regex ~r/^(?:([A-Z]+)\/)?(\d+)\/(\d{4})$/

  @doc """
  Parses an invoice number in one of the supported numbering formats:

    * monthly `NN/MM/YYYY[/SERIES]`, e.g. `01/10/2026` or `01/10/2026/A`,
    * yearly `[PREFIX/]N/YYYY`, e.g. `1/2026` or `BC/1/2026`, where `PREFIX`
      is uppercase ASCII letters (usually the organization initials).

  Returns the numbering `format` (`:monthly` or `:yearly`), counter, month
  (`nil` for yearly numbers), year and optional series (the suffix of a
  monthly number or the prefix of a yearly one), or `:error` for other input.
  """
  @spec parse_invoice_number(term()) ::
          {:ok,
           %{
             format: :monthly | :yearly,
             num: pos_integer(),
             month: pos_integer() | nil,
             year: pos_integer(),
             series: String.t() | nil
           }}
          | :error
  def parse_invoice_number(invoice_number) when is_binary(invoice_number) do
    case Regex.run(@monthly_number_regex, invoice_number) do
      [_, num, month, year | series] ->
        {:ok,
         %{
           format: :monthly,
           num: String.to_integer(num),
           month: String.to_integer(month),
           year: String.to_integer(year),
           series: List.first(series)
         }}

      nil ->
        parse_yearly_invoice_number(invoice_number)
    end
  end

  def parse_invoice_number(_), do: :error

  defp parse_yearly_invoice_number(invoice_number) do
    case Regex.run(@yearly_number_regex, invoice_number) do
      [_, prefix, num, year] ->
        {:ok,
         %{
           format: :yearly,
           num: String.to_integer(num),
           month: nil,
           year: String.to_integer(year),
           series: if(prefix != "", do: prefix)
         }}

      nil ->
        :error
    end
  end

  @doc """
  Formats an invoice number for a counter, numbering format, date and optional
  series: monthly as `NN/MM/YYYY[/SERIES]`, yearly as `[SERIES/]N/YYYY`.
  """
  @spec format_invoice_number(pos_integer(), :monthly | :yearly, Date.t(), String.t() | nil) ::
          String.t()
  def format_invoice_number(num, :monthly, date, series) do
    Enum.join(
      [pad_two(num), pad_two(date.month), date.year] ++ List.wrap(series),
      "/"
    )
  end

  def format_invoice_number(num, :yearly, date, series) do
    Enum.join(List.wrap(series) ++ [num, date.year], "/")
  end

  defp pad_two(number), do: String.pad_leading("#{number}", 2, "0")

  @legal_form_words ~w(
    SP SPOLKA Z OO O OGRANICZONA ODPOWIEDZIALNOSCIA SA AKCYJNA SK SKA SPK SJ JAWNA
    KOMANDYTOWA KOMANDYTOWO PARTNERSKA SPP SC CYWILNA
  )

  @doc """
  Derives uppercase ASCII initials from an organization name, used as the
  prefix of the `INITIALS/N/YYYY` yearly numbering.

  The name is split into words on whitespace and hyphens. Words that are a
  Polish legal form (`sp.`, `z`, `o.o.`, `spółka`, `ograniczoną`,
  `odpowiedzialnością`, `S.A.`, `sp.k.`, `sp.j.`, `s.c.`, …, compared without
  dots, diacritics and case) are skipped. The first letter of every remaining
  word is transliterated to ASCII and upcased; words starting with a
  non-letter contribute nothing. For example
  `"Bytecraft Collective spółka z ograniczoną odpowiedzialnością"` and
  `"Bytecraft Collective sp. z o.o."` both give `"BC"`. Returns `nil` when no
  letter remains.
  """
  @spec organization_initials(String.t()) :: String.t() | nil
  def organization_initials(name) do
    name
    |> AnyAscii.transliterate()
    |> IO.iodata_to_binary()
    |> String.upcase()
    |> String.split(~r/[\s\-]+/, trim: true)
    |> Enum.reject(&(String.replace(&1, ".", "") in @legal_form_words))
    |> Enum.map_join(&String.slice(&1, 0, 1))
    |> String.replace(~r/[^A-Z]/, "")
    |> case do
      "" -> nil
      initials -> initials
    end
  end

  @doc """
  Returns visible non-nil invoice numbers, optionally omitting one invoice.
  """
  @spec read_all_invoice_numbers(keyword(), Ash.UUID.t() | nil) :: [String.t()]
  def read_all_invoice_numbers(opts, omit_invoice_id \\ nil) do
    query =
      SalesInvoice
      |> Ash.Query.filter(not is_nil(invoice_number))
      |> Ash.Query.select([:invoice_number])

    query = if omit_invoice_id, do: Ash.Query.filter(query, id != ^omit_invoice_id), else: query

    query
    |> then(&SalesInvoice.list!(Keyword.put(opts, :query, &1)))
    |> Enum.map(& &1.invoice_number)
  end

  @doc """
  Returns the next free number of each `{format, series}` sequence on `date`:
  one above the sequence's highest counter among `numbers` in the date's month
  (monthly) or year (yearly), skipping numbers already in `numbers`.
  """
  @spec next_numbers([String.t()], Date.t(), [sequence()]) :: %{sequence() => String.t()}
  def next_numbers(numbers, date, sequences) do
    counters = current_number_counters(numbers, date)
    occupied = MapSet.new(numbers)

    Map.new(sequences, fn {format, series} = sequence ->
      number =
        counters
        |> Map.get(sequence, 0)
        |> Kernel.+(1)
        |> Stream.iterate(&(&1 + 1))
        |> Enum.find_value(fn counter ->
          candidate = format_invoice_number(counter, format, date, series)
          if not MapSet.member?(occupied, candidate), do: candidate
        end)

      {sequence, number}
    end)
  end

  @doc """
  Returns the next free number of one sequence on `date`, see `next_numbers/3`.
  """
  @spec next_number([String.t()], :monthly | :yearly, Date.t(), String.t() | nil) :: String.t()
  def next_number(numbers, format, date, series) do
    numbers
    |> next_numbers(date, [{format, series}])
    |> Map.fetch!({format, series})
  end

  @doc """
  Lists the warnings about `number` issued on `date`, given the organization's
  other `numbers` and the `suggestions` offered instead: an unsupported format
  and a number already in use carry the suggestions, a number above its
  sequence's next free number carries that number.
  """
  @spec warnings(String.t(), Date.t(), [String.t()], [String.t()]) :: [
          {:invalid_format | :duplicate, [String.t()]} | {:gap, String.t()}
        ]
  def warnings(number, date, numbers, suggestions) do
    parsed = parse_invoice_number(number)

    Enum.reject(
      [
        if(parsed == :error, do: {:invalid_format, suggestions}),
        if(number in numbers, do: {:duplicate, suggestions}),
        gap_warning(parsed, numbers, date)
      ],
      &is_nil/1
    )
  end

  defp gap_warning({:ok, %{num: num, format: format, series: series}}, numbers, date) do
    expected = next_number(numbers, format, date, series)

    case parse_invoice_number(expected) do
      {:ok, %{num: expected_num}} when num > expected_num -> {:gap, expected}
      _ -> nil
    end
  end

  defp gap_warning(:error, _numbers, _date), do: nil

  defp current_number_counters(numbers, date) do
    Enum.reduce(numbers, %{}, fn number, counters ->
      with {:ok, parsed} <- parse_invoice_number(number),
           true <- number_in_period?(number, parsed.format, date) do
        Map.update(
          counters,
          {parsed.format, parsed.series},
          parsed.num,
          &Kernel.max(&1, parsed.num)
        )
      else
        _ -> counters
      end
    end)
  end

  defp number_in_period?(number, :monthly, date) do
    [_counter, month, year | _] = String.split(number, "/", parts: 4)

    month == String.pad_leading(Integer.to_string(date.month), 2, "0") and
      year == Integer.to_string(date.year)
  end

  defp number_in_period?(number, :yearly, date), do: List.last(String.split(number, "/")) == Integer.to_string(date.year)
end
