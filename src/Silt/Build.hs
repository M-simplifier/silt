module Silt.Build
  ( buildPackage
  , runPackage
  , testPackage
  ) where

import Control.Monad (forM, when)
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.Environment (lookupEnv)
import System.Exit (ExitCode (..), die, exitFailure, exitWith)
import System.FilePath ((</>), takeDirectory)
import System.Process (callProcess, rawSystem, readProcessWithExitCode)
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

runPackage :: Maybe Name -> [String] -> IO ()
runPackage maybeTargetName programArgs = do
  (root, package) <- loadPackage
  target <- either die pure (selectBuildTarget maybeTargetName package)
  output <- buildPackageTarget root target
  exitCode <- rawSystem output programArgs
  exitWith exitCode

testPackage :: Maybe Name -> IO ()
testPackage maybeTargetName = do
  (root, package) <- loadPackage
  testTargets <- either die pure (selectTestTargets maybeTargetName package)
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

selectTestTargets :: Maybe Name -> Package -> Either String [PackageTarget]
selectTestTargets maybeTargetName package =
  case maybeTargetName of
    Nothing ->
      let testTargets = packageTargetsOfKind PackageTest package
       in if null testTargets
            then Left "package has no test targets"
            else Right testTargets
    Just name ->
      case [target | target <- packageTargets package, packageTargetName target == name] of
        [target]
          | packageTargetKind target == PackageTest -> Right [target]
          | otherwise -> Left ("package target is not a test: " ++ name)
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
      , "#include <stdlib.h>"
      , "#include <string.h>"
      , ""
      , "static int silt_host_argc = 0;"
      , "static char **silt_host_argv = 0;"
      , "static char **silt_host_envp = 0;"
      , "typedef struct SiltHostFileReadBuffer {"
      , "  uint8_t *bytes;"
      , "  struct SiltHostFileReadBuffer *next;"
      , "} SiltHostFileReadBuffer;"
      , ""
      , "static SiltHostFileReadBuffer *silt_host_file_read_buffers = 0;"
      , "static uint64_t silt_host_file_read_last_len = 0;"
      , "static uint8_t silt_host_file_read_last_ok = 0u;"
      , "static uint64_t silt_host_stdin_read_last_len = 0;"
      , "static uint8_t silt_host_stdin_read_last_ok = 0u;"
      , ""
      , "uint8_t silt_host_put_byte(uint8_t byte) {"
      , "  return putchar((int)byte) == EOF ? 1u : 0u;"
      , "}"
      , ""
      , "uint8_t silt_host_put_error_byte(uint8_t byte) {"
      , "  return fputc((int)byte, stderr) == EOF ? 1u : 0u;"
      , "}"
      , ""
      , "uint64_t silt_host_arg_count(void) {"
      , "  return silt_host_argc <= 0 ? 0ULL : (uint64_t)silt_host_argc;"
      , "}"
      , ""
      , "uintptr_t silt_host_arg_base(uint64_t index) {"
      , "  if (index >= (uint64_t)silt_host_argc || silt_host_argv[index] == 0) {"
      , "    return (uintptr_t)\"\";"
      , "  }"
      , "  return (uintptr_t)silt_host_argv[index];"
      , "}"
      , ""
      , "uint64_t silt_host_arg_len(uint64_t index) {"
      , "  if (index >= (uint64_t)silt_host_argc || silt_host_argv[index] == 0) {"
      , "    return 0ULL;"
      , "  }"
      , "  return (uint64_t)strlen(silt_host_argv[index]);"
      , "}"
      , ""
      , "static char *silt_host_env_value(uintptr_t name_base, uint64_t name_len) {"
      , "  const char *name = (const char *)name_base;"
      , "  if (silt_host_envp == 0 || name == 0) {"
      , "    return 0;"
      , "  }"
      , "  for (char **env = silt_host_envp; *env != 0; env++) {"
      , "    char *entry = *env;"
      , "    if (strncmp(entry, name, (size_t)name_len) == 0 && entry[name_len] == '=') {"
      , "      return entry + name_len + 1;"
      , "    }"
      , "  }"
      , "  return 0;"
      , "}"
      , ""
      , "uint8_t silt_host_env_present(uintptr_t name_base, uint64_t name_len) {"
      , "  return silt_host_env_value(name_base, name_len) == 0 ? 0u : 1u;"
      , "}"
      , ""
      , "uintptr_t silt_host_env_base(uintptr_t name_base, uint64_t name_len) {"
      , "  char *value = silt_host_env_value(name_base, name_len);"
      , "  return value == 0 ? (uintptr_t)\"\" : (uintptr_t)value;"
      , "}"
      , ""
      , "uint64_t silt_host_env_len(uintptr_t name_base, uint64_t name_len) {"
      , "  char *value = silt_host_env_value(name_base, name_len);"
      , "  return value == 0 ? 0ULL : (uint64_t)strlen(value);"
      , "}"
      , ""
      , "static uint8_t silt_host_size_fits(uint64_t value) {"
      , "  return value <= (uint64_t)((size_t)-1) ? 1u : 0u;"
      , "}"
      , ""
      , "static char *silt_host_copy_path(uintptr_t path_base, uint64_t path_len) {"
      , "  const char *path = (const char *)path_base;"
      , "  if (path == 0 || path_len == 0 || silt_host_size_fits(path_len) == 0 || path_len == (uint64_t)((size_t)-1)) {"
      , "    return 0;"
      , "  }"
      , "  size_t len = (size_t)path_len;"
      , "  char *copy = (char *)malloc(len + 1U);"
      , "  if (copy == 0) {"
      , "    return 0;"
      , "  }"
      , "  memcpy(copy, path, len);"
      , "  copy[len] = '\\0';"
      , "  return copy;"
      , "}"
      , ""
      , "static void silt_host_file_read_cleanup(void) {"
      , "  while (silt_host_file_read_buffers != 0) {"
      , "    SiltHostFileReadBuffer *node = silt_host_file_read_buffers;"
      , "    silt_host_file_read_buffers = node->next;"
      , "    free(node->bytes);"
      , "    free(node);"
      , "  }"
      , "  silt_host_file_read_last_len = 0ULL;"
      , "  silt_host_file_read_last_ok = 0u;"
      , "  silt_host_stdin_read_last_len = 0ULL;"
      , "  silt_host_stdin_read_last_ok = 0u;"
      , "}"
      , ""
      , "uint8_t silt_host_file_write_bytes(uintptr_t path_base, uint64_t path_len, uintptr_t body_base, uint64_t body_len) {"
      , "  if (silt_host_size_fits(body_len) == 0) {"
      , "    return 0u;"
      , "  }"
      , "  char *path = silt_host_copy_path(path_base, path_len);"
      , "  if (path == 0) {"
      , "    return 0u;"
      , "  }"
      , "  FILE *file = fopen(path, \"wb\");"
      , "  free(path);"
      , "  if (file == 0) {"
      , "    return 0u;"
      , "  }"
      , "  const uint8_t *body = (const uint8_t *)body_base;"
      , "  size_t len = (size_t)body_len;"
      , "  if (body == 0 && len != 0U) {"
      , "    (void)fclose(file);"
      , "    return 0u;"
      , "  }"
      , "  size_t written = len == 0U ? 0U : fwrite(body, 1U, len, file);"
      , "  int closed = fclose(file);"
      , "  return written == len && closed == 0 ? 1u : 0u;"
      , "}"
      , ""
      , "uintptr_t silt_host_file_read_base(uintptr_t path_base, uint64_t path_len) {"
      , "  silt_host_file_read_last_len = 0ULL;"
      , "  silt_host_file_read_last_ok = 0u;"
      , "  char *path = silt_host_copy_path(path_base, path_len);"
      , "  if (path == 0) {"
      , "    return (uintptr_t)\"\";"
      , "  }"
      , "  FILE *file = fopen(path, \"rb\");"
      , "  free(path);"
      , "  if (file == 0) {"
      , "    return (uintptr_t)\"\";"
      , "  }"
      , "  if (fseek(file, 0L, SEEK_END) != 0) {"
      , "    (void)fclose(file);"
      , "    return (uintptr_t)\"\";"
      , "  }"
      , "  long size = ftell(file);"
      , "  if (size < 0 || fseek(file, 0L, SEEK_SET) != 0) {"
      , "    (void)fclose(file);"
      , "    return (uintptr_t)\"\";"
      , "  }"
      , "  uint64_t len64 = (uint64_t)size;"
      , "  if (silt_host_size_fits(len64) == 0) {"
      , "    (void)fclose(file);"
      , "    return (uintptr_t)\"\";"
      , "  }"
      , "  size_t len = (size_t)len64;"
      , "  if (len == 0U) {"
      , "    (void)fclose(file);"
      , "    silt_host_file_read_last_ok = 1u;"
      , "    return (uintptr_t)\"\";"
      , "  }"
      , "  uint8_t *buffer = (uint8_t *)malloc(len);"
      , "  if (buffer == 0) {"
      , "    (void)fclose(file);"
      , "    return (uintptr_t)\"\";"
      , "  }"
      , "  size_t read = fread(buffer, 1U, len, file);"
      , "  int closed = fclose(file);"
      , "  if (read != len || closed != 0) {"
      , "    free(buffer);"
      , "    return (uintptr_t)\"\";"
      , "  }"
      , "  SiltHostFileReadBuffer *node = (SiltHostFileReadBuffer *)malloc(sizeof(SiltHostFileReadBuffer));"
      , "  if (node == 0) {"
      , "    free(buffer);"
      , "    return (uintptr_t)\"\";"
      , "  }"
      , "  node->bytes = buffer;"
      , "  node->next = silt_host_file_read_buffers;"
      , "  silt_host_file_read_buffers = node;"
      , "  silt_host_file_read_last_len = len64;"
      , "  silt_host_file_read_last_ok = 1u;"
      , "  return (uintptr_t)buffer;"
      , "}"
      , ""
      , "uintptr_t silt_host_stdin_read_base(void) {"
      , "  silt_host_stdin_read_last_len = 0ULL;"
      , "  silt_host_stdin_read_last_ok = 0u;"
      , "  uint8_t *buffer = 0;"
      , "  size_t len = 0U;"
      , "  size_t capacity = 0U;"
      , "  int ch = 0;"
      , "  while ((ch = fgetc(stdin)) != EOF) {"
      , "    if (len == capacity) {"
      , "      size_t next_capacity = capacity == 0U ? 4096U : capacity * 2U;"
      , "      if (next_capacity <= capacity) {"
      , "        free(buffer);"
      , "        return (uintptr_t)\"\";"
      , "      }"
      , "      uint8_t *next_buffer = (uint8_t *)realloc(buffer, next_capacity);"
      , "      if (next_buffer == 0) {"
      , "        free(buffer);"
      , "        return (uintptr_t)\"\";"
      , "      }"
      , "      buffer = next_buffer;"
      , "      capacity = next_capacity;"
      , "    }"
      , "    buffer[len] = (uint8_t)ch;"
      , "    len++;"
      , "  }"
      , "  if (ferror(stdin)) {"
      , "    free(buffer);"
      , "    return (uintptr_t)\"\";"
      , "  }"
      , "  if (len == 0U) {"
      , "    free(buffer);"
      , "    silt_host_stdin_read_last_ok = 1u;"
      , "    return (uintptr_t)\"\";"
      , "  }"
      , "  SiltHostFileReadBuffer *node = (SiltHostFileReadBuffer *)malloc(sizeof(SiltHostFileReadBuffer));"
      , "  if (node == 0) {"
      , "    free(buffer);"
      , "    return (uintptr_t)\"\";"
      , "  }"
      , "  node->bytes = buffer;"
      , "  node->next = silt_host_file_read_buffers;"
      , "  silt_host_file_read_buffers = node;"
      , "  silt_host_stdin_read_last_len = (uint64_t)len;"
      , "  silt_host_stdin_read_last_ok = 1u;"
      , "  return (uintptr_t)buffer;"
      , "}"
      , ""
      , "uint64_t silt_host_stdin_read_len(void) {"
      , "  return silt_host_stdin_read_last_len;"
      , "}"
      , ""
      , "uint8_t silt_host_stdin_read_ok(void) {"
      , "  return silt_host_stdin_read_last_ok;"
      , "}"
      , ""
      , "uint64_t silt_host_file_read_len(void) {"
      , "  return silt_host_file_read_last_len;"
      , "}"
      , ""
      , "uint8_t silt_host_file_read_ok(void) {"
      , "  return silt_host_file_read_last_ok;"
      , "}"
      , ""
      , cReturnType ret ++ " " ++ cSymbolName entry ++ "(void);"
      , ""
      , "int main(int argc, char **argv, char **envp) {"
      , "  silt_host_argc = argc;"
      , "  silt_host_argv = argv;"
      , "  silt_host_envp = envp;"
      , "  (void)atexit(silt_host_file_read_cleanup);"
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
