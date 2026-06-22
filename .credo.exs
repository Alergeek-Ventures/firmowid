%{
  configs: [
    %{
      name: "default",
      requires: ["./checks/*.ex"],
      plugins: [{AshCredo, []}],
      checks: %{
        enabled: [
          {Checks.RejectDirectHistoryRates, []},
          {Checks.ClassAttributeFormat, []},
          {Checks.EnforceDesignSystemMarkup, []},
          {Checks.EnforceVerifiedRoutesInDsLink, []},
          {ExDNA.Credo, [min_mass: 40]},
          {CredoNaming.Check.Consistency.ModuleFilename,
           [
             # Only enforce within lib/firmowid_web/ — exclude everything else
             excluded_paths: [
               ~r{^(?!lib/firmowid_web/)}
             ]
           ]},
          {Checks.CheckModulePlacement, []},
          {Credo.Check.Design.DuplicatedCode, false},
          {ExSlop.Check.Warning.BlanketRescue, []},
          {ExSlop.Check.Warning.RescueWithoutReraise, []},
          {ExSlop.Check.Warning.RepoAllThenFilter, []},
          {ExSlop.Check.Warning.QueryInEnumMap, []},
          {ExSlop.Check.Warning.GenserverAsKvStore, []},
          {ExSlop.Check.Refactor.FilterNil, []},
          {ExSlop.Check.Refactor.RejectNil, []},
          {ExSlop.Check.Refactor.ReduceAsMap, []},
          {ExSlop.Check.Refactor.MapIntoLiteral, []},
          {ExSlop.Check.Refactor.IdentityPassthrough, []},
          {ExSlop.Check.Refactor.IdentityMap, []},
          {ExSlop.Check.Refactor.CaseTrueFalse, []},
          {ExSlop.Check.Refactor.TryRescueWithSafeAlternative, []},
          {ExSlop.Check.Refactor.WithIdentityElse, []},
          {ExSlop.Check.Refactor.WithIdentityDo, []},
          {ExSlop.Check.Refactor.SortThenReverse, []},
          {ExSlop.Check.Refactor.StringConcatInReduce, []},
          {ExSlop.Check.Readability.NarratorDoc, []},
          {ExSlop.Check.Readability.DocFalseOnPublicFunction, []},
          {ExSlop.Check.Readability.BoilerplateDocParams, []},
          {ExSlop.Check.Readability.ObviousComment, []},
          {ExSlop.Check.Readability.StepComment, []},
          {ExSlop.Check.Readability.NarratorComment, []},

          # Temporary ceiling requested for legacy task modules.
          {Credo.Check.Refactor.Nesting, [max_nesting: 40]},
          # TODOs are tracked as issues, not enforced in code
          {Credo.Check.Design.TagTODO, false},
          {Credo.Check.Design.TagFIXME, false},
          {AshCredo.Check.Warning.AuthorizeFalse, [excluded_paths: [~r{/(test|deps|_build)/}, ~r/_test\.exs$/]]},
          {AshCredo.Check.Warning.AuthorizerWithoutPolicies, []},
          {AshCredo.Check.Warning.EmptyDomain, []},
          {AshCredo.Check.Warning.MissingDomain, []},
          {AshCredo.Check.Warning.OverlyPermissivePolicy, []},
          {AshCredo.Check.Warning.SensitiveAttributeExposed, []},
          {AshCredo.Check.Warning.SensitiveFieldInAccept, []},
          {AshCredo.Check.Warning.UnknownAction, []},
          {AshCredo.Check.Warning.WildcardAcceptOnAction, []},
          {AshCredo.Check.Refactor.DirectiveInFunctionBody, []},
          {AshCredo.Check.Refactor.LargeResource, []},
          {AshCredo.Check.Refactor.RaisingCall, false},
          {AshCredo.Check.Refactor.UseCodeInterface, false},
          {AshCredo.Check.Design.MissingCodeInterface, false},
          {AshCredo.Check.Design.MissingIdentity, [identity_candidates: []]},
          {AshCredo.Check.Design.MissingPrimaryAction, []},
          {AshCredo.Check.Design.MissingTimestamps, []},
          {AshCredo.Check.Readability.ActionMissingDescription, []},
          {AshCredo.Check.Readability.BelongsToMissingAllowNil, []}
        ]
      }
    }
  ]
}
