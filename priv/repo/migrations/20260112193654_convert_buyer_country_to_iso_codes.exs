defmodule Firmowid.Repo.Migrations.ConvertBuyerCountryToIsoCodes do
  use Ecto.Migration

  def up do
    # Convert buyer_country from full country names to ISO 2-letter codes
    # Production data contains: Sweden, USA, Poland, Belgia, and unidentified strings
    # Default unidentified strings to PL (Poland)

    execute """
    UPDATE sales_invoices 
    SET buyer_country = 
      CASE 
        WHEN LOWER(buyer_country) IN ('sweden', 'se') THEN 'SE'
        WHEN LOWER(buyer_country) IN ('usa', 'united states', 'united states of america', 'us') THEN 'US'
        WHEN LOWER(buyer_country) IN ('poland', 'polska', 'pl') THEN 'PL'
        WHEN LOWER(buyer_country) IN ('belgia', 'belgium', 'be') THEN 'BE'
        WHEN buyer_country IS NULL THEN 'PL'
        ELSE 'PL'
      END
    WHERE buyer_country IS NULL OR CHAR_LENGTH(buyer_country) != 2 OR buyer_country !~ '^[A-Z]{2}$'
    """
  end

  def down do
    # Note: This down migration is lossy - we cannot reliably convert back from ISO codes
    # to the original full country names, especially for unidentified strings that were
    # defaulted to 'PL'. This provides a best-effort conversion back to common names.

    execute """
    UPDATE sales_invoices 
    SET buyer_country = 
      CASE 
        WHEN buyer_country = 'SE' THEN 'Sweden'
        WHEN buyer_country = 'US' THEN 'USA'
        WHEN buyer_country = 'PL' THEN 'Poland'
        WHEN buyer_country = 'BE' THEN 'Belgium'
        ELSE buyer_country
      END
    WHERE CHAR_LENGTH(buyer_country) = 2 AND buyer_country ~ '^[A-Z]{2}$'
    """
  end
end
