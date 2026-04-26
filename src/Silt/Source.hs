module Silt.Source
  ( readProgramBundle
  , readProgramFile
  ) where

import Control.Exception (IOException, try)
import Control.Monad (foldM, unless, when)
import Data.List (intercalate)
import Silt.Parse (parseProgramFromSExprs, parseSExprs)
import Silt.Syntax (Program, SExpr (..))
import System.FilePath
  ( isRelative
  , normalise
  , splitDirectories
  , takeDirectory
  , takeExtension
  , (</>)
  )

readProgramBundle :: [FilePath] -> IO (Either String Program)
readProgramBundle paths = do
  sexprsResult <- foldM appendSourceFile (Right []) paths
  pure (sexprsResult >>= parseProgramFromSExprs)
  where
    appendSourceFile (Left err) _ =
      pure (Left err)
    appendSourceFile (Right sexprs) path = do
      fileSexprs <- readSExprFile [] path
      pure ((sexprs ++) <$> fileSexprs)

readProgramFile :: FilePath -> IO (Either String Program)
readProgramFile path =
  readProgramBundle [path]

readSExprFile :: [FilePath] -> FilePath -> IO (Either String [SExpr])
readSExprFile stack path = do
  let normalizedPath = normalise path
  if normalizedPath `elem` stack
    then pure (Left ("include cycle: " ++ renderCycle normalizedPath stack))
    else do
      inputResult <- try (readFile normalizedPath) :: IO (Either IOException String)
      case inputResult of
        Left err ->
          pure (Left (normalizedPath ++ ": " ++ show err))
        Right input ->
          case parseSExprs input of
            Left err -> pure (Left (prefixError normalizedPath err))
            Right sexprs ->
              foldM
                (expandInto (normalizedPath : stack) normalizedPath)
                (Right [])
                sexprs

expandInto :: [FilePath] -> FilePath -> Either String [SExpr] -> SExpr -> IO (Either String [SExpr])
expandInto _ _ (Left err) _ =
  pure (Left err)
expandInto stack source (Right expanded) sexpr = do
  current <- expandSExpr stack source sexpr
  pure ((expanded ++) <$> current)

expandSExpr :: [FilePath] -> FilePath -> SExpr -> IO (Either String [SExpr])
expandSExpr stack source sexpr =
  case sexpr of
    List [Atom "include", Atom includePath] ->
      case resolveInclude source includePath of
        Left err -> pure (Left err)
        Right path -> readSExprFile stack path
    List (Atom "include" : _) ->
      pure (Left (prefixError source "expected top-level include form (include relative-file.silt)"))
    _ ->
      pure (Right [sexpr])

resolveInclude :: FilePath -> FilePath -> Either String FilePath
resolveInclude source includePath = do
  when (null includePath) $
    Left (prefixError source "include path cannot be empty")
  unless (isRelative includePath) $
    Left (prefixError source ("include path must be relative: " ++ includePath))
  when (".." `elem` splitDirectories includePath) $
    Left (prefixError source ("include path cannot contain '..': " ++ includePath))
  unless (takeExtension includePath == ".silt") $
    Left (prefixError source ("include path must end in .silt: " ++ includePath))
  pure (normalise (takeDirectory source </> includePath))

prefixError :: FilePath -> String -> String
prefixError path err =
  path ++ ": " ++ err

renderCycle :: FilePath -> [FilePath] -> String
renderCycle path stack =
  intercalate " -> " (reverse stack ++ [path])
