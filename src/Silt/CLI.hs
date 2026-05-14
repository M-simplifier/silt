module Silt.CLI (main) where
import Control.Exception (evaluate)
import Control.Monad (when)
import Data.Char (isSpace)
import Data.List (isInfixOf)
import Silt.Build (buildPackage, runPackage, testPackage)
import Silt.Codegen.C
  ( emitDefinitionC
  , emitDefinitionFreestandingC
  , emitDefinitionsC
  , emitDefinitionsFreestandingC
  )
import Silt.Elab (CheckedDecl (..), checkProgram, normalizeDefinition, renderCheckedDecl)
import Silt.Format (formatSExprSource)
import Silt.Lint (lintProgramPaths, renderLintDiagnostic, renderLintDiagnosticsJson)
import Silt.PackageDoc (docPackage)
import Silt.Parse (parseSExprs)
import Silt.Source (readProgramBundle)
import Silt.Syntax (Name, Program (..), prettyDecl)
import System.Directory (createDirectory, doesDirectoryExist, doesFileExist)
import System.Environment (getArgs)
import System.Exit (die, exitFailure)
import System.FilePath ((</>))
import System.IO (hPutStr, hPutStrLn, stderr)

main :: IO ()
main = do
  args <- getArgs
  case args of
    ["version"] ->
      putStrLn "silt stage0 0.1.0.0"
    ["new", packageName] ->
      createPackage packageName
    ["build"] ->
      buildPackage Nothing
    ["build", target] ->
      buildPackage (Just target)
    ["run"] ->
      runPackage Nothing []
    ["run", target] ->
      runPackage (Just target) []
    ("run" : "--" : programArgs) ->
      runPackage Nothing programArgs
    ("run" : target : "--" : programArgs) ->
      runPackage (Just target) programArgs
    ["test"] ->
      testPackage Nothing
    ["test", target] ->
      testPackage (Just target)
    ["doc"] ->
      docPackage
    ["help"] ->
      putStr usage
    ["parse", path] -> do
      Program decls <- loadProgramBundle [path]
      mapM_ (putStrLn . prettyDecl) decls
    ["sexpr", path] -> do
      input <- readFile path
      case parseSExprs input of
        Left err -> die err
        Right sexprs -> mapM_ print sexprs
    ["fmt", "--write"] ->
      die "silt fmt --write requires at least one file"
    ("fmt" : "--write" : paths) | not (null paths) && "--" `notElem` paths -> do
      mapM_ formatWrite paths
    ["fmt", "--check"] ->
      die "silt fmt --check requires at least one file"
    ("fmt" : "--check" : paths) | not (null paths) && "--" `notElem` paths -> do
      results <- mapM formatCheck paths
      if and results then pure () else exitFailure
    ["fmt", path] -> do
      input <- readFile path
      output <- either die pure (formatSExprSource input)
      putStr output
    ("lint" : paths) | not (null paths) && "--" `notElem` paths -> do
      diagnostics <- lintProgramPaths paths
      case diagnostics of
        [] -> putStrLn ("Lint passed for " ++ show (length paths) ++ " source file(s).")
        _ -> do
          mapM_ (hPutStrLn stderr . renderLintDiagnostic) diagnostics
          exitFailure
    ("diagnostics" : "--json" : paths) | not (null paths) && "--" `notElem` paths -> do
      diagnostics <- lintProgramPaths paths
      putStr (renderLintDiagnosticsJson diagnostics)
      when (not (null diagnostics)) exitFailure
    ("check" : paths) | not (null paths) && "--" `notElem` paths -> do
      program <- loadProgramBundle paths
      checked <- either die pure (checkProgram program)
      mapM_ (putStrLn . renderCheckedDecl) checked
      putStrLn ("Checked " ++ show (length checked) ++ " declarations.")
    ("abi-contracts" : paths) | not (null paths) && "--" `notElem` paths -> do
      program <- loadProgramBundle paths
      checked <- either die pure (checkProgram program)
      mapM_ (putStrLn . renderCheckedDecl) (filter isAbiContract checked)
    ("target-contracts" : paths) | not (null paths) && "--" `notElem` paths -> do
      program <- loadProgramBundle paths
      checked <- either die pure (checkProgram program)
      mapM_ (putStrLn . renderCheckedDecl) (filter isTargetContract checked)
    ("boot-contracts" : paths) | not (null paths) && "--" `notElem` paths -> do
      program <- loadProgramBundle paths
      checked <- either die pure (checkProgram program)
      mapM_ (putStrLn . renderCheckedDecl) (filter isBootContract checked)
    ["norm", path, name] -> do
      program <- loadProgramBundle [path]
      output <- either die pure (normalizeDefinition program name)
      putStrLn output
    ("norm" : rest) | Just (paths, [name]) <- splitSourcesAndNames rest -> do
      program <- loadProgramBundle paths
      output <- either die pure (normalizeDefinition program name)
      putStrLn output
    ["emit-c", path, name] -> do
      program <- loadProgramBundle [path]
      output <- either die pure (emitDefinitionC program name)
      putStrLn output
    ("emit-c" : rest) | Just (paths, [name]) <- splitSourcesAndNames rest -> do
      program <- loadProgramBundle paths
      output <- either die pure (emitDefinitionC program name)
      putStrLn output
    ["emit-freestanding-c", path, name] -> do
      program <- loadProgramBundle [path]
      output <- either die pure (emitDefinitionFreestandingC program name)
      putStrLn output
    ("emit-freestanding-c" : rest) | Just (paths, [name]) <- splitSourcesAndNames rest -> do
      program <- loadProgramBundle paths
      output <- either die pure (emitDefinitionFreestandingC program name)
      putStrLn output
    ("emit-c-bundle" : rest) | Just (paths, names) <- splitSourcesAndNames rest -> do
      program <- loadProgramBundle paths
      output <- either die pure (emitDefinitionsC program names)
      putStrLn output
    ("emit-c-bundle" : path : names) | not (null names) -> do
      program <- loadProgramBundle [path]
      output <- either die pure (emitDefinitionsC program names)
      putStrLn output
    ("emit-freestanding-c-bundle" : rest) | Just (paths, names) <- splitSourcesAndNames rest -> do
      program <- loadProgramBundle paths
      output <- either die pure (emitDefinitionsFreestandingC program names)
      putStrLn output
    ("emit-freestanding-c-bundle" : path : names) | not (null names) -> do
      program <- loadProgramBundle [path]
      output <- either die pure (emitDefinitionsFreestandingC program names)
      putStrLn output
    _ -> do
      hPutStr stderr usage
      exitFailure

