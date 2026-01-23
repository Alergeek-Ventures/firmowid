defmodule Firmowid.Cldr do
  @moduledoc false
  use Cldr,
    otp_app: :firmowid,
    default_locale: :pl,
    gettext: Firmowid.Gettext,
    json_library: Jason,
    data_dir: "./priv/cldr",
    precompile_number_formats: ["¤¤#,##0.##"],
    providers: [Cldr.Number, Money, Cldr.DateTime, Cldr.Calendar, Cldr.Territory]
end
