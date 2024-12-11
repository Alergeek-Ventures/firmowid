defmodule Firmowid.Nbp.ApiClient do
  def get_exchange_rate(currency, date) do
    today = Date.utc_today()

    date_max_till_yesterday =
      case Date.compare(date, today) do
        :lt -> date
        :eq -> today
        :gt -> today
      end
      |> Date.shift(Duration.new!(day: -1))

    end_date_str = date_max_till_yesterday |> Date.to_iso8601()

    start_date_str =
      date_max_till_yesterday |> Date.shift(Duration.new!(day: -20)) |> Date.to_iso8601()

    %{
      body: %{
        "rates" => rates
      }
    } =
      Req.get!(
        "https://api.nbp.pl/api/exchangerates/rates/a/#{currency}/#{start_date_str}/#{end_date_str}"
      )

    %{"effectiveDate" => effective_date, "mid" => rate, "no" => table_number} = Enum.at(rates, -1)

    %{effective_date: effective_date, rate: rate, table_number: table_number}
  end
end
