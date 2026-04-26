module Silt.CLI (main) where
import Silt.Codegen.C
  ( emitDefinitionC
  , emitDefinitionFreestandingC
  , emitDefinitionsC
  , emitDefinitionsFreestandingC
  )
import Silt.Elab (CheckedDecl (..), checkProgram, normalizeDefinition, renderCheckedDecl)
import Silt.Parse (parseSExprs)
import Silt.Source (readProgramBundle)
import Silt.Syntax (Name, Program (..), prettyDecl)
import System.Environment (getArgs)
import System.Exit (die)

main :: IO ()
main = do
  args <- getArgs
  case args of
    ["version"] ->
      putStrLn "silt stage0 0.1.0.0"
    ["parse", path] -> do
      Program decls <- loadProgramBundle [path]
      mapM_ (putStrLn . prettyDecl) decls
    ["sexpr", path] -> do
      input <- readFile path
      case parseSExprs input of
        Left err -> die err
        Right sexprs -> mapM_ print sexprs
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
    _ ->
      putStrLn usage

usage :: String
usage =
  unlines
    [ "silt stage0"
    , ""
    , "Usage:"
    , "  silt version"
    , "  silt sexpr FILE"
    , "  silt parse FILE"
    , "  top-level (include relative-file.silt) is expanded for all commands except sexpr"
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

splitSourcesAndNames :: [String] -> Maybe ([FilePath], [Name])
splitSourcesAndNames args =
  case break (== "--") args of
    (paths, "--" : names) | not (null paths) && not (null names) -> Just (paths, names)
    _ -> Nothing

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
