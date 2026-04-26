module Silt.CLI (main) where
import Silt.Codegen.C
  ( emitDefinitionC
  , emitDefinitionFreestandingC
  , emitDefinitionsC
  , emitDefinitionsFreestandingC
  )
import Silt.Elab (CheckedDecl (..), checkProgram, normalizeDefinition, renderCheckedDecl)
import Silt.Parse (parseProgram, parseSExprs)
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
      input <- readFile path
      case parseProgram input of
        Left err -> die err
        Right (Program decls) -> mapM_ (putStrLn . prettyDecl) decls
    ["sexpr", path] -> do
      input <- readFile path
      case parseSExprs input of
        Left err -> die err
        Right sexprs -> mapM_ print sexprs
    ("check" : paths) | not (null paths) && "--" `notElem` paths -> do
      program <- readProgramBundle paths
      checked <- either die pure (checkProgram program)
      mapM_ (putStrLn . renderCheckedDecl) checked
      putStrLn ("Checked " ++ show (length checked) ++ " declarations.")
    ("abi-contracts" : paths) | not (null paths) && "--" `notElem` paths -> do
      program <- readProgramBundle paths
      checked <- either die pure (checkProgram program)
      mapM_ (putStrLn . renderCheckedDecl) (filter isAbiContract checked)
    ("target-contracts" : paths) | not (null paths) && "--" `notElem` paths -> do
      program <- readProgramBundle paths
      checked <- either die pure (checkProgram program)
      mapM_ (putStrLn . renderCheckedDecl) (filter isTargetContract checked)
    ("boot-contracts" : paths) | not (null paths) && "--" `notElem` paths -> do
      program <- readProgramBundle paths
      checked <- either die pure (checkProgram program)
      mapM_ (putStrLn . renderCheckedDecl) (filter isBootContract checked)
    ["norm", path, name] -> do
      input <- readFile path
      program <- either die pure (parseProgram input)
      output <- either die pure (normalizeDefinition program name)
      putStrLn output
    ("norm" : rest) | Just (paths, [name]) <- splitSourcesAndNames rest -> do
      program <- readProgramBundle paths
      output <- either die pure (normalizeDefinition program name)
      putStrLn output
    ["emit-c", path, name] -> do
      input <- readFile path
      program <- either die pure (parseProgram input)
      output <- either die pure (emitDefinitionC program name)
      putStrLn output
    ("emit-c" : rest) | Just (paths, [name]) <- splitSourcesAndNames rest -> do
      program <- readProgramBundle paths
      output <- either die pure (emitDefinitionC program name)
      putStrLn output
    ["emit-freestanding-c", path, name] -> do
      input <- readFile path
      program <- either die pure (parseProgram input)
      output <- either die pure (emitDefinitionFreestandingC program name)
      putStrLn output
    ("emit-freestanding-c" : rest) | Just (paths, [name]) <- splitSourcesAndNames rest -> do
      program <- readProgramBundle paths
      output <- either die pure (emitDefinitionFreestandingC program name)
      putStrLn output
    ("emit-c-bundle" : rest) | Just (paths, names) <- splitSourcesAndNames rest -> do
      program <- readProgramBundle paths
      output <- either die pure (emitDefinitionsC program names)
      putStrLn output
    ("emit-c-bundle" : path : names) | not (null names) -> do
      input <- readFile path
      program <- either die pure (parseProgram input)
      output <- either die pure (emitDefinitionsC program names)
      putStrLn output
    ("emit-freestanding-c-bundle" : rest) | Just (paths, names) <- splitSourcesAndNames rest -> do
      program <- readProgramBundle paths
      output <- either die pure (emitDefinitionsFreestandingC program names)
      putStrLn output
    ("emit-freestanding-c-bundle" : path : names) | not (null names) -> do
      input <- readFile path
      program <- either die pure (parseProgram input)
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

readProgramBundle :: [FilePath] -> IO Program
readProgramBundle paths = do
  programs <- traverse readProgramFile paths
  pure (concatPrograms programs)

readProgramFile :: FilePath -> IO Program
readProgramFile path = do
  input <- readFile path
  either (die . prefixError path) pure (parseProgram input)

prefixError :: FilePath -> String -> String
prefixError path err =
  path ++ ": " ++ err

concatPrograms :: [Program] -> Program
concatPrograms programs =
  Program [decl | Program decls <- programs, decl <- decls]

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
