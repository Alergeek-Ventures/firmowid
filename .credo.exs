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
        # Temporary ceiling requested for legacy task modules.
        {Credo.Check.Refactor.Nesting, [max_nesting: 40]},
        # TODOs are tracked as issues, not enforced in code
        {Credo.Check.Design.TagTODO, false},
        {Credo.Check.Design.TagFIXME, false}
      ]
    }
  ]
}
