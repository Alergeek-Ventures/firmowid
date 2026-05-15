defmodule FirmowidWeb.Invoicing.Utilities.QueryCodec do
  @moduledoc """
  Canonical codec for user-facing invoicing query values.
  """

  alias FirmowidWeb.Infrastructure.Utilities.CounterpartyTypeCodec
  alias FirmowidWeb.Infrastructure.Utilities.PolishValues

  @filter_values %{
    "wszystkie" => :all,
    "faktury" => :invoices,
    "transakcje" => :transactions,
    "nieprzypisane" => :unmatched
  }
  @filter_params Map.new(@filter_values, fn {key, value} -> {value, key} end)

  @subfilter_values %{
    "oplacone" => :oplacone,
    "nieoplacone" => :nieoplacone,
    "dopasowane" => :dopasowane,
    "bez_dokumentu" => :bez_dokumentu
  }
  @subfilter_params Map.new(@subfilter_values, fn {key, value} -> {value, key} end)

  @view_mode_values %{"lista" => :list}
  @view_mode_params Map.new(@view_mode_values, fn {key, value} -> {value, key} end)

  @last_sales_invoices_tab_values %{"ostatnie_faktury" => :last_sales_invoices}
  @last_sales_invoices_tab_params Map.new(@last_sales_invoices_tab_values, fn {key, value} ->
                                    {value, key}
                                  end)

  @creator_tab_values %{
    "ostatni_kontrahenci" => :last_counterparties,
    "ostatnie_faktury" => :last_invoices
  }
  @creator_tab_params Map.new(@creator_tab_values, fn {key, value} -> {value, key} end)

  @invoicing_index_param_keys ~w(miesiac filtr podfiltr widok)

  @type filter :: :all | :invoices | :transactions | :unmatched
  @type subfilter :: :oplacone | :nieoplacone | :dopasowane | :bez_dokumentu
  @type view_mode :: :dashboard | :list
  @type creator_tab :: :last_counterparties | :last_invoices
  @type counterparty_type :: CounterpartyTypeCodec.counterparty_type()
  @type invoice_language :: :pl | :en

  @doc """
  Returns the allowlisted user-facing param keys for the invoicing index route.
  """
  @spec invoicing_index_param_keys() :: [String.t()]
  def invoicing_index_param_keys, do: @invoicing_index_param_keys

  @doc """
  Parses the invoicing filter query value.
  """
  @spec parse_filter(String.t() | nil) :: filter() | nil
  def parse_filter(raw_value), do: PolishValues.parse_atom(raw_value, @filter_values)

  @doc """
  Encodes the invoicing filter query value.
  """
  @spec encode_filter(filter()) :: String.t()
  def encode_filter(filter), do: PolishValues.encode_atom(filter, @filter_params)

  @doc """
  Parses the invoicing subfilter query value.
  """
  @spec parse_subfilter(String.t() | nil) :: subfilter() | nil
  def parse_subfilter(raw_value), do: PolishValues.parse_atom(raw_value, @subfilter_values)

  @doc """
  Encodes the invoicing subfilter query value.
  """
  @spec encode_subfilter(subfilter()) :: String.t()
  def encode_subfilter(subfilter), do: PolishValues.encode_atom(subfilter, @subfilter_params)

  @doc """
  Parses the invoicing view-mode query value.
  """
  @spec parse_view_mode(String.t() | nil) :: view_mode() | nil
  def parse_view_mode(raw_value), do: PolishValues.parse_atom(raw_value, @view_mode_values)

  @doc """
  Encodes the invoicing view-mode query value.
  """
  @spec encode_view_mode(:list) :: String.t()
  def encode_view_mode(view_mode), do: PolishValues.encode_atom(view_mode, @view_mode_params)

  @doc """
  Parses the last-sales-invoices tab query value.
  """
  @spec parse_last_sales_invoices_tab(String.t() | nil) :: :last_sales_invoices | nil
  def parse_last_sales_invoices_tab(raw_value), do: PolishValues.parse_atom(raw_value, @last_sales_invoices_tab_values)

  @doc """
  Encodes the last-sales-invoices tab query value.
  """
  @spec encode_last_sales_invoices_tab(:last_sales_invoices) :: String.t()
  def encode_last_sales_invoices_tab(tab), do: PolishValues.encode_atom(tab, @last_sales_invoices_tab_params)

  @doc """
  Parses the sales-invoice creator tab query value.
  """
  @spec parse_creator_tab(String.t() | nil) :: creator_tab() | nil
  def parse_creator_tab(raw_value), do: PolishValues.parse_atom(raw_value, @creator_tab_values)

  @doc """
  Encodes the sales-invoice creator tab query value.
  """
  @spec encode_creator_tab(creator_tab()) :: String.t()
  def encode_creator_tab(tab), do: PolishValues.encode_atom(tab, @creator_tab_params)

  @doc """
  Parses the counterparty-type query value.
  """
  @spec parse_counterparty_type(String.t() | nil) :: counterparty_type() | nil
  def parse_counterparty_type(raw_value), do: CounterpartyTypeCodec.parse(raw_value)

  @doc """
  Encodes the counterparty-type query value.
  """
  @spec encode_counterparty_type(counterparty_type()) :: String.t()
  def encode_counterparty_type(type), do: CounterpartyTypeCodec.encode(type)

  @doc """
  Parses the public invoice language query value.
  """
  @spec parse_invoice_language(String.t() | nil) :: invoice_language() | nil
  def parse_invoice_language(raw_value), do: PolishValues.parse_language(raw_value)

  @doc """
  Encodes the public invoice language query value.
  """
  @spec encode_invoice_language(invoice_language()) :: String.t()
  def encode_invoice_language(language), do: PolishValues.encode_language(language)
end
