module Silt.Lint
  ( LintDiagnostic (..)
  , lintProgramPaths
  , renderLintDiagnosticsJson
  , renderLintDiagnostic
  ) where

import Control.Exception (IOException, try)
import Data.List (intercalate)
import Silt.Elab (checkProgram)
import Silt.Format (formatSExprSource)
import Silt.Source (readProgramBundle)

data LintDiagnostic = LintDiagnostic
  { lintDiagnosticPath :: Maybe FilePath
  , lintDiagnosticMessage :: String
  }
  deriving (Eq, Show)

data FormatLintResult = FormatLintResult
  { formatLintDiagnostics :: [LintDiagnostic]
  , formatLintCanCheckBundle :: Bool
  }

lintProgramPaths :: [FilePath] -> IO [LintDiagnostic]
lintProgramPaths paths =
  case paths of
    [] -> pure [LintDiagnostic Nothing "lint requires at least one source file"]
    _ -> do
      formatResults <- traverse lintFormat paths
      let formatDiagnostics = concatMap formatLintDiagnostics formatResults
      checkDiagnostics <-
        if all formatLintCanCheckBundle formatResults
          then do
            bundleResult <- readProgramBundle paths
            pure $
              case bundleResult >>= checkProgram of
                Left err -> [LintDiagnostic Nothing err]
                Right _ -> []
          else pure []
      pure (formatDiagnostics ++ checkDiagnostics)

lintFormat :: FilePath -> IO FormatLintResult
lintFormat path = do
  inputResult <- try (readFile path) :: IO (Either IOException String)
  case inputResult of
    Left err ->
      pure (FormatLintResult [LintDiagnostic (Just path) (show err)] False)
    Right input ->
      case formatSExprSource input of
        Left err ->
          pure (FormatLintResult [LintDiagnostic (Just path) err] False)
        Right formatted
          | formatted == input -> pure (FormatLintResult [] True)
          | otherwise ->
              pure (FormatLintResult [LintDiagnostic (Just path) "not canonical; run silt fmt"] True)

renderLintDiagnostic :: LintDiagnostic -> String
renderLintDiagnostic diagnostic =
  case lintDiagnosticPath diagnostic of
    Nothing -> lintDiagnosticMessage diagnostic
    Just path -> path ++ ": " ++ lintDiagnosticMessage diagnostic

renderLintDiagnosticsJson :: [LintDiagnostic] -> String
renderLintDiagnosticsJson diagnostics =
  unlines $
    [ "{"
    , "  \"schema\": \"silt.diagnostics.v0\","
    , "  \"diagnostics\": ["
    ]
      ++ diagnosticLines
      ++ [ "  ]"
         , "}"
         ]
  where
    diagnosticLines =
      case diagnostics of
        [] -> []
        _ -> [intercalate ",\n" (map renderLintDiagnosticJson diagnostics)]

renderLintDiagnosticJson :: LintDiagnostic -> String
renderLintDiagnosticJson diagnostic =
  "    {\"path\": "
    ++ renderJsonMaybeString (lintDiagnosticPath diagnostic)
    ++ ", \"message\": "
    ++ renderJsonString (lintDiagnosticMessage diagnostic)
    ++ ", \"severity\": \"error\"}"

renderJsonMaybeString :: Maybe String -> String
renderJsonMaybeString value =
  case value of
    Nothing -> "null"
    Just text -> renderJsonString text

renderJsonString :: String -> String
renderJsonString text =
  "\"" ++ concatMap renderJsonChar text ++ "\""

renderJsonChar :: Char -> String
renderJsonChar ch =
  case ch of
    '"' -> "\\\""
    '\\' -> "\\\\"
    '\b' -> "\\b"
    '\f' -> "\\f"
    '\n' -> "\\n"
    '\r' -> "\\r"
    '\t' -> "\\t"
    _ | fromEnum ch < 32 -> renderJsonControl ch
    _ -> [ch]

renderJsonControl :: Char -> String
renderJsonControl ch =
  let value = fromEnum ch
      hex = "0123456789abcdef"
   in "\\u00" ++ [hex !! (value `div` 16), hex !! (value `mod` 16)]
