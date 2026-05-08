module Silt.Lint
  ( LintDiagnostic (..)
  , lintProgramPaths
  , renderLintDiagnostic
  ) where

import Control.Exception (IOException, try)
import Silt.Elab (checkProgram)
import Silt.Format (formatSExprSource)
import Silt.Source (readProgramBundle)

data LintDiagnostic = LintDiagnostic
  { lintDiagnosticPath :: Maybe FilePath
  , lintDiagnosticMessage :: String
  }
  deriving (Eq, Show)

lintProgramPaths :: [FilePath] -> IO [LintDiagnostic]
lintProgramPaths paths =
  case paths of
    [] -> pure [LintDiagnostic Nothing "lint requires at least one source file"]
    _ -> do
      formatDiagnostics <- concat <$> traverse lintFormat paths
      bundleResult <- readProgramBundle paths
      let checkDiagnostics =
            case bundleResult >>= checkProgram of
              Left err -> [LintDiagnostic Nothing err]
              Right _ -> []
      pure (formatDiagnostics ++ checkDiagnostics)

lintFormat :: FilePath -> IO [LintDiagnostic]
lintFormat path = do
  inputResult <- try (readFile path) :: IO (Either IOException String)
  case inputResult of
    Left err ->
      pure [LintDiagnostic (Just path) (show err)]
    Right input ->
      case formatSExprSource input of
        Left err ->
          pure [LintDiagnostic (Just path) err]
        Right formatted
          | formatted == input -> pure []
          | otherwise ->
              pure [LintDiagnostic (Just path) "not canonical; run silt fmt"]

renderLintDiagnostic :: LintDiagnostic -> String
renderLintDiagnostic diagnostic =
  case lintDiagnosticPath diagnostic of
    Nothing -> lintDiagnosticMessage diagnostic
    Just path -> path ++ ": " ++ lintDiagnosticMessage diagnostic
