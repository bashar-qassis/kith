%{
  configs: [
    %{
      name: "default",
      strict: true,
      files: %{
        included: [
          "lib/",
          "src/",
          "web/",
          "apps/*/lib/",
          "apps/*/src/",
          "apps/*/web/"
        ],
        excluded: [~r"/_build/", ~r"/deps/", ~r"/node_modules/"]
      },
      plugins: [],
      requires: [],
      parse_timeout: 5000,
      checks: %{
        enabled: [
          #
          # Consistency — reported but non-blocking (exit_status: 0)
          #
          {Credo.Check.Consistency.ExceptionNames, [exit_status: 0]},
          {Credo.Check.Consistency.LineEndings, [exit_status: 0]},
          {Credo.Check.Consistency.ParameterPatternMatching, [exit_status: 0]},
          {Credo.Check.Consistency.SpaceAroundOperators, [exit_status: 0]},
          {Credo.Check.Consistency.SpaceInParentheses, [exit_status: 0]},
          {Credo.Check.Consistency.TabsOrSpaces, [exit_status: 0]},

          #
          # Design — reported but non-blocking (exit_status: 0)
          #
          {Credo.Check.Design.AliasUsage,
           [
             priority: :low,
             if_nested_deeper_than: 2,
             if_called_more_often_than: 0,
             exit_status: 0
           ]},
          {Credo.Check.Design.TagTODO, [exit_status: 0]},
          {Credo.Check.Design.TagFIXME, [exit_status: 0]},

          #
          # Readability — reported but non-blocking (exit_status: 0)
          #
          {Credo.Check.Readability.AliasOrder, [exit_status: 0]},
          {Credo.Check.Readability.FunctionNames, [exit_status: 0]},
          {Credo.Check.Readability.LargeNumbers, [exit_status: 0]},
          {Credo.Check.Readability.MaxLineLength,
           [priority: :low, max_length: 120, exit_status: 0]},
          {Credo.Check.Readability.ModuleAttributeNames, [exit_status: 0]},
          # ModuleDoc disabled — Phoenix projects have many small modules where @moduledoc is noise
          {Credo.Check.Readability.ModuleDoc, false},
          {Credo.Check.Readability.ModuleNames, [exit_status: 0]},
          {Credo.Check.Readability.ParenthesesInCondition, [exit_status: 0]},
          {Credo.Check.Readability.ParenthesesOnZeroArityDefs, [exit_status: 0]},
          {Credo.Check.Readability.PipeIntoAnonymousFunctions, [exit_status: 0]},
          {Credo.Check.Readability.PredicateFunctionNames, [exit_status: 0]},
          {Credo.Check.Readability.PreferImplicitTry, [exit_status: 0]},
          {Credo.Check.Readability.RedundantBlankLines, [exit_status: 0]},
          {Credo.Check.Readability.Semicolons, [exit_status: 0]},
          {Credo.Check.Readability.SpaceAfterCommas, [exit_status: 0]},
          {Credo.Check.Readability.StringSigils, [exit_status: 0]},
          {Credo.Check.Readability.TrailingBlankLine, [exit_status: 0]},
          {Credo.Check.Readability.TrailingWhiteSpace, [exit_status: 0]},
          {Credo.Check.Readability.UnnecessaryAliasExpansion, [exit_status: 0]},
          {Credo.Check.Readability.VariableNames, [exit_status: 0]},
          {Credo.Check.Readability.WithSingleClause, [exit_status: 0]},

          #
          # Refactoring — reported but non-blocking (exit_status: 0)
          #
          {Credo.Check.Refactor.Apply, [exit_status: 0]},
          {Credo.Check.Refactor.CondStatements, [exit_status: 0]},
          {Credo.Check.Refactor.CyclomaticComplexity, [exit_status: 0]},
          {Credo.Check.Refactor.FunctionArity, [exit_status: 0]},
          {Credo.Check.Refactor.LongQuoteBlocks, [exit_status: 0]},
          {Credo.Check.Refactor.MatchInCondition, [exit_status: 0]},
          {Credo.Check.Refactor.MapJoin, [exit_status: 0]},
          {Credo.Check.Refactor.NegatedConditionsInUnless, [exit_status: 0]},
          {Credo.Check.Refactor.NegatedConditionsWithElse, [exit_status: 0]},
          {Credo.Check.Refactor.Nesting, [exit_status: 0]},
          {Credo.Check.Refactor.UnlessWithElse, [exit_status: 0]},
          {Credo.Check.Refactor.WithClauses, [exit_status: 0]},
          {Credo.Check.Refactor.FilterFilter, [exit_status: 0]},
          {Credo.Check.Refactor.RejectReject, [exit_status: 0]},
          {Credo.Check.Refactor.RedundantWithClauseResult, [exit_status: 0]},

          #
          # Warnings — BLOCKING (default exit_status)
          # These catch debug statements, unsafe patterns, and real mistakes
          #
          {Credo.Check.Warning.ApplicationConfigInModuleAttribute, []},
          {Credo.Check.Warning.BoolOperationOnSameValues, []},
          {Credo.Check.Warning.Dbg, []},
          {Credo.Check.Warning.ExpensiveEmptyEnumCheck, []},
          {Credo.Check.Warning.IExPry, []},
          {Credo.Check.Warning.IoInspect, []},
          {Credo.Check.Warning.MissedMetadataKeyInLoggerConfig, [exit_status: 0]},
          {Credo.Check.Warning.OperationOnSameValues, []},
          {Credo.Check.Warning.OperationWithConstantResult, []},
          {Credo.Check.Warning.RaiseInsideRescue, []},
          {Credo.Check.Warning.SpecWithStruct, []},
          {Credo.Check.Warning.UnsafeExec, []},
          {Credo.Check.Warning.UnusedEnumOperation, []},
          {Credo.Check.Warning.UnusedFileOperation, []},
          {Credo.Check.Warning.UnusedKeywordOperation, []},
          {Credo.Check.Warning.UnusedListOperation, []},
          {Credo.Check.Warning.UnusedPathOperation, []},
          {Credo.Check.Warning.UnusedRegexOperation, []},
          {Credo.Check.Warning.UnusedStringOperation, []},
          {Credo.Check.Warning.UnusedTupleOperation, []},
          {Credo.Check.Warning.WrongTestFileExtension, []}
        ],
        disabled: [
          {Credo.Check.Readability.ModuleDoc, []}
        ]
      }
    }
  ]
}
