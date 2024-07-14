defmodule Firmowid.Cldr do
  use Cldr,
    otp_app: :firmowid,
    default_locale: "pl",
    gettext: Firmowid.Gettext,
    json_library: Jason,
    data_dir: "./priv/cldr",
    precompile_number_formats: ["¤¤#,##0.##"],
    providers: [Cldr.Number]
end