usage :: String
usage =
  unlines
    [ "silt stage0"
    , ""
    , "Usage:"
    , "  silt help"
    , "  silt version"
    , "  silt new NAME"
    , "  silt build [TARGET]"
    , "  silt run [TARGET] [-- ARG...]"
    , "  silt test [TARGET]"
    , "  silt doc"
    , "  silt sexpr FILE"
    , "  silt fmt FILE"
    , "  silt fmt --write FILE..."
    , "  silt fmt --check FILE..."
    , "  silt lint FILE..."
    , "  silt diagnostics --json FILE..."
    , "  silt parse FILE"
    , "  top-level (include relative-file.silt) is expanded for all commands except sexpr and fmt"
    , "  silt check FILE..."
    , "  silt abi-contracts FILE..."
    , "  silt target-contracts FILE..."
    , "  silt boot-contracts FILE..."
    , "  silt norm FILE NAME"
    , "  silt norm FILE... -- NAME"
    , "  silt emit-c FILE NAME"
    , "  silt emit-c FILE... -- NAME"
    , "  silt emit-c-bundle FILE NAME..."
    , "  silt emit-c-bundle FILE... -- NAME..."
    , "  silt emit-freestanding-c FILE NAME"
    , "  silt emit-freestanding-c FILE... -- NAME"
    , "  silt emit-freestanding-c-bundle FILE NAME..."
    , "  silt emit-freestanding-c-bundle FILE... -- NAME..."
    ]

loadProgramBundle :: [FilePath] -> IO Program
loadProgramBundle paths =
  readProgramBundle paths >>= either die pure

formatCheck :: FilePath -> IO Bool
formatCheck path = do
  input <- readFile path
  case formatSExprSource input of
    Left err -> do
      hPutStrLn stderr (path ++ ": " ++ err)
      pure False
    Right output
      | input == output -> pure True
      | otherwise -> do
          hPutStrLn stderr (path ++ ": needs formatting")
          pure False

formatWrite :: FilePath -> IO ()
formatWrite path = do
  input <- readFile path
  output <- either die pure (formatSExprSource input)
  _ <- evaluate (length output)
  writeFile path output

splitSourcesAndNames :: [String] -> Maybe ([FilePath], [Name])
splitSourcesAndNames args =
  case break (== "--") args of
    (paths, "--" : names) | not (null paths) && not (null names) -> Just (paths, names)
    _ -> Nothing

createPackage :: String -> IO ()
createPackage packageName = do
  either die pure (validateNewPackageName packageName)
  directoryExists <- doesDirectoryExist packageName
  fileExists <- doesFileExist packageName
  when (directoryExists || fileExists) $
    die ("package path already exists: " ++ packageName)
  createDirectory packageName
  createDirectory (packageName </> "src")
  createDirectory (packageName </> "tests")
  writeFile (packageName </> "Silt.pkg") (newPackageManifest packageName)
  writeFile (packageName </> "src" </> "main.silt") newPackageAppSource
  writeFile (packageName </> "tests" </> "main.silt") newPackageTestSource
  putStrLn ("Created Silt package " ++ packageName)

validateNewPackageName :: String -> Either String ()
validateNewPackageName packageName
  | null packageName = Left "package name cannot be empty"
  | packageName == "." || packageName == ".." = Left "package name cannot be '.' or '..'"
  | "/" `isInfixOf` packageName = Left "package name cannot contain '/'"
  | "\\" `isInfixOf` packageName = Left "package name cannot contain '\\'"
  | any isPackageNameDelimiter packageName = Left "package name must be a simple S-expression atom"
  | otherwise = Right ()

isPackageNameDelimiter :: Char -> Bool
isPackageNameDelimiter ch =
  isSpace ch || ch == '(' || ch == ')' || ch == ';'

newPackageManifest :: String -> String
newPackageManifest packageName =
  unlines
    [ "(package"
    , "  " ++ packageName
    , "  (bin " ++ packageName ++ " (sources src/main.silt) (entry app-main))"
    , "  (test " ++ packageName ++ "-test (sources src/main.silt tests/main.silt) (entry app-test)))"
    ]

newPackageAppSource :: String
newPackageAppSource =
  unlines
    [ "(claim app-main U64)"
    , ""
    , "(def app-main (u64 0))"
    ]

newPackageTestSource :: String
newPackageTestSource =
  unlines
    [ "(claim app-test Bool)"
    , ""
    , "(def app-test True)"
    ]

isAbiContract :: CheckedDecl -> Bool
isAbiContract checked =
  case checked of
    CheckedAbiContract _ _ -> True
    _ -> False

isTargetContract :: CheckedDecl -> Bool
isTargetContract checked =
  case checked of
    CheckedTargetContract _ _ -> True
    _ -> False

isBootContract :: CheckedDecl -> Bool
isBootContract checked =
  case checked of
    CheckedBootContract _ _ -> True
    _ -> False
