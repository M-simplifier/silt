module Silt.Build
  ( buildPackage
  , runPackage
  , testPackage
  ) where

import Control.Monad (forM, when)
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.Environment (lookupEnv)
import System.Exit (ExitCode (..), die, exitFailure)
import System.FilePath ((</>), takeDirectory)
import System.Process (callProcess, readProcessWithExitCode)
import Silt.Codegen.C (cSymbolName, emitDefinitionsC)
import Silt.Elab (normalizeDefinitionTerm)
import Silt.Package
  ( Package (..)
  , PackageTarget (..)
  , PackageTargetKind (..)
  , defaultBinTarget
  , packageTargetsOfKind
  , readPackageFile
  )
import Silt.Source (readProgramBundle)
import Silt.Syntax (Name, Program, Term (..), prettyTerm)

data EntryReturn
  = EntryUnit
  | EntryU8
  | EntryU64
  | EntryBool
  | EntryAddr
  | EntryPtr
  deriving (Eq, Show)

buildPackage :: Maybe Name -> IO ()
buildPackage maybeTargetName = do
  (root, package) <- loadPackage
  target <- either die pure (selectBuildTarget maybeTargetName package)
  output <- buildPackageTarget root target
  putStrLn ("Built " ++ packageTargetName target ++ " at " ++ output)

runPackage :: Maybe Name -> IO ()
runPackage maybeTargetName = do
  (root, package) <- loadPackage
  target <- either die pure (selectBuildTarget maybeTargetName package)
  output <- buildPackageTarget root target
  callProcess output []

testPackage :: IO ()
testPackage = do
  (root, package) <- loadPackage
  let testTargets = packageTargetsOfKind PackageTest package
  when (null testTargets) $
    die "package has no test targets"
  results <-
    forM testTargets $ \target -> do
      output <- buildPackageTarget root target
      (exitCode, stdoutText, stderrText) <- readProcessWithExitCode output [] ""
      putStr stdoutText
      putStr stderrText
      case exitCode of
        ExitSuccess -> do
          putStrLn ("PASS [" ++ packageTargetName target ++ "]")
          pure True
        ExitFailure code -> do
          putStrLn ("FAIL [" ++ packageTargetName target ++ "] exited " ++ show code)
          pure False
  if and results
    then putStrLn ("silt package tests: " ++ show (length results) ++ " passed")
    else exitFailure

loadPackage :: IO (FilePath, Package)
loadPackage = do
  let manifestPath = "Silt.pkg"
  exists <- doesFileExist manifestPath
  if exists
    then do
      packageResult <- readPackageFile manifestPath
      package <- either die pure packageResult
      pure (takeDirectory manifestPath, package)
    else die "missing Silt.pkg in current directory"

selectBuildTarget :: Maybe Name -> Package -> Either String PackageTarget
selectBuildTarget maybeTargetName package =
  case maybeTargetName of
    Nothing -> defaultBinTarget package
    Just name ->
      case [target | target <- packageTargets package, packageTargetName target == name] of
        [target] -> Right target
        [] -> Left ("unknown package target: " ++ name)
        _ -> Left ("ambiguous package target: " ++ name)

buildPackageTarget :: FilePath -> PackageTarget -> IO FilePath
buildPackageTarget root target = do
  let outDir = root </> "out" </> "silt" </> "debug"
  let buildDir = outDir </> (packageTargetName target ++ ".build")
  let cPath = buildDir </> (packageTargetName target ++ ".c")
  let harnessPath = buildDir </> (packageTargetName target ++ "_main.c")
  let outputPath = outDir </> packageTargetName target
  createDirectoryIfMissing True buildDir
  program <- loadTargetProgram root target
  (entryTy, _) <- either die pure (normalizeDefinitionTerm program (packageTargetEntry target))
  entryReturn <- either die pure (entryReturnFromType entryTy)
  when (packageTargetKind target == PackageTest && entryReturn /= EntryBool) $
    die "test target entry must return Bool"
  generated <- either die pure (emitDefinitionsC program [packageTargetEntry target])
  writeFile cPath generated
  writeFile harnessPath (renderHarness (packageTargetKind target) (packageTargetEntry target) entryReturn)
  cc <- maybe "cc" id <$> lookupEnv "CC"
  callProcess cc ["-std=c11", "-Wall", "-Wextra", "-o", outputPath, cPath, harnessPath]
  pure outputPath

loadTargetProgram :: FilePath -> PackageTarget -> IO Program
loadTargetProgram root target = do
  let sources = map (root </>) (packageTargetSources target)
  readProgramBundle sources >>= either die pure

entryReturnFromType :: Term -> Either String EntryReturn
entryReturnFromType ty =
  case ty of
    TPi {} -> Left "package entry must be a no-argument definition"
    _ -> runtimeReturn (unwrapEffectResult ty)

unwrapEffectResult :: Term -> Term
unwrapEffectResult ty =
  case ty of
    TApp (TApp (TApp (TGlobal "Eff") _) _) resultTy -> unwrapEffectResult resultTy
    _ -> ty

runtimeReturn :: Term -> Either String EntryReturn
runtimeReturn ty =
  case ty of
    TGlobal "Unit" -> Right EntryUnit
    TGlobal "U8" -> Right EntryU8
    TGlobal "U64" -> Right EntryU64
    TGlobal "Nat" -> Right EntryU64
    TGlobal "Bool" -> Right EntryBool
    TGlobal "Addr" -> Right EntryAddr
    TApp (TGlobal "Ptr") _ -> Right EntryPtr
    _ -> Left ("package entry result is not supported by hosted package build: " ++ prettyTerm ty)

renderHarness :: PackageTargetKind -> Name -> EntryReturn -> String
renderHarness kind entry ret =
  unlines
    ( [ "#include <stdint.h>"
      , "#include <stdio.h>"
      , ""
      , "uint8_t silt_host_put_byte(uint8_t byte) {"
      , "  return putchar((int)byte) == EOF ? 1u : 0u;"
      , "}"
      , ""
      , cReturnType ret ++ " " ++ cSymbolName entry ++ "(void);"
      , ""
      , "int main(void) {"
      ]
        ++ renderHarnessBody kind entry ret
        ++ ["}"]
    )

renderHarnessBody :: PackageTargetKind -> Name -> EntryReturn -> [String]
renderHarnessBody kind entry ret =
  case kind of
    PackageBin -> renderBinHarnessBody entry ret
    PackageTest -> renderTestHarnessBody entry ret

renderBinHarnessBody :: Name -> EntryReturn -> [String]
renderBinHarnessBody entry ret =
  case ret of
    EntryUnit ->
      [ "  " ++ cSymbolName entry ++ "();"
      , "  return 0;"
      ]
    _ ->
      [ "  return (int)(" ++ cSymbolName entry ++ "() & 255u);"
      ]

renderTestHarnessBody :: Name -> EntryReturn -> [String]
renderTestHarnessBody entry ret =
  case ret of
    EntryBool ->
      [ "  return " ++ cSymbolName entry ++ "() == 1u ? 0 : 1;"
      ]
    _ ->
      [ "  (void)" ++ cSymbolName entry ++ "();"
      , "  return 1;"
      ]

cReturnType :: EntryReturn -> String
cReturnType ret =
  case ret of
    EntryUnit -> "uint8_t"
    EntryU8 -> "uint8_t"
    EntryBool -> "uint8_t"
    EntryU64 -> "uint64_t"
    EntryAddr -> "uintptr_t"
    EntryPtr -> "uintptr_t"
