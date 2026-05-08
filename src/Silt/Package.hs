module Silt.Package
  ( Package (..)
  , PackageTarget (..)
  , PackageTargetKind (..)
  , defaultBinTarget
  , packageTargetsOfKind
  , parsePackageSource
  , readPackageFile
  ) where

import Data.Foldable (traverse_)
import Data.List (isInfixOf, nub)
import System.FilePath (isAbsolute, splitDirectories, takeExtension)
import Silt.Parse (parseSExprs)
import Silt.Syntax (Name, SExpr (..))

data Package = Package
  { packageName :: Name
  , packageTargets :: [PackageTarget]
  }
  deriving (Eq, Show)

data PackageTarget = PackageTarget
  { packageTargetKind :: PackageTargetKind
  , packageTargetName :: Name
  , packageTargetSources :: [FilePath]
  , packageTargetEntry :: Name
  }
  deriving (Eq, Show)

data PackageTargetKind
  = PackageBin
  | PackageTest
  deriving (Eq, Show)

readPackageFile :: FilePath -> IO (Either String Package)
readPackageFile path = do
  source <- readFile path
  pure (parsePackageSource source)

parsePackageSource :: String -> Either String Package
parsePackageSource source = do
  sexprs <- parseSExprs source
  case sexprs of
    [List (Atom "package" : Atom name : forms)] -> parsePackage name forms
    [List (Atom "package" : _)] -> Left "package form must start with a package name"
    [_] -> Left "Silt.pkg must contain a single (package ...) form"
    [] -> Left "Silt.pkg is empty"
    _ -> Left "Silt.pkg must contain exactly one top-level package form"

defaultBinTarget :: Package -> Either String PackageTarget
defaultBinTarget package =
  case packageTargetsOfKind PackageBin package of
    target : _ -> Right target
    [] -> Left "package has no bin target"

packageTargetsOfKind :: PackageTargetKind -> Package -> [PackageTarget]
packageTargetsOfKind kind package =
  [target | target <- packageTargets package, packageTargetKind target == kind]

parsePackage :: Name -> [SExpr] -> Either String Package
parsePackage name forms = do
  validateName "package name" name
  targets <- traverse parseTarget forms
  ensureUniqueTargets targets
  pure
    Package
      { packageName = name
      , packageTargets = targets
      }

parseTarget :: SExpr -> Either String PackageTarget
parseTarget expr =
  case expr of
    List (Atom kindAtom : Atom name : clauses) -> do
      kind <- parseTargetKind kindAtom
      validateName "target name" name
      (sources, entry) <- parseTargetClauses clauses
      pure
        PackageTarget
          { packageTargetKind = kind
          , packageTargetName = name
          , packageTargetSources = sources
          , packageTargetEntry = entry
          }
    List (Atom kindAtom : _) | kindAtom == "bin" || kindAtom == "test" ->
      Left (kindAtom ++ " target must start with a target name")
    List (Atom kindAtom : _) ->
      Left ("unsupported package form: " ++ kindAtom)
    _ ->
      Left "package target must be a list"

parseTargetKind :: Name -> Either String PackageTargetKind
parseTargetKind kind =
  case kind of
    "bin" -> Right PackageBin
    "test" -> Right PackageTest
    _ -> Left ("unsupported package target kind: " ++ kind)

parseTargetClauses :: [SExpr] -> Either String ([FilePath], Name)
parseTargetClauses clauses = do
  sourcesGroups <- traverse parseSourcesClause [clause | clause@(List (Atom "sources" : _)) <- clauses]
  entries <- traverse parseEntryClause [clause | clause@(List (Atom "entry" : _)) <- clauses]
  traverse_ ensureKnownClause clauses
  sources <-
    case sourcesGroups of
      [paths] -> Right paths
      [] -> Left "target is missing a (sources ...) clause"
      _ -> Left "target has multiple sources clauses"
  entry <-
    case entries of
      [name] -> Right name
      [] -> Left "target is missing an (entry ...) clause"
      _ -> Left "target has multiple entry clauses"
  pure (sources, entry)

parseSourcesClause :: SExpr -> Either String [FilePath]
parseSourcesClause expr =
  case expr of
    List (Atom "sources" : atoms) -> do
      paths <- traverse expectAtom atoms
      if null paths
        then Left "sources clause must list at least one .silt file"
        else traverse validateSourcePath paths
    _ -> Left "internal error: expected sources clause"

parseEntryClause :: SExpr -> Either String Name
parseEntryClause expr =
  case expr of
    List [Atom "entry", Atom name] -> do
      validateName "entry name" name
      pure name
    List (Atom "entry" : _) -> Left "entry clause must be (entry NAME)"
    _ -> Left "internal error: expected entry clause"

ensureKnownClause :: SExpr -> Either String ()
ensureKnownClause expr =
  case expr of
    List (Atom "sources" : _) -> Right ()
    List (Atom "entry" : _) -> Right ()
    List (Atom name : _) -> Left ("unsupported target clause: " ++ name)
    _ -> Left "target clauses must be lists"

expectAtom :: SExpr -> Either String String
expectAtom expr =
  case expr of
    Atom atom -> Right atom
    List _ -> Left "expected atom"

validateSourcePath :: FilePath -> Either String FilePath
validateSourcePath path
  | isAbsolute path = Left "source path must be relative"
  | ".." `elem` splitDirectories path = Left "source path cannot contain '..'"
  | takeExtension path /= ".silt" = Left "source path must end in .silt"
  | otherwise = Right path

validateName :: String -> Name -> Either String ()
validateName label name
  | null name = Left (label ++ " cannot be empty")
  | "/" `isInfixOf` name = Left (label ++ " cannot contain '/'")
  | "\\" `isInfixOf` name = Left (label ++ " cannot contain '\\'")
  | otherwise = Right ()

ensureUniqueTargets :: [PackageTarget] -> Either String ()
ensureUniqueTargets targets =
  let names = map packageTargetName targets
   in if length names == length (nub names)
        then Right ()
        else Left "package target names must be unique"
