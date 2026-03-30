%{
  configs: [
    %{
      name: "default",
      requires: ["./checks/*.ex"],
      checks: [
        {Checks.RejectDirectHistoryRates, []},
        {Checks.ClassAttributeFormat, []},
        {CredoNaming.Check.Consistency.ModuleFilename,
         [
           # Only enforce within lib/firmowid_web/ — exclude everything else
           excluded_paths: [
             ~r{^(?!lib/firmowid_web/)}
           ]
         ]},
        {Checks.CheckModulePlacement, []},
        # TODOs are tracked as issues, not enforced in code
        {Credo.Check.Design.TagTODO, false},
        {Credo.Check.Design.TagFIXME, false}
      ]
    }
  ]
}
