module Silt.Elab
  ( CheckedDecl (..)
  , CheckedConstructor (..)
  , CheckedLayoutField (..)
  , checkProgram
  , normalizeDefinition
  , normalizeDefinitionTerm
  , renderCheckedDecl
  ) where

import Control.Monad (unless, when)
import Data.Bits ((.&.), (.|.), shiftL, shiftR, xor)
import Data.List (nub, tails)
import Data.Word (Word64)
import qualified Data.Map.Strict as Map
import Silt.Syntax

data CheckedDecl
  = CheckedClaim Name Term
  | CheckedDef Name Term Term
  | CheckedExtern Name Term Name
  | CheckedExport Name Name
  | CheckedSection Name Name
  | CheckedCallingConvention Name Name
  | CheckedEntry Name
  | CheckedAbiContract Name [AbiContractClause]
  | CheckedTargetContract Name [TargetContractClause]
  | CheckedBootContract Name [BootContractClause]
  | CheckedLayout Name Word64 Word64 [CheckedLayoutField]
  | CheckedStaticBytes Name [Word64]
  | CheckedStaticCell Name Term
  | CheckedStaticValue Name Term Name Term
  | CheckedData Name Term [CheckedConstructor]
  deriving (Eq, Show)

data CheckedConstructor = CheckedConstructor Name Term
  deriving (Eq, Show)

data CheckedLayoutField = CheckedLayoutField Name Term Word64
  deriving (Eq, Show)

data GlobalEntry = GlobalEntry
  { globalTypeTerm :: Term
  , globalTypeValue :: Value
  , globalDefinition :: Maybe Term
  , globalValue :: Maybe Value
  , globalExternSymbol :: Maybe Name
  , globalExportSymbol :: Maybe Name
  , globalSectionName :: Maybe Name
  , globalCallingConvention :: Maybe Name
  , globalEntryPoint :: Bool
  }

newtype DataInfo = DataInfo
  { dataConstructors :: [Name]
  }

data ConstructorInfo = ConstructorInfo
  { constructorName :: Name
  , constructorDataName :: Name
  , constructorParamCount :: Int
  , constructorFieldTypes :: [Term]
  }

data LayoutInfo = LayoutInfo
  { layoutSize :: Word64
  , layoutAlign :: Word64
  , layoutFieldOrder :: [Name]
  , layoutFields :: Map.Map Name LayoutFieldInfo
  }

data LayoutFieldInfo = LayoutFieldInfo
  { layoutFieldTypeTerm :: Term
  , layoutFieldOffset :: Word64
  , layoutFieldSize :: Word64
  , layoutFieldAlign :: Word64
  }

data Globals = Globals
  { globalsEntries :: Map.Map Name GlobalEntry
  , globalsDataInfos :: Map.Map Name DataInfo
  , globalsConstructorInfos :: Map.Map Name ConstructorInfo
  , globalsLayoutInfos :: Map.Map Name LayoutInfo
  , globalsTargetContracts :: Map.Map Name [TargetContractClause]
  , globalsBootContracts :: Map.Map Name [BootContractClause]
  }

data CtxEntry = CtxEntry
  { ctxName :: Name
  , ctxType :: Value
  }

type Context = [CtxEntry]
type Env = [Value]

data Value
  = VUniverse Int
  | VPi Name Quantity Value Closure
  | VLam Name Quantity Closure
  | VNeutral Neutral
  | VU8 Word64
  | VU64 Word64
  | VAddr Word64
  | VStaticBytesPtr Name
  | VStaticCellPtr Name
  | VStaticValuePtr Name
  | VLayout Name [LayoutFieldInit Value]
  | VPrim Name [Value]

data Closure = Closure Globals Env Term

data MatchClosure = MatchClosure Name [PatternBinder] Closure

data Neutral
  = NLocal Int
  | NGlobal Name
  | NApp Neutral Value
  | NLayoutField Name Name Neutral
  | NLayoutUpdate Name Name Neutral Value
  | NMatch Neutral [MatchClosure]

checkProgram :: Program -> Either String [CheckedDecl]
checkProgram program =
  snd <$> checkProgramState program

checkProgramState :: Program -> Either String (Globals, [CheckedDecl])
checkProgramState (Program decls) =
  foldl step (Right (builtinsGlobals, [])) decls
  where
    step :: Either String (Globals, [CheckedDecl]) -> Decl -> Either String (Globals, [CheckedDecl])
    step result decl = do
      (globals, checked) <- result
      (globals', checkedDecl) <- processDecl globals decl
      pure (globals', checked ++ [checkedDecl])

normalizeDefinition :: Program -> Name -> Either String String
normalizeDefinition program name = do
  (_, nf) <- normalizeDefinitionTerm program name
  pure (prettyTerm nf)

normalizeDefinitionTerm :: Program -> Name -> Either String (Term, Term)
normalizeDefinitionTerm program name = do
  (globals, _) <- checkProgramState program
  entry <- lookupGlobal globals name
  case globalValue entry of
    Nothing -> Left ("global " ++ name ++ " does not have a definition")
    Just value -> Right (globalTypeTerm entry, quote 0 value)

processDecl :: Globals -> Decl -> Either String (Globals, CheckedDecl)
processDecl globals decl =
  case decl of
    Claim name tySurface -> do
      ensureFresh globals name
      (tyTerm, tyTy) <- infer globals [] [] tySurface
      _ <- expectUniverse 0 tyTy
      let tyValue = eval globals [] tyTerm
      let entry =
            GlobalEntry
              { globalTypeTerm = tyTerm
              , globalTypeValue = tyValue
              , globalDefinition = Nothing
              , globalValue = Nothing
              , globalExternSymbol = Nothing
              , globalExportSymbol = Nothing
              , globalSectionName = Nothing
              , globalCallingConvention = Nothing
              , globalEntryPoint = False
              }
      pure (insertGlobal name entry globals, CheckedClaim name tyTerm)
    Extern name tySurface maybeSymbol -> do
      ensureFresh globals name
      (tyTerm, tyTy) <- infer globals [] [] tySurface
      _ <- expectUniverse 0 tyTy
      let tyValue = eval globals [] tyTerm
      let symbol = maybe name id maybeSymbol
      validateCSymbolName ("extern symbol for " ++ name) symbol
      let entry =
            GlobalEntry
              { globalTypeTerm = tyTerm
              , globalTypeValue = tyValue
              , globalDefinition = Nothing
              , globalValue = Nothing
              , globalExternSymbol = Just symbol
              , globalExportSymbol = Nothing
              , globalSectionName = Nothing
              , globalCallingConvention = Nothing
              , globalEntryPoint = False
              }
      pure (insertGlobal name entry globals, CheckedExtern name tyTerm symbol)
    Export name symbol -> do
      validateCSymbolName ("export symbol for " ++ name) symbol
      entry <- lookupGlobal globals name
      case globalDefinition entry of
        Nothing ->
          Left ("export target " ++ name ++ " must be a checked definition")
        Just _ ->
          case globalExportSymbol entry of
            Just existing ->
              Left ("duplicate export for " ++ name ++ " as " ++ existing)
            Nothing -> do
              case [owner | (owner, candidate) <- Map.toList (globalsEntries globals), globalExportSymbol candidate == Just symbol] of
                owner : _ ->
                  Left ("export symbol " ++ symbol ++ " is already used by " ++ owner)
                [] -> pure ()
              let updated = entry {globalExportSymbol = Just symbol}
              pure (insertGlobal name updated globals, CheckedExport name symbol)
    Section name sectionName -> do
      validateCSectionName ("section for " ++ name) sectionName
      entry <- lookupGlobal globals name
      case globalDefinition entry of
        Nothing ->
          Left ("section target " ++ name ++ " must be a checked definition")
        Just _ ->
          case globalSectionName entry of
            Just existing ->
              Left ("duplicate section for " ++ name ++ " as " ++ existing)
            Nothing -> do
              let updated = entry {globalSectionName = Just sectionName}
              pure (insertGlobal name updated globals, CheckedSection name sectionName)
    CallingConvention name conventionName -> do
      validateCallingConventionName ("calling convention for " ++ name) conventionName
      entry <- lookupGlobal globals name
      unless (globalExternSymbol entry /= Nothing || globalDefinition entry /= Nothing) $
        Left ("calling-convention target " ++ name ++ " must be an extern or checked definition")
      case globalCallingConvention entry of
        Just existing ->
          Left ("duplicate calling-convention for " ++ name ++ " as " ++ existing)
        Nothing -> do
          let updated = entry {globalCallingConvention = Just conventionName}
          pure (insertGlobal name updated globals, CheckedCallingConvention name conventionName)
    Entry name -> do
      entry <- lookupGlobal globals name
      case globalDefinition entry of
        Nothing ->
          Left ("entry target " ++ name ++ " must be a checked definition")
        Just _ -> do
          validateCEmittableSignature globals ("entry " ++ name) (globalTypeTerm entry)
          when (globalEntryPoint entry) $
            Left ("duplicate entry for " ++ name)
          case [owner | (owner, candidate) <- Map.toList (globalsEntries globals), globalEntryPoint candidate] of
            owner : _ ->
              Left ("entry point is already declared as " ++ owner)
            [] -> pure ()
          let updated = entry {globalEntryPoint = True}
          pure (insertGlobal name updated globals, CheckedEntry name)
    AbiContract name clauses -> do
      entry <- lookupGlobal globals name
      validateAbiContractClauses globals name entry clauses
      pure (globals, CheckedAbiContract name clauses)
    TargetContract target clauses -> do
      when (Map.member target (globalsTargetContracts globals)) $
        Left ("duplicate target-contract for " ++ target)
      validateTargetContractClauses globals target clauses
      pure
        ( globals {globalsTargetContracts = Map.insert target clauses (globalsTargetContracts globals)}
        , CheckedTargetContract target clauses
        )
    BootContract name clauses -> do
      when (Map.member name (globalsBootContracts globals)) $
        Left ("duplicate boot-contract for " ++ name)
      validateBootContractClauses globals name clauses
      pure
        ( globals {globalsBootContracts = Map.insert name clauses (globalsBootContracts globals)}
        , CheckedBootContract name clauses
        )
    LayoutDecl name size align fields ->
      processLayoutDecl globals name size align fields
    StaticBytes name values ->
      processStaticBytesDecl globals name values
    StaticCell name tySurface ->
      processStaticCellDecl globals name tySurface
    StaticValue name tySurface sectionName valueSurface ->
      processStaticValueDecl globals name tySurface sectionName valueSurface
    Define name exprSurface -> do
      entry <- lookupGlobal globals name
      unless (globalDefinition entry == Nothing && globalExternSymbol entry == Nothing) $
        Left ("duplicate definition for " ++ name)
      exprTerm <- check globals [] [] exprSurface (globalTypeValue entry)
      let exprValue = eval globals [] exprTerm
      let updated =
            entry
              { globalDefinition = Just exprTerm
              , globalValue = Just exprValue
              , globalExternSymbol = Nothing
              }
      pure
        ( insertGlobal name updated globals
        , CheckedDef name (globalTypeTerm entry) exprTerm
        )
    DataDecl name params ctors ->
      processDataDecl globals name params ctors

processDataDecl :: Globals -> Name -> [Binder Surface] -> [ConstructorDecl] -> Either String (Globals, CheckedDecl)
processDataDecl globals name params ctors = do
  ensureFresh globals name
  ensureDistinct ("duplicate constructor in data " ++ name) [ctorName | ConstructorDecl ctorName _ <- ctors]
  (paramCtx, paramEnv, paramTerms, _) <- inferBinders globals [] [] params
  let dataTypeTerm = foldr piFromBinder (TUniverse 0) paramTerms
  let dataEntry =
        GlobalEntry
          { globalTypeTerm = dataTypeTerm
          , globalTypeValue = eval globals [] dataTypeTerm
          , globalDefinition = Nothing
          , globalValue = Nothing
          , globalExternSymbol = Nothing
          , globalExportSymbol = Nothing
          , globalSectionName = Nothing
          , globalCallingConvention = Nothing
          , globalEntryPoint = False
          }
  let globalsWithData =
        insertDataInfo
          name
          (DataInfo (map ctorDeclName ctors))
          (insertGlobal name dataEntry globals)
  mapM_ (ensureFresh globalsWithData . ctorDeclName) ctors
  constructorBundle <- traverse (buildConstructor globalsWithData name paramCtx paramEnv paramTerms) ctors
  let globals' =
        foldl
          (\acc (_, (ctorName, ctorEntry), ctorInfo) ->
              insertConstructorInfo ctorName ctorInfo (insertGlobal ctorName ctorEntry acc))
          globalsWithData
          constructorBundle
  pure
    ( globals'
    , CheckedData name dataTypeTerm [checkedCtor | (checkedCtor, _, _) <- constructorBundle]
    )

processLayoutDecl ::
     Globals
  -> Name
  -> Word64
  -> Word64
  -> [LayoutFieldDecl]
  -> Either String (Globals, CheckedDecl)
processLayoutDecl globals name size align fields = do
  ensureFresh globals name
  unless (size > 0) $
    Left ("layout " ++ name ++ " must have positive size")
  unless (align > 0) $
    Left ("layout " ++ name ++ " must have positive alignment")
  unless (isPowerOfTwo align) $
    Left ("layout " ++ name ++ " alignment must be a power of two")
  unless (size `mod` align == 0) $
    Left ("layout " ++ name ++ " size must be a multiple of its alignment")
  checkedFields <- checkLayoutFields globals name size align fields
  let fieldTable =
        Map.fromList
          [ (fieldName, layoutFieldInfoFromChecked fieldName fieldTy fieldOffset)
          | CheckedLayoutField fieldName fieldTy fieldOffset <- checkedFields
          ]
  let entry =
        GlobalEntry
          { globalTypeTerm = TUniverse 0
          , globalTypeValue = VUniverse 0
          , globalDefinition = Nothing
          , globalValue = Nothing
          , globalExternSymbol = Nothing
          , globalExportSymbol = Nothing
          , globalSectionName = Nothing
          , globalCallingConvention = Nothing
          , globalEntryPoint = False
          }
  let globals' =
        insertLayoutInfo
          name
          (LayoutInfo size align [fieldName | CheckedLayoutField fieldName _ _ <- checkedFields] fieldTable)
          (insertGlobal name entry globals)
  pure (globals', CheckedLayout name size align checkedFields)
  where
    layoutFieldInfoFromChecked fieldName fieldTy fieldOffset =
      case runtimeTypeLayoutTerm globals fieldTy of
        Just (fieldSize, fieldAlign) ->
          LayoutFieldInfo
            { layoutFieldTypeTerm = fieldTy
            , layoutFieldOffset = fieldOffset
            , layoutFieldSize = fieldSize
            , layoutFieldAlign = fieldAlign
            }
        Nothing ->
          error ("internal error: checked layout field lost runtime representation for " ++ name ++ "." ++ fieldName)

processStaticBytesDecl :: Globals -> Name -> [Word64] -> Either String (Globals, CheckedDecl)
processStaticBytesDecl globals name values = do
  ensureFresh globals name
  ensureFresh globals lenName
  unless (not (null values)) $
    Left ("static-bytes " ++ name ++ " must contain at least one byte")
  let ptrTy = TApp (TGlobal "Ptr") (TGlobal "U8")
  let ptrEntry =
        GlobalEntry
          { globalTypeTerm = ptrTy
          , globalTypeValue = eval globals [] ptrTy
          , globalDefinition = Just (TStaticBytesPtr name)
          , globalValue = Just (VStaticBytesPtr name)
          , globalExternSymbol = Nothing
          , globalExportSymbol = Nothing
          , globalSectionName = Nothing
          , globalCallingConvention = Nothing
          , globalEntryPoint = False
          }
  let lenTerm = TU64 (fromIntegral (length values))
  let lenEntry =
        GlobalEntry
          { globalTypeTerm = TGlobal "U64"
          , globalTypeValue = u64TypeValue
          , globalDefinition = Just lenTerm
          , globalValue = Just (VU64 (fromIntegral (length values)))
          , globalExternSymbol = Nothing
          , globalExportSymbol = Nothing
          , globalSectionName = Nothing
          , globalCallingConvention = Nothing
          , globalEntryPoint = False
          }
  pure
    ( insertGlobal lenName lenEntry (insertGlobal name ptrEntry globals)
    , CheckedStaticBytes name values
    )
  where
    lenName = staticBytesLengthName name

processStaticCellDecl :: Globals -> Name -> Surface -> Either String (Globals, CheckedDecl)
processStaticCellDecl globals name tySurface = do
  ensureFresh globals name
  (tyTerm, tyTy) <- infer globals [] [] tySurface
  _ <- expectUniverse 0 tyTy
  let tyValue = eval globals [] tyTerm
  case runtimeTypeLayoutValue globals tyValue of
    Nothing ->
      Left ("static-cell " ++ name ++ " type must have a runtime-backed representation")
    Just _ -> Right ()
  let ptrTy = TApp (TGlobal "Ptr") tyTerm
  let ptrEntry =
        GlobalEntry
          { globalTypeTerm = ptrTy
          , globalTypeValue = eval globals [] ptrTy
          , globalDefinition = Just (TStaticCellPtr name)
          , globalValue = Just (VStaticCellPtr name)
          , globalExternSymbol = Nothing
          , globalExportSymbol = Nothing
          , globalSectionName = Nothing
          , globalCallingConvention = Nothing
          , globalEntryPoint = False
          }
  pure
    ( insertGlobal name ptrEntry globals
    , CheckedStaticCell name tyTerm
    )

processStaticValueDecl :: Globals -> Name -> Surface -> Name -> Surface -> Either String (Globals, CheckedDecl)
processStaticValueDecl globals name tySurface sectionName valueSurface = do
  ensureFresh globals name
  validateCSectionName ("static-value section for " ++ name) sectionName
  (tyTerm, tyTy) <- infer globals [] [] tySurface
  _ <- expectUniverse 0 tyTy
  let tyValue = eval globals [] tyTerm
  case runtimeTypeLayoutValue globals tyValue of
    Nothing ->
      Left ("static-value " ++ name ++ " type must have a runtime-backed representation")
    Just _ -> Right ()
  valueTerm <- check globals [] [] valueSurface tyValue
  let valueNF = quote 0 (eval globals [] valueTerm)
  validateStaticValueTerm globals name tyTerm valueNF
  let ptrTy = TApp (TGlobal "Ptr") tyTerm
  let ptrEntry =
        GlobalEntry
          { globalTypeTerm = ptrTy
          , globalTypeValue = eval globals [] ptrTy
          , globalDefinition = Just (TStaticValuePtr name)
          , globalValue = Just (VStaticValuePtr name)
          , globalExternSymbol = Nothing
          , globalExportSymbol = Nothing
          , globalSectionName = Nothing
          , globalCallingConvention = Nothing
          , globalEntryPoint = False
          }
  pure
    ( insertGlobal name ptrEntry globals
    , CheckedStaticValue name tyTerm sectionName valueNF
    )

validateStaticValueTerm :: Globals -> Name -> Term -> Term -> Either String ()
validateStaticValueTerm globals name ty value =
  case ty of
    TGlobal "Unit" ->
      requireStaticValue (value == TGlobal "tt")
    TGlobal "Bool" ->
      requireStaticValue (value == TGlobal "True" || value == TGlobal "False")
    TGlobal "U8" ->
      requireStaticValue $
        case value of
          TU8 _ -> True
          _ -> False
    TGlobal "U64" ->
      requireStaticValue $
        case value of
          TU64 _ -> True
          _ -> False
    TGlobal "Addr" ->
      requireStaticValue $
        case value of
          TAddr _ -> True
          _ -> False
    TApp (TGlobal "Ptr") _ ->
      requireStaticValue (isStaticPtrValue value)
    TGlobal layoutName
      | Just layoutInfo <- lookupLayoutInfoMaybe globals layoutName ->
          case value of
            TLayout valueLayout fields
              | valueLayout == layoutName && map (\(LayoutFieldInit fieldName _) -> fieldName) fields == layoutFieldOrder layoutInfo ->
                  mapM_ (validateLayoutField layoutName layoutInfo) fields
              | otherwise -> unsupported
            _ -> unsupported
      | otherwise -> unsupported
    _ -> unsupported
  where
    requireStaticValue ok =
      if ok then Right () else unsupported
    validateLayoutField layoutName layoutInfo (LayoutFieldInit fieldName fieldValue) =
      case Map.lookup fieldName (layoutFields layoutInfo) of
        Nothing -> Left ("internal error: static-value " ++ name ++ " field metadata missing for " ++ layoutName ++ "." ++ fieldName)
        Just fieldInfo -> validateStaticValueTerm globals name (layoutFieldTypeTerm fieldInfo) fieldValue
    unsupported =
      Left ("static-value " ++ name ++ " initializer must be a compile-time static value for " ++ prettyTerm ty)

isStaticPtrValue :: Term -> Bool
isStaticPtrValue value =
  case unfoldApps value of
    (TGlobal "ptr-from-addr", [_ty, TAddr _]) -> True
    _ -> False

buildConstructor ::
     Globals
  -> Name
  -> Context
  -> Env
  -> [Binder Term]
  -> ConstructorDecl
  -> Either String (CheckedConstructor, (Name, GlobalEntry), ConstructorInfo)
buildConstructor globals dataName paramCtx paramEnv paramTerms (ConstructorDecl ctorName fields) = do
  fieldTerms <- traverse (inferFieldType globals paramCtx paramEnv) fields
  let paramCount = length paramTerms
  let fieldCount = length fieldTerms
  let resultTerm = dataResultTerm dataName paramCount fieldCount
  let fieldBinders =
        [ Binder ("arg" ++ show index) QOmega (shift 0 index fieldTy)
        | (index, fieldTy) <- zip [0 ..] fieldTerms
        ]
  let ctorTypeTerm = foldr piFromBinder resultTerm (paramTerms ++ fieldBinders)
  let ctorEntry =
        GlobalEntry
          { globalTypeTerm = ctorTypeTerm
          , globalTypeValue = eval globals [] ctorTypeTerm
          , globalDefinition = Nothing
          , globalValue = Nothing
          , globalExternSymbol = Nothing
          , globalExportSymbol = Nothing
          , globalSectionName = Nothing
          , globalCallingConvention = Nothing
          , globalEntryPoint = False
          }
  let ctorInfo =
        ConstructorInfo
          { constructorName = ctorName
          , constructorDataName = dataName
          , constructorParamCount = paramCount
          , constructorFieldTypes = fieldTerms
          }
  pure (CheckedConstructor ctorName ctorTypeTerm, (ctorName, ctorEntry), ctorInfo)

inferFieldType :: Globals -> Context -> Env -> Surface -> Either String Term
inferFieldType globals ctx env fieldSurface = do
  (fieldTerm, fieldTy) <- infer globals ctx env fieldSurface
  _ <- expectUniverse (length env) fieldTy
  pure fieldTerm

checkLayoutFields ::
     Globals
  -> Name
  -> Word64
  -> Word64
  -> [LayoutFieldDecl]
  -> Either String [CheckedLayoutField]
checkLayoutFields globals layoutName layoutSize layoutAlign fields = do
  ensureDistinct ("duplicate field in layout " ++ layoutName) [fieldName | LayoutFieldDecl fieldName _ _ <- fields]
  checkedFields <- traverse checkField fields
  ensureNonOverlappingLayoutFields globals layoutName checkedFields
  pure checkedFields
  where
    checkField (LayoutFieldDecl fieldName fieldTySurface fieldOffset) = do
      (fieldTyTerm, fieldTyTy) <- infer globals [] [] fieldTySurface
      _ <- expectUniverse 0 fieldTyTy
      let fieldTyValue = eval globals [] fieldTyTerm
      (fieldSize, fieldAlign) <-
        case runtimeTypeLayoutValue globals fieldTyValue of
          Nothing ->
            Left
              ( "layout field "
                  ++ layoutName
                  ++ "."
                  ++ fieldName
                  ++ " does not have a runtime-backed representation"
              )
          Just info -> Right info
      unless (fieldOffset `mod` fieldAlign == 0) $
        Left
          ( "layout field "
              ++ layoutName
              ++ "."
              ++ fieldName
              ++ " is not aligned to "
              ++ show fieldAlign
          )
      unless (layoutAlign >= fieldAlign && layoutAlign `mod` fieldAlign == 0) $
        Left
          ( "layout "
              ++ layoutName
              ++ " alignment "
              ++ show layoutAlign
              ++ " is weaker than field "
              ++ fieldName
              ++ " alignment "
              ++ show fieldAlign
          )
      unless (fieldOffset <= layoutSize && fieldSize <= layoutSize - fieldOffset) $
        Left
          ( "layout field "
              ++ layoutName
              ++ "."
              ++ fieldName
              ++ " exceeds layout size "
              ++ show layoutSize
          )
      pure (CheckedLayoutField fieldName fieldTyTerm fieldOffset)

ensureNonOverlappingLayoutFields :: Globals -> Name -> [CheckedLayoutField] -> Either String ()
ensureNonOverlappingLayoutFields globals layoutName fields =
  mapM_ rejectOverlap [(left, right) | (left : rest) <- tails fields, right <- rest]
  where
    rejectOverlap (left, right) = do
      (leftName, leftStart, leftEnd) <- fieldRange left
      (rightName, rightStart, rightEnd) <- fieldRange right
      when (leftStart < rightEnd && rightStart < leftEnd) $
        Left
          ( "layout fields "
              ++ layoutName
              ++ "."
              ++ leftName
              ++ " and "
              ++ layoutName
              ++ "."
              ++ rightName
              ++ " overlap"
          )
    fieldRange (CheckedLayoutField fieldName fieldTy fieldOffset) =
      case runtimeTypeLayoutTerm globals fieldTy of
        Just (fieldSize, _) -> Right (fieldName, fieldOffset, fieldOffset + fieldSize)
        Nothing ->
          Left ("layout field " ++ layoutName ++ "." ++ fieldName ++ " does not have a runtime-backed representation")

ensureDistinct :: String -> [Name] -> Either String ()
ensureDistinct err names =
  if length names == length (nub names)
    then Right ()
    else Left err

isPowerOfTwo :: Word64 -> Bool
isPowerOfTwo value =
  value > 0 && (value .&. (value - 1)) == 0

validateCSymbolName :: String -> Name -> Either String ()
validateCSymbolName label symbol =
  case symbol of
    [] -> Left (label ++ " must be a non-empty C identifier")
    first : rest
      | isCSymbolStart first && all isCSymbolRest rest -> Right ()
      | otherwise -> Left (label ++ " must be a C identifier")

isCSymbolStart :: Char -> Bool
isCSymbolStart char =
  char == '_' || ('A' <= char && char <= 'Z') || ('a' <= char && char <= 'z')

isCSymbolRest :: Char -> Bool
isCSymbolRest char =
  isCSymbolStart char || ('0' <= char && char <= '9')

validateCSectionName :: String -> Name -> Either String ()
validateCSectionName label sectionName =
  case sectionName of
    [] ->
      Left (label ++ " must be a non-empty C section name")
    _ | all isCSectionChar sectionName ->
          Right ()
      | otherwise ->
          Left (label ++ " must be a C section name without quotes or escapes")

isCSectionChar :: Char -> Bool
isCSectionChar char =
  char /= '"' && char /= '\\' && char /= ';' && char /= '(' && char /= ')'

validateCallingConventionName :: String -> Name -> Either String ()
validateCallingConventionName label conventionName =
  case conventionName of
    "c" -> Right ()
    "sysv-abi" -> Right ()
    "ms-abi" -> Right ()
    _ -> Left (label ++ " must be one of c, sysv-abi, or ms-abi")

validateAbiContractClauses :: Globals -> Name -> GlobalEntry -> [AbiContractClause] -> Either String ()
validateAbiContractClauses globals name entry clauses = do
  ensureDistinct ("duplicate abi-contract clause for " ++ name) (map abiContractClauseKey clauses)
  mapM_ validateClause clauses
  where
    validateClause clause =
      case clause of
        AbiContractEntry ->
          unless (globalEntryPoint entry) $
            Left ("abi-contract " ++ name ++ " requires entry metadata")
        AbiContractSymbol symbol -> do
          validateCSymbolName ("abi-contract symbol for " ++ name) symbol
          unless (globalExportSymbol entry == Just symbol || globalExternSymbol entry == Just symbol) $
            Left ("abi-contract " ++ name ++ " expected emitted symbol " ++ symbol)
        AbiContractSection sectionName -> do
          validateCSectionName ("abi-contract section for " ++ name) sectionName
          unless (globalSectionName entry == Just sectionName) $
            Left ("abi-contract " ++ name ++ " expected section " ++ sectionName)
        AbiContractCallingConvention conventionName -> do
          validateCallingConventionName ("abi-contract calling convention for " ++ name) conventionName
          unless (globalCallingConvention entry == Just conventionName) $
            Left ("abi-contract " ++ name ++ " expected calling convention " ++ conventionName)
        AbiContractFreestanding -> do
          unless (globalDefinition entry /= Nothing || globalExternSymbol entry /= Nothing) $
            Left ("abi-contract " ++ name ++ " freestanding target must be an extern or checked definition")
          validateCEmittableSignature globals ("abi-contract " ++ name) (globalTypeTerm entry)

abiContractClauseKey :: AbiContractClause -> Name
abiContractClauseKey clause =
  case clause of
    AbiContractEntry -> "entry"
    AbiContractSymbol _ -> "symbol"
    AbiContractSection _ -> "section"
    AbiContractCallingConvention _ -> "calling-convention"
    AbiContractFreestanding -> "freestanding"

data TargetContractSpec = TargetContractSpec
  { targetSpecFormat :: Name
  , targetSpecArch :: Name
  , targetSpecAbi :: Name
  , targetSpecCallingConvention :: Name
  , targetSpecRedZone :: Name
  , targetSpecMinimumEntryAddress :: Word64
  }

limineHigherHalfBase :: Word64
limineHigherHalfBase = 0xffffffff80000000

lookupTargetContractSpec :: Name -> Either String TargetContractSpec
lookupTargetContractSpec target =
  case target of
    "x86_64-sysv-elf" ->
      Right
        TargetContractSpec
          { targetSpecFormat = "elf64"
          , targetSpecArch = "x86_64"
          , targetSpecAbi = "sysv"
          , targetSpecCallingConvention = "sysv-abi"
          , targetSpecRedZone = "disabled"
          , targetSpecMinimumEntryAddress = 1
          }
    "x86_64-limine-elf" ->
      Right
        TargetContractSpec
          { targetSpecFormat = "elf64"
          , targetSpecArch = "x86_64"
          , targetSpecAbi = "sysv"
          , targetSpecCallingConvention = "sysv-abi"
          , targetSpecRedZone = "disabled"
          , targetSpecMinimumEntryAddress = limineHigherHalfBase
          }
    _ ->
      Left ("unsupported target-contract target " ++ target)

validateTargetContractClauses :: Globals -> Name -> [TargetContractClause] -> Either String ()
validateTargetContractClauses globals target clauses = do
  spec <- lookupTargetContractSpec target
  ensureDistinct ("duplicate target-contract clause for " ++ target) (map targetContractClauseKey clauses)
  formatName <- requireTargetClause target "format" (targetContractFormat clauses)
  archName <- requireTargetClause target "arch" (targetContractArch clauses)
  abiName <- requireTargetClause target "abi" (targetContractAbi clauses)
  entryName <- requireTargetClause target "entry" (targetContractEntry clauses)
  symbol <- requireTargetClause target "symbol" (targetContractSymbol clauses)
  sectionName <- requireTargetClause target "section" (targetContractSection clauses)
  conventionName <- requireTargetClause target "calling-convention" (targetContractCallingConvention clauses)
  entryAddress <- requireTargetClause target "entry-address" (targetContractEntryAddress clauses)
  redZoneMode <- requireTargetClause target "red-zone" (targetContractRedZone clauses)
  unless (TargetContractFreestanding `elem` clauses) $
    Left ("target-contract " ++ target ++ " missing freestanding clause")
  unless (formatName == targetSpecFormat spec) $
    Left ("target-contract " ++ target ++ " format must be " ++ targetSpecFormat spec)
  unless (archName == targetSpecArch spec) $
    Left ("target-contract " ++ target ++ " arch must be " ++ targetSpecArch spec)
  unless (abiName == targetSpecAbi spec) $
    Left ("target-contract " ++ target ++ " abi must be " ++ targetSpecAbi spec)
  unless (conventionName == targetSpecCallingConvention spec) $
    Left ("target-contract " ++ target ++ " calling convention must be " ++ targetSpecCallingConvention spec)
  unless (redZoneMode == targetSpecRedZone spec) $
    Left ("target-contract " ++ target ++ " red-zone must be " ++ targetSpecRedZone spec)
  unless (entryAddress > 0) $
    Left ("target-contract " ++ target ++ " entry-address must be non-zero")
  unless (entryAddress `mod` 4096 == 0) $
    Left ("target-contract " ++ target ++ " entry-address must be page-aligned")
  unless (entryAddress >= targetSpecMinimumEntryAddress spec) $
    Left ("target-contract " ++ target ++ " entry-address must be at or above " ++ show (targetSpecMinimumEntryAddress spec))
  validateCSymbolName ("target-contract symbol for " ++ target) symbol
  validateCSectionName ("target-contract section for " ++ target) sectionName
  validateCallingConventionName ("target-contract calling convention for " ++ target) conventionName
  entry <- lookupGlobal globals entryName
  unless (globalEntryPoint entry) $
    Left ("target-contract " ++ target ++ " entry " ++ entryName ++ " requires entry metadata")
  unless (globalExportSymbol entry == Just symbol) $
    Left ("target-contract " ++ target ++ " entry " ++ entryName ++ " expected emitted symbol " ++ symbol)
  unless (globalSectionName entry == Just sectionName) $
    Left ("target-contract " ++ target ++ " entry " ++ entryName ++ " expected section " ++ sectionName)
  unless (globalCallingConvention entry == Just conventionName) $
    Left ("target-contract " ++ target ++ " entry " ++ entryName ++ " expected calling convention " ++ conventionName)
  validateCEmittableSignature globals ("target-contract " ++ target ++ " entry " ++ entryName) (globalTypeTerm entry)

requireTargetClause :: Name -> Name -> Maybe a -> Either String a
requireTargetClause target key maybeValue =
  case maybeValue of
    Just value -> Right value
    Nothing -> Left ("target-contract " ++ target ++ " missing " ++ key ++ " clause")

targetContractClauseKey :: TargetContractClause -> Name
targetContractClauseKey clause =
  case clause of
    TargetContractFormat _ -> "format"
    TargetContractArch _ -> "arch"
    TargetContractAbi _ -> "abi"
    TargetContractEntry _ -> "entry"
    TargetContractSymbol _ -> "symbol"
    TargetContractSection _ -> "section"
    TargetContractCallingConvention _ -> "calling-convention"
    TargetContractEntryAddress _ -> "entry-address"
    TargetContractRedZone _ -> "red-zone"
    TargetContractFreestanding -> "freestanding"

targetContractFormat :: [TargetContractClause] -> Maybe Name
targetContractFormat clauses =
  case [formatName | TargetContractFormat formatName <- clauses] of
    formatName : _ -> Just formatName
    [] -> Nothing

targetContractArch :: [TargetContractClause] -> Maybe Name
targetContractArch clauses =
  case [archName | TargetContractArch archName <- clauses] of
    archName : _ -> Just archName
    [] -> Nothing

targetContractAbi :: [TargetContractClause] -> Maybe Name
targetContractAbi clauses =
  case [abiName | TargetContractAbi abiName <- clauses] of
    abiName : _ -> Just abiName
    [] -> Nothing

targetContractEntry :: [TargetContractClause] -> Maybe Name
targetContractEntry clauses =
  case [entryName | TargetContractEntry entryName <- clauses] of
    entryName : _ -> Just entryName
    [] -> Nothing

targetContractSymbol :: [TargetContractClause] -> Maybe Name
targetContractSymbol clauses =
  case [symbol | TargetContractSymbol symbol <- clauses] of
    symbol : _ -> Just symbol
    [] -> Nothing

targetContractSection :: [TargetContractClause] -> Maybe Name
targetContractSection clauses =
  case [sectionName | TargetContractSection sectionName <- clauses] of
    sectionName : _ -> Just sectionName
    [] -> Nothing

targetContractCallingConvention :: [TargetContractClause] -> Maybe Name
targetContractCallingConvention clauses =
  case [conventionName | TargetContractCallingConvention conventionName <- clauses] of
    conventionName : _ -> Just conventionName
    [] -> Nothing

targetContractEntryAddress :: [TargetContractClause] -> Maybe Word64
targetContractEntryAddress clauses =
  case [address | TargetContractEntryAddress address <- clauses] of
    address : _ -> Just address
    [] -> Nothing

targetContractRedZone :: [TargetContractClause] -> Maybe Name
targetContractRedZone clauses =
  case [mode | TargetContractRedZone mode <- clauses] of
    mode : _ -> Just mode
    [] -> Nothing

validateBootContractClauses :: Globals -> Name -> [BootContractClause] -> Either String ()
validateBootContractClauses globals name clauses = do
  unless (name == "limine-x86_64") $
    Left ("unsupported boot-contract " ++ name)
  ensureDistinct ("duplicate boot-contract clause for " ++ name) (map bootContractClauseKey clauses)
  protocol <- requireBootClause name "protocol" (bootContractProtocol clauses)
  target <- requireBootClause name "target" (bootContractTarget clauses)
  entryName <- requireBootClause name "entry" (bootContractEntry clauses)
  kernelPath <- requireBootClause name "kernel-path" (bootContractKernelPath clauses)
  configPath <- requireBootClause name "config-path" (bootContractConfigPath clauses)
  unless (BootContractFreestanding `elem` clauses) $
    Left ("boot-contract " ++ name ++ " missing freestanding clause")
  unless (protocol == "limine") $
    Left ("boot-contract " ++ name ++ " protocol must be limine")
  unless (target == "x86_64-limine-elf") $
    Left ("boot-contract " ++ name ++ " target must be x86_64-limine-elf")
  validateBootPath ("boot-contract " ++ name ++ " kernel path") kernelPath
  validateBootPath ("boot-contract " ++ name ++ " config path") configPath
  targetClauses <-
    case Map.lookup target (globalsTargetContracts globals) of
      Just existing -> Right existing
      Nothing -> Left ("boot-contract " ++ name ++ " target " ++ target ++ " has no checked target-contract")
  targetEntry <- requireTargetClause target "entry" (targetContractEntry targetClauses)
  unless (targetEntry == entryName) $
    Left ("boot-contract " ++ name ++ " entry " ++ entryName ++ " does not match target-contract entry " ++ targetEntry)
  entry <- lookupGlobal globals entryName
  unless (globalEntryPoint entry) $
    Left ("boot-contract " ++ name ++ " entry " ++ entryName ++ " requires entry metadata")
  targetAddress <- requireTargetClause target "entry-address" (targetContractEntryAddress targetClauses)
  unless (targetAddress >= limineHigherHalfBase) $
    Left ("boot-contract " ++ name ++ " target " ++ target ++ " must use a higher-half entry address")

requireBootClause :: Name -> Name -> Maybe a -> Either String a
requireBootClause name key maybeValue =
  case maybeValue of
    Just value -> Right value
    Nothing -> Left ("boot-contract " ++ name ++ " missing " ++ key ++ " clause")

bootContractClauseKey :: BootContractClause -> Name
bootContractClauseKey clause =
  case clause of
    BootContractProtocol _ -> "protocol"
    BootContractTarget _ -> "target"
    BootContractEntry _ -> "entry"
    BootContractKernelPath _ -> "kernel-path"
    BootContractConfigPath _ -> "config-path"
    BootContractFreestanding -> "freestanding"

bootContractProtocol :: [BootContractClause] -> Maybe Name
bootContractProtocol clauses =
  case [protocol | BootContractProtocol protocol <- clauses] of
    protocol : _ -> Just protocol
    [] -> Nothing

bootContractTarget :: [BootContractClause] -> Maybe Name
bootContractTarget clauses =
  case [target | BootContractTarget target <- clauses] of
    target : _ -> Just target
    [] -> Nothing

bootContractEntry :: [BootContractClause] -> Maybe Name
bootContractEntry clauses =
  case [entryName | BootContractEntry entryName <- clauses] of
    entryName : _ -> Just entryName
    [] -> Nothing

bootContractKernelPath :: [BootContractClause] -> Maybe Name
bootContractKernelPath clauses =
  case [path | BootContractKernelPath path <- clauses] of
    path : _ -> Just path
    [] -> Nothing

bootContractConfigPath :: [BootContractClause] -> Maybe Name
bootContractConfigPath clauses =
  case [path | BootContractConfigPath path <- clauses] of
    path : _ -> Just path
    [] -> Nothing

validateBootPath :: String -> Name -> Either String ()
validateBootPath label path =
  case path of
    '/' : rest
      | not (null rest) && all isBootPathChar path -> Right ()
    _ -> Left (label ++ " must be an absolute boot path atom")

isBootPathChar :: Char -> Bool
isBootPathChar char =
  char /= '"' && char /= '\\' && char /= ';' && char /= '(' && char /= ')'

validateCEmittableSignature :: Globals -> String -> Term -> Either String ()
validateCEmittableSignature globals label ty =
  case ty of
    TPi _ quantity domain codomain -> do
      case quantity of
        Q0 -> Right ()
        _ -> validateCEmittableRuntimeType globals label domain
      validateCEmittableSignature globals label codomain
    TApp (TApp (TApp (TGlobal "Eff") _) _) resultTy ->
      validateCEmittableRuntimeType globals label resultTy
    _ ->
      validateCEmittableRuntimeType globals label ty

validateCEmittableRuntimeType :: Globals -> String -> Term -> Either String ()
validateCEmittableRuntimeType globals label ty =
  case runtimeTypeLayoutTerm globals ty of
    Just _ -> Right ()
    Nothing ->
      Left (label ++ " must have a first-order C-emittable signature, unsupported runtime type " ++ prettyTerm ty)

piFromBinder :: Binder Term -> Term -> Term
piFromBinder binder body =
  TPi (binderName binder) (binderQuantity binder) (binderPayload binder) body

dataResultTerm :: Name -> Int -> Int -> Term
dataResultTerm dataName paramCount fieldCount =
  apps
    (TGlobal dataName)
    [ TVar (fieldCount + paramCount - index - 1)
    | index <- [0 .. paramCount - 1]
    ]

ctorDeclName :: ConstructorDecl -> Name
ctorDeclName (ConstructorDecl ctorName _) = ctorName

ensureFresh :: Globals -> Name -> Either String ()
ensureFresh globals name =
  case lookupGlobalMaybe globals name of
    Nothing -> Right ()
    Just _ -> Left ("duplicate top-level name " ++ name)

staticBytesLengthName :: Name -> Name
staticBytesLengthName name =
  name ++ "-len"

insertGlobal :: Name -> GlobalEntry -> Globals -> Globals
insertGlobal name entry globals =
  globals {globalsEntries = Map.insert name entry (globalsEntries globals)}

insertDataInfo :: Name -> DataInfo -> Globals -> Globals
insertDataInfo name info globals =
  globals {globalsDataInfos = Map.insert name info (globalsDataInfos globals)}

insertConstructorInfo :: Name -> ConstructorInfo -> Globals -> Globals
insertConstructorInfo name info globals =
  globals {globalsConstructorInfos = Map.insert name info (globalsConstructorInfos globals)}

insertLayoutInfo :: Name -> LayoutInfo -> Globals -> Globals
insertLayoutInfo name info globals =
  globals {globalsLayoutInfos = Map.insert name info (globalsLayoutInfos globals)}

lookupGlobal :: Globals -> Name -> Either String GlobalEntry
lookupGlobal globals name =
  case lookupGlobalMaybe globals name of
    Nothing -> Left ("unknown global " ++ name)
    Just entry -> Right entry

lookupGlobalMaybe :: Globals -> Name -> Maybe GlobalEntry
lookupGlobalMaybe globals name =
  Map.lookup name (globalsEntries globals)

lookupDataInfoMaybe :: Globals -> Name -> Maybe DataInfo
lookupDataInfoMaybe globals name =
  Map.lookup name (globalsDataInfos globals)

lookupLayoutInfoMaybe :: Globals -> Name -> Maybe LayoutInfo
lookupLayoutInfoMaybe globals name =
  Map.lookup name (globalsLayoutInfos globals)

lookupLayoutFieldMaybe :: Globals -> Name -> Name -> Maybe LayoutFieldInfo
lookupLayoutFieldMaybe globals layoutName fieldName = do
  layoutInfo <- lookupLayoutInfoMaybe globals layoutName
  Map.lookup fieldName (layoutFields layoutInfo)

lookupConstructorInfoMaybe :: Globals -> Name -> Maybe ConstructorInfo
lookupConstructorInfoMaybe globals name =
  Map.lookup name (globalsConstructorInfos globals)

lookupLocal :: Context -> Name -> Maybe (Int, Value)
lookupLocal ctx target =
  go 0 ctx
  where
    go _ [] = Nothing
    go index (entry : rest)
      | ctxName entry == target = Just (index, ctxType entry)
      | otherwise = go (index + 1) rest

infer :: Globals -> Context -> Env -> Surface -> Either String (Term, Value)
infer globals ctx env surface =
  case surface of
    SVar name ->
      case lookupLocal ctx name of
        Just (index, ty) ->
          Right (TVar index, ty)
        Nothing ->
          case lookupGlobalMaybe globals name of
            Just entry -> Right (TGlobal name, globalTypeValue entry)
            Nothing -> Left ("unknown name " ++ name)
    SUniverse level ->
      Right (TUniverse level, VUniverse (level + 1))
    SU8 value ->
      Right (TU8 value, u8TypeValue)
    SU64 value ->
      Right (TU64 value, u64TypeValue)
    SAddr value ->
      Right (TAddr value, addrTypeValue)
    SPi binders body -> do
      (ctx', env', domains, maxDomainLevel) <- inferBinders globals ctx env binders
      (bodyTerm, bodyTy) <- infer globals ctx' env' body
      bodyLevel <- expectUniverse (length env') bodyTy
      let resultLevel = max maxDomainLevel bodyLevel
      let term = foldr piFromBinder bodyTerm domains
      Right (term, VUniverse resultLevel)
    SLam _ _ ->
      Left "cannot infer a lambda without an expected Pi type"
    SLet bindings body ->
      inferLet globals ctx env bindings body
    SLetLayout layoutName bindings source body ->
      infer globals ctx env (desugarLayoutLet layoutName bindings source body)
    SLetLoadLayout capSurface layoutName bindings source body ->
      inferLayoutLoad globals ctx env capSurface layoutName bindings source body
    SWithFields layoutName source fields ->
      infer globals ctx env (desugarLayoutUpdate layoutName source fields)
    SStoreFields capSurface layoutName base fields ->
      infer globals ctx env (desugarLayoutStore capSurface layoutName base fields)
    SMatch _ _ ->
      Left "cannot infer match without an expected type; wrap it with (the ...)"
    SLayout layoutName fieldSurfaces ->
      inferLayoutLiteral globals ctx env layoutName fieldSurfaces
    SLayoutValues layoutName valueSurfaces ->
      inferLayoutValues globals ctx env layoutName valueSurfaces
    SApp (SVar "Eff") [capSurface, resultSurface] ->
      infer globals ctx env (SApp (SVar "Eff") [capSurface, capSurface, resultSurface])
    SApp (SVar "bind") [capSurface, aSurface, bSurface, actionSurface, kSurface] ->
      infer globals ctx env (SApp (SVar "bind") [capSurface, capSurface, capSurface, aSurface, bSurface, actionSurface, kSurface])
    SApp (SVar "load") [tySurface, ptrSurface] ->
      infer globals ctx env (SApp (SVar "load") [SVar "Heap", tySurface, ptrSurface])
    SApp (SVar "store") [tySurface, ptrSurface, valueSurface] ->
      infer globals ctx env (SApp (SVar "store") [SVar "Heap", SVar "Heap", tySurface, ptrSurface, valueSurface])
    SApp (SVar "load-u64") [ptrSurface] ->
      infer globals ctx env (SApp (SVar "load-u64") [SVar "Heap", ptrSurface])
    SApp (SVar "store-u64") [ptrSurface, valueSurface] ->
      infer globals ctx env (SApp (SVar "store-u64") [SVar "Heap", SVar "Heap", ptrSurface, valueSurface])
    SApp (SVar "load-addr") [ptrSurface] ->
      infer globals ctx env (SApp (SVar "load-addr") [SVar "Heap", ptrSurface])
    SApp (SVar "store-addr") [ptrSurface, valueSurface] ->
      infer globals ctx env (SApp (SVar "store-addr") [SVar "Heap", SVar "Heap", ptrSurface, valueSurface])
    SApp (SVar "field-offset") [SVar layoutName, SVar fieldName] ->
      inferFieldOffset globals layoutName fieldName
    SApp (SVar "field") [SVar layoutName, SVar fieldName, baseSurface] ->
      inferFieldValue globals ctx env layoutName fieldName baseSurface
    SApp (SVar "with-field") [SVar layoutName, SVar fieldName, baseSurface, valueSurface] ->
      inferLayoutUpdate globals ctx env layoutName fieldName baseSurface valueSurface
    SApp (SVar "ptr-field") [SVar layoutName, SVar fieldName, baseSurface] ->
      inferPtrField globals ctx env layoutName fieldName baseSurface
    SApp (SVar "load-field") [capSurface, SVar layoutName, SVar fieldName, baseSurface] ->
      inferLoadField globals ctx env capSurface layoutName fieldName baseSurface
    SApp (SVar "load-field") [SVar layoutName, SVar fieldName, baseSurface] ->
      inferLoadField globals ctx env (SVar "Heap") layoutName fieldName baseSurface
    SApp (SVar "store-field") [preSurface, postSurface, SVar layoutName, SVar fieldName, baseSurface, valueSurface] ->
      inferStoreField globals ctx env preSurface postSurface layoutName fieldName baseSurface valueSurface
    SApp (SVar "store-field") [SVar layoutName, SVar fieldName, baseSurface, valueSurface] ->
      inferStoreField globals ctx env (SVar "Heap") (SVar "Heap") layoutName fieldName baseSurface valueSurface
    SApp fn args -> do
      (fnTerm, fnTy) <- infer globals ctx env fn
      foldl (inferApplication globals ctx env) (Right (fnTerm, fnTy)) args
    SAnn expr tySurface -> do
      (tyTerm, tyTy) <- infer globals ctx env tySurface
      _ <- expectUniverse (length env) tyTy
      let tyValue = eval globals env tyTerm
      exprTerm <- check globals ctx env expr tyValue
      Right (exprTerm, tyValue)

inferApplication :: Globals -> Context -> Env -> Either String (Term, Value) -> Surface -> Either String (Term, Value)
inferApplication globals ctx env result argSurface = do
  (fnTerm, fnTy) <- result
  case fnTy of
    VPi _ _ domain closure -> do
      argTerm <- check globals ctx env argSurface domain
      let argValue = eval globals env argTerm
      Right (TApp fnTerm argTerm, instantiate closure argValue)
    _ ->
      Left "attempted to apply a non-function"

inferFieldOffset :: Globals -> Name -> Name -> Either String (Term, Value)
inferFieldOffset globals layoutName fieldName =
  case lookupLayoutFieldMaybe globals layoutName fieldName of
    Nothing -> Left ("unknown layout field " ++ layoutName ++ "." ++ fieldName)
    Just fieldInfo -> Right (TU64 (layoutFieldOffset fieldInfo), u64TypeValue)

inferFieldValue :: Globals -> Context -> Env -> Name -> Name -> Surface -> Either String (Term, Value)
inferFieldValue globals ctx env layoutName fieldName baseSurface = do
  fieldInfo <-
    case lookupLayoutFieldMaybe globals layoutName fieldName of
      Nothing -> Left ("unknown layout field " ++ layoutName ++ "." ++ fieldName)
      Just info -> Right info
  let layoutTy = eval globals [] (TGlobal layoutName)
  baseTerm <- check globals ctx env baseSurface layoutTy
  let fieldTy = eval globals [] (layoutFieldTypeTerm fieldInfo)
  pure (TLayoutField layoutName fieldName baseTerm, fieldTy)

inferLayoutUpdate :: Globals -> Context -> Env -> Name -> Name -> Surface -> Surface -> Either String (Term, Value)
inferLayoutUpdate globals ctx env layoutName fieldName baseSurface valueSurface = do
  fieldInfo <-
    case lookupLayoutFieldMaybe globals layoutName fieldName of
      Nothing -> Left ("unknown layout field " ++ layoutName ++ "." ++ fieldName)
      Just info -> Right info
  let layoutTy = eval globals [] (TGlobal layoutName)
  baseTerm <- check globals ctx env baseSurface layoutTy
  valueTerm <- check globals ctx env valueSurface (eval globals [] (layoutFieldTypeTerm fieldInfo))
  pure (TLayoutUpdate layoutName fieldName baseTerm valueTerm, layoutTy)

inferPtrField :: Globals -> Context -> Env -> Name -> Name -> Surface -> Either String (Term, Value)
inferPtrField globals ctx env layoutName fieldName baseSurface = do
  (fieldInfo, baseTerm) <- checkLayoutPtr globals ctx env layoutName fieldName baseSurface
  let fieldTy = layoutFieldTypeTerm fieldInfo
  let term = layoutFieldPointerTerm layoutName fieldInfo baseTerm
  let termTy = eval globals [] (TApp (TGlobal "Ptr") fieldTy)
  pure (term, termTy)

inferLoadField :: Globals -> Context -> Env -> Surface -> Name -> Name -> Surface -> Either String (Term, Value)
inferLoadField globals ctx env capSurface layoutName fieldName baseSurface = do
  (fieldInfo, baseTerm) <- checkLayoutPtr globals ctx env layoutName fieldName baseSurface
  capTerm <- inferCapabilityTerm globals ctx env capSurface
  let fieldTy = layoutFieldTypeTerm fieldInfo
  let fieldPtr = layoutFieldPointerTerm layoutName fieldInfo baseTerm
  let term = apps (TGlobal "load") [capTerm, fieldTy, fieldPtr]
  let termTy = stableEffectType globals env capTerm fieldTy
  pure (term, termTy)

inferStoreField :: Globals -> Context -> Env -> Surface -> Surface -> Name -> Name -> Surface -> Surface -> Either String (Term, Value)
inferStoreField globals ctx env preSurface postSurface layoutName fieldName baseSurface valueSurface = do
  (fieldInfo, baseTerm) <- checkLayoutPtr globals ctx env layoutName fieldName baseSurface
  preTerm <- inferCapabilityTerm globals ctx env preSurface
  postTerm <- inferCapabilityTerm globals ctx env postSurface
  let fieldTy = layoutFieldTypeTerm fieldInfo
  valueTerm <- check globals ctx env valueSurface (eval globals [] fieldTy)
  let fieldPtr = layoutFieldPointerTerm layoutName fieldInfo baseTerm
  let term = apps (TGlobal "store") [preTerm, postTerm, fieldTy, fieldPtr, valueTerm]
  let termTy = effectType globals env preTerm postTerm (TGlobal "Unit")
  pure (term, termTy)

checkLayoutPtr :: Globals -> Context -> Env -> Name -> Name -> Surface -> Either String (LayoutFieldInfo, Term)
checkLayoutPtr globals ctx env layoutName fieldName baseSurface = do
  fieldInfo <-
    case lookupLayoutFieldMaybe globals layoutName fieldName of
      Nothing -> Left ("unknown layout field " ++ layoutName ++ "." ++ fieldName)
      Just info -> Right info
  let layoutPtrTy = eval globals [] (TApp (TGlobal "Ptr") (TGlobal layoutName))
  baseTerm <- check globals ctx env baseSurface layoutPtrTy
  pure (fieldInfo, baseTerm)

layoutFieldPointerTerm :: Name -> LayoutFieldInfo -> Term -> Term
layoutFieldPointerTerm layoutName fieldInfo baseTerm =
  let fieldTy = layoutFieldTypeTerm fieldInfo
      baseAddr = apps (TGlobal "ptr-to-addr") [TGlobal layoutName, baseTerm]
      fieldAddr = apps (TGlobal "addr-add") [baseAddr, TU64 (layoutFieldOffset fieldInfo)]
   in apps (TGlobal "ptr-from-addr") [fieldTy, fieldAddr]

inferCapabilityTerm :: Globals -> Context -> Env -> Surface -> Either String Term
inferCapabilityTerm globals ctx env capSurface = do
  (capTerm, capTy) <- infer globals ctx env capSurface
  _ <- expectUniverse (length env) capTy
  pure capTerm

effectType :: Globals -> Env -> Term -> Term -> Term -> Value
effectType globals env preTerm postTerm resultTy =
  eval globals env (apps (TGlobal "Eff") [preTerm, postTerm, resultTy])

stableEffectType :: Globals -> Env -> Term -> Term -> Value
stableEffectType globals env capTerm resultTy =
  effectType globals env capTerm capTerm resultTy

inferLayoutLiteral :: Globals -> Context -> Env -> Name -> [LayoutFieldInit Surface] -> Either String (Term, Value)
inferLayoutLiteral globals ctx env layoutName fieldSurfaces = do
  layoutInfo <-
    case lookupLayoutInfoMaybe globals layoutName of
      Nothing -> Left ("unknown layout " ++ layoutName)
      Just info -> Right info
  let providedNames = [fieldName | LayoutFieldInit fieldName _ <- fieldSurfaces]
  ensureDistinct ("duplicate field in layout literal " ++ layoutName) providedNames
  let unknownFields =
        [ fieldName
        | fieldName <- providedNames
        , Map.notMember fieldName (layoutFields layoutInfo)
        ]
  unless (null unknownFields) $
    Left ("unknown layout field " ++ layoutName ++ "." ++ head unknownFields)
  let providedMap = Map.fromList [(fieldName, fieldSurface) | LayoutFieldInit fieldName fieldSurface <- fieldSurfaces]
  let missingFields =
        [ fieldName
        | fieldName <- layoutFieldOrder layoutInfo
        , Map.notMember fieldName providedMap
        ]
  unless (null missingFields) $
    Left ("missing layout field " ++ layoutName ++ "." ++ head missingFields)
  fieldTerms <-
    traverse
      (\fieldName -> do
          fieldInfo <-
            case lookupLayoutFieldMaybe globals layoutName fieldName of
              Nothing ->
                Left ("internal error: missing checked metadata for layout field " ++ layoutName ++ "." ++ fieldName)
              Just info -> Right info
          fieldSurface <-
            case Map.lookup fieldName providedMap of
              Nothing ->
                Left ("internal error: layout literal field disappeared for " ++ layoutName ++ "." ++ fieldName)
              Just value -> Right value
          fieldTerm <- check globals ctx env fieldSurface (eval globals [] (layoutFieldTypeTerm fieldInfo))
          pure (LayoutFieldInit fieldName fieldTerm)
      )
      (layoutFieldOrder layoutInfo)
  pure (TLayout layoutName fieldTerms, eval globals [] (TGlobal layoutName))

inferLayoutValues :: Globals -> Context -> Env -> Name -> [Surface] -> Either String (Term, Value)
inferLayoutValues globals ctx env layoutName valueSurfaces = do
  layoutInfo <-
    case lookupLayoutInfoMaybe globals layoutName of
      Nothing -> Left ("unknown layout " ++ layoutName)
      Just info -> Right info
  let fieldNames = layoutFieldOrder layoutInfo
  unless (length valueSurfaces == length fieldNames) $
    Left
      ( "layout-values "
          ++ layoutName
          ++ " expects "
          ++ show (length fieldNames)
          ++ " fields, got "
          ++ show (length valueSurfaces)
      )
  inferLayoutLiteral globals ctx env layoutName (zipWith LayoutFieldInit fieldNames valueSurfaces)

check :: Globals -> Context -> Env -> Surface -> Value -> Either String Term
check globals ctx env surface expected =
  case surface of
    SLam binders body ->
      checkLambda globals ctx env binders body expected
    SLet bindings body ->
      checkLet globals ctx env bindings body expected
    SLetLayout layoutName bindings source body ->
      check globals ctx env (desugarLayoutLet layoutName bindings source body) expected
    SLetLoadLayout capSurface layoutName bindings source body ->
      checkLayoutLoad globals ctx env capSurface layoutName bindings source body expected
    SWithFields layoutName source fields ->
      check globals ctx env (desugarLayoutUpdate layoutName source fields) expected
    SStoreFields capSurface layoutName base fields ->
      check globals ctx env (desugarLayoutStore capSurface layoutName base fields) expected
    SMatch scrutinee arms ->
      checkMatch globals ctx env scrutinee arms expected
    _ -> do
      (term, actual) <- infer globals ctx env surface
      unless (convertible (length env) actual expected) $
        Left
          ( "type mismatch\nexpected: "
              ++ prettyTerm (quote (length env) expected)
              ++ "\nactual:   "
              ++ prettyTerm (quote (length env) actual)
          )
      Right term

checkLambda :: Globals -> Context -> Env -> [Binder Surface] -> Surface -> Value -> Either String Term
checkLambda globals ctx env binders body expected =
  case binders of
    [] -> check globals ctx env body expected
    Binder name quantity annSurface : rest ->
      case expected of
        VPi _ expectedQuantity domain closure -> do
          (annTerm, annTy) <- infer globals ctx env annSurface
          _ <- expectUniverse (length env) annTy
          let annValue = eval globals env annTerm
          unless (quantity == expectedQuantity) $
            Left
              ( "lambda binder quantity for "
                  ++ name
                  ++ " does not match the expected quantity\nannotation: "
                  ++ renderQuantity quantity
                  ++ "\nexpected:   "
                  ++ renderQuantity expectedQuantity
              )
          unless (convertible (length env) annValue domain) $
            Left
              ( "lambda binder annotation for "
                  ++ name
                  ++ " does not match the expected domain\nannotation: "
                  ++ prettyTerm (quote (length env) annValue)
                  ++ "\nexpected:   "
                  ++ prettyTerm (quote (length env) domain)
              )
          let local = freshLocal env
          let ctx' = CtxEntry name domain : ctx
          let env' = local : env
          let bodyTy = instantiate closure local
          bodyTerm <- checkLambda globals ctx' env' rest body bodyTy
          ensureUsageQuantity globals name quantity bodyTerm
          Right (TLam name quantity bodyTerm)
        _ ->
          Left "lambda checked against a non-function type"

inferLet :: Globals -> Context -> Env -> [Binder Surface] -> Surface -> Either String (Term, Value)
inferLet globals ctx env bindings body =
  case bindings of
    [] -> infer globals ctx env body
    Binder name quantity exprSurface : rest -> do
      (exprTerm, exprTy) <- infer globals ctx env exprSurface
      let local = freshLocal env
      let ctx' = CtxEntry name exprTy : ctx
      let env' = local : env
      (bodyTerm, bodyTy) <- inferLet globals ctx' env' rest body
      ensureUsageQuantity globals name quantity bodyTerm
      let resultTerm = TApp (TLam name quantity bodyTerm) exprTerm
      let bodyTyTerm = quote (length env') bodyTy
      let resultTy = eval globals env (substTop exprTerm bodyTyTerm)
      pure (resultTerm, resultTy)

inferLayoutLoad :: Globals -> Context -> Env -> Surface -> Name -> [LayoutBinding] -> Surface -> Surface -> Either String (Term, Value)
inferLayoutLoad globals ctx env capSurface layoutName bindings baseSurface bodySurface = do
  layoutTy <- lookupLayoutTypeValue globals layoutName
  capTerm <- inferCapabilityTerm globals ctx env capSurface
  let capValue = eval globals env capTerm
  baseTerm <- checkLayoutBasePointer globals ctx env layoutName baseSurface
  let local = freshLocal env
  let ctx' = CtxEntry hiddenLoadedLayoutName layoutTy : ctx
  let env' = local : env
  let bodySurface' = desugarLayoutLoadBody layoutName bindings bodySurface
  (bodyTerm, bodyTy) <- infer globals ctx' env' bodySurface'
  resultTy <- expectStableEffectResult (length env') "let-load-layout body" capValue bodyTy
  resultTyTermOpen <- reifyType (length env') resultTy
  when (countVarUses 0 resultTyTermOpen /= 0) $
    Left "let-load-layout body result type cannot depend on the loaded layout value"
  let resultTyTerm = shift 0 (-1) resultTyTermOpen
  pure (layoutLoadTerm capTerm layoutName baseTerm resultTyTerm bodyTerm, stableEffectType globals env capTerm resultTyTerm)

checkLayoutLoad :: Globals -> Context -> Env -> Surface -> Name -> [LayoutBinding] -> Surface -> Surface -> Value -> Either String Term
checkLayoutLoad globals ctx env capSurface layoutName bindings baseSurface bodySurface expected = do
  layoutTy <- lookupLayoutTypeValue globals layoutName
  capTerm <- inferCapabilityTerm globals ctx env capSurface
  let capValue = eval globals env capTerm
  resultTy <- expectStableEffectResult (length env) "let-load-layout" capValue expected
  resultTyTerm <- reifyType (length env) resultTy
  baseTerm <- checkLayoutBasePointer globals ctx env layoutName baseSurface
  let local = freshLocal env
  let ctx' = CtxEntry hiddenLoadedLayoutName layoutTy : ctx
  let env' = local : env
  bodyTerm <- check globals ctx' env' (desugarLayoutLoadBody layoutName bindings bodySurface) expected
  pure (layoutLoadTerm capTerm layoutName baseTerm resultTyTerm bodyTerm)

desugarLayoutLet :: Name -> [LayoutBinding] -> Surface -> Surface -> Surface
desugarLayoutLet layoutName bindings source body =
  SLet
    ( Binder hiddenLayoutLetName QOmega source
        : [ Binder
              (layoutBindingName binding)
              (layoutBindingQuantity binding)
              (SApp (SVar "field") [SVar layoutName, SVar (layoutBindingField binding), SVar hiddenLayoutLetName])
          | binding <- bindings
          ]
    )
    body

desugarLayoutLoadBody :: Name -> [LayoutBinding] -> Surface -> Surface
desugarLayoutLoadBody layoutName bindings body =
  desugarLayoutLet layoutName bindings (SVar hiddenLoadedLayoutName) body

desugarLayoutUpdate :: Name -> Surface -> [LayoutFieldInit Surface] -> Surface
desugarLayoutUpdate layoutName source fields =
  SLet
    [Binder hiddenLayoutLetName QOmega source]
    (foldl applyFieldUpdate (SVar hiddenLayoutLetName) fields)
  where
    applyFieldUpdate base (LayoutFieldInit fieldName value) =
      SApp (SVar "with-field") [SVar layoutName, SVar fieldName, base, value]

desugarLayoutStore :: Surface -> Name -> Surface -> [LayoutFieldInit Surface] -> Surface
desugarLayoutStore cap layoutName base fields =
  desugarUnitEffectSequence cap
    [ SApp (SVar "store-field") [cap, cap, SVar layoutName, SVar fieldName, base, value]
    | LayoutFieldInit fieldName value <- fields
    ]

desugarUnitEffectSequence :: Surface -> [Surface] -> Surface
desugarUnitEffectSequence cap effects =
  case effects of
    [] ->
      SApp (SVar "pure") [cap, SVar "Unit", SVar "tt"]
    [effect] ->
      effect
    effect : rest ->
      SApp
        (SVar "bind")
        [ cap
        , cap
        , cap
        , SVar "Unit"
        , SVar "Unit"
        , effect
        , SLam
            [Binder hiddenEffectResultName Q1 (SVar "Unit")]
            ( SLet
                [Binder hiddenEffectIgnoredName Q0 (SVar hiddenEffectResultName)]
                (desugarUnitEffectSequence cap rest)
            )
        ]

layoutLoadTerm :: Term -> Name -> Term -> Term -> Term -> Term
layoutLoadTerm capTerm layoutName baseTerm resultTy bodyTerm =
  apps
    (TGlobal "bind")
    [ capTerm
    , capTerm
    , capTerm
    , TGlobal layoutName
    , resultTy
    , apps (TGlobal "load") [capTerm, TGlobal layoutName, baseTerm]
    , TLam hiddenLoadedLayoutName Q1 bodyTerm
    ]

lookupLayoutTypeValue :: Globals -> Name -> Either String Value
lookupLayoutTypeValue globals layoutName =
  case lookupLayoutInfoMaybe globals layoutName of
    Nothing -> Left ("unknown layout " ++ layoutName)
    Just _ -> Right (eval globals [] (TGlobal layoutName))

checkLayoutBasePointer :: Globals -> Context -> Env -> Name -> Surface -> Either String Term
checkLayoutBasePointer globals ctx env layoutName baseSurface = do
  _ <- lookupLayoutTypeValue globals layoutName
  let layoutPtrTy = eval globals [] (TApp (TGlobal "Ptr") (TGlobal layoutName))
  check globals ctx env baseSurface layoutPtrTy

expectStableEffectResult :: Int -> String -> Value -> Value -> Either String Value
expectStableEffectResult depth label capValue value =
  case value of
    VPrim "Eff" [pre, post, resultTy]
      | convertible depth pre capValue && convertible depth post capValue ->
          Right resultTy
      | otherwise -> Left (label ++ " must synthesize or check as a stable effect for the supplied capability")
    _ ->
      Left (label ++ " must synthesize or check as a stable effect for the supplied capability")

hiddenLayoutLetName :: Name
hiddenLayoutLetName = ""

hiddenLoadedLayoutName :: Name
hiddenLoadedLayoutName = ""

hiddenEffectResultName :: Name
hiddenEffectResultName = ""

hiddenEffectIgnoredName :: Name
hiddenEffectIgnoredName = ""

checkLet :: Globals -> Context -> Env -> [Binder Surface] -> Surface -> Value -> Either String Term
checkLet globals ctx env bindings body expected =
  case bindings of
    [] -> check globals ctx env body expected
    Binder name quantity exprSurface : rest -> do
      (exprTerm, exprTy) <- infer globals ctx env exprSurface
      let local = freshLocal env
      let ctx' = CtxEntry name exprTy : ctx
      let env' = local : env
      bodyTerm <- checkLet globals ctx' env' rest body expected
      ensureUsageQuantity globals name quantity bodyTerm
      pure (TApp (TLam name quantity bodyTerm) exprTerm)

checkMatch :: Globals -> Context -> Env -> Surface -> [MatchArm] -> Value -> Either String Term
checkMatch globals ctx env scrutineeSurface arms expected = do
  (scrutineeTerm, scrutineeTy) <- infer globals ctx env scrutineeSurface
  expectedTerm <- reifyType (length env) expected
  case asDataApplication globals scrutineeTy of
    Just ("Bool", _) -> do
      rejectUnexpectedArms globals "Bool" arms
      falseBody <- constructorArm "False" 0 arms
      trueBody <- constructorArm "True" 0 arms
      falseTerm <- check globals ctx env falseBody expected
      trueTerm <- check globals ctx env trueBody expected
      pure (apps (TGlobal "bool-case") [expectedTerm, falseTerm, trueTerm, scrutineeTerm])
    Just ("Nat", _) -> do
      rejectUnexpectedArms globals "Nat" arms
      zeroBody <- constructorArm "Z" 0 arms
      (succBinder, succBody) <- constructorArm1 "S" arms
      zeroTerm <- check globals ctx env zeroBody expected
      let local = freshLocal env
      let ctx' = CtxEntry (patternBinderName succBinder) natTypeValue : ctx
      let env' = local : env
      succBodyTerm <- check globals ctx' env' succBody expected
      ensureUsageQuantity globals (patternBinderName succBinder) (patternBinderQuantity succBinder) succBodyTerm
      let succLambda = TLam (patternBinderName succBinder) (patternBinderQuantity succBinder) succBodyTerm
      pure (apps (TGlobal "nat-case") [expectedTerm, zeroTerm, succLambda, scrutineeTerm])
    Just (dataName, params) ->
      checkGenericMatch globals ctx env dataName params scrutineeTerm arms expected
    Nothing ->
      Left
        ( "match currently supports algebraic data scrutinees only, found "
            ++ prettyTerm (quote (length env) scrutineeTy)
        )

checkGenericMatch ::
     Globals
  -> Context
  -> Env
  -> Name
  -> [Value]
  -> Term
  -> [MatchArm]
  -> Value
  -> Either String Term
checkGenericMatch globals ctx env dataName paramValues scrutineeTerm arms expected = do
  dataInfo <-
    case lookupDataInfoMaybe globals dataName of
      Nothing -> Left ("unknown data type " ++ dataName)
      Just info -> Right info
  caseBodies <- traverse (checkConstructorArm globals ctx env paramValues arms expected) (dataConstructors dataInfo)
  rejectUnexpectedArms globals dataName arms
  pure (TMatch scrutineeTerm caseBodies)

checkConstructorArm ::
     Globals
  -> Context
  -> Env
  -> [Value]
  -> [MatchArm]
  -> Value
  -> Name
  -> Either String CaseTerm
checkConstructorArm globals ctx env paramValues arms expected ctorName = do
  ctorInfo <-
    case lookupConstructorInfoMaybe globals ctorName of
      Nothing -> Left ("unknown constructor " ++ ctorName)
      Just info -> Right info
  (binders, bodySurface) <- findArm ctorName arms
  let expectedFields = constructorFieldTypes ctorInfo
  unless (length binders == length expectedFields) $
    Left
      ( "constructor pattern "
          ++ ctorName
          ++ " expects "
          ++ show (length expectedFields)
          ++ " binders, found "
          ++ show (length binders)
      )
  let fieldTypes = map (eval globals (reverse paramValues)) expectedFields
  let (ctx', env') =
        foldl
          (\(accCtx, accEnv) (binder', fieldTy) ->
              (CtxEntry (patternBinderName binder') fieldTy : accCtx, freshLocal accEnv : accEnv))
          (ctx, env)
          (zip binders fieldTypes)
  bodyTerm <- check globals ctx' env' bodySurface expected
  mapM_
    (\(target, binder') -> ensureUsageQuantityAt globals target (patternBinderName binder') (patternBinderQuantity binder') bodyTerm)
    (zip (reverse [0 .. length binders - 1]) binders)
  pure (CaseTerm ctorName binders bodyTerm)

rejectUnexpectedArms :: Globals -> Name -> [MatchArm] -> Either String ()
rejectUnexpectedArms globals dataName arms =
  mapM_ reject arms
  where
    reject (MatchArm (PConstructor ctorName _) _) =
      case lookupConstructorInfoMaybe globals ctorName of
        Nothing -> Left ("unknown constructor in pattern " ++ ctorName)
        Just info ->
          unless (constructorDataName info == dataName) $
            Left ("constructor " ++ ctorName ++ " does not belong to data " ++ dataName)

findArm :: Name -> [MatchArm] -> Either String ([PatternBinder], Surface)
findArm ctorName arms =
  case [(binders, body) | MatchArm (PConstructor name binders) body <- arms, name == ctorName] of
    [(binders, body)] -> Right (binders, body)
    [] -> Left ("missing match arm for " ++ ctorName)
    _ -> Left ("duplicate match arm for " ++ ctorName)

constructorArm :: Name -> Int -> [MatchArm] -> Either String Surface
constructorArm ctorName arity arms = do
  (binders, body) <- findArm ctorName arms
  unless (length binders == arity) $
    Left
      ( "constructor pattern "
          ++ ctorName
          ++ " expects "
          ++ show arity
          ++ " binders, found "
          ++ show (length binders)
      )
  pure body

constructorArm1 :: Name -> [MatchArm] -> Either String (PatternBinder, Surface)
constructorArm1 ctorName arms = do
  (binders, body) <- findArm ctorName arms
  case binders of
    [binder] -> Right (binder, body)
    _ ->
      Left
        ( "constructor pattern "
            ++ ctorName
            ++ " expects 1 binder, found "
            ++ show (length binders)
        )

inferBinders ::
     Globals
  -> Context
  -> Env
  -> [Binder Surface]
  -> Either String (Context, Env, [Binder Term], Int)
inferBinders globals = go [] 0
  where
    go domains maxLevel ctx env [] =
      Right (ctx, env, reverse domains, maxLevel)
    go domains maxLevel ctx env (Binder name quantity tySurface : rest) = do
      (tyTerm, tyTy) <- infer globals ctx env tySurface
      level <- expectUniverse (length env) tyTy
      let tyValue = eval globals env tyTerm
      let local = freshLocal env
      let ctx' = CtxEntry name tyValue : ctx
      let env' = local : env
      go (Binder name quantity tyTerm : domains) (max maxLevel level) ctx' env' rest

expectUniverse :: Int -> Value -> Either String Int
expectUniverse _ (VUniverse level) = Right level
expectUniverse depth value =
  Left ("expected a universe, found " ++ prettyTerm (quote depth value))

freshLocal :: Env -> Value
freshLocal env =
  VNeutral (NLocal (length env))

convertible :: Int -> Value -> Value -> Bool
convertible depth left right =
  quote depth left == quote depth right

ensureUsageQuantity :: Globals -> Name -> Quantity -> Term -> Either String ()
ensureUsageQuantity globals name quantity body =
  ensureUsageQuantityAt globals 0 name quantity body

ensureUsageQuantityAt :: Globals -> Int -> Name -> Quantity -> Term -> Either String ()
ensureUsageQuantityAt globals target name quantity body =
  let uses = countRuntimeUses globals target body
   in case quantity of
        QOmega -> Right ()
        Q0 ->
          if uses == 0
            then Right ()
            else Left ("binder " ++ name ++ " has quantity 0 but is used " ++ show uses ++ " times")
        Q1 ->
          if uses == 1
            then Right ()
            else Left ("binder " ++ name ++ " has quantity 1 but is used " ++ show uses ++ " times")

countRuntimeUses :: Globals -> Int -> Term -> Int
countRuntimeUses globals target term =
  case unfoldApps term of
    (TGlobal name, args@(_ : _)) ->
      countGlobalAppUses globals target name args
    _ ->
      case term of
        TVar index
          | index == target -> 1
          | otherwise -> 0
        TGlobal _ -> 0
        TUniverse _ -> 0
        TU8 _ -> 0
        TU64 _ -> 0
        TAddr _ -> 0
        TStaticBytesPtr _ -> 0
        TStaticCellPtr _ -> 0
        TStaticValuePtr _ -> 0
        TLayout _ fields ->
          sum [countRuntimeUses globals target value | LayoutFieldInit _ value <- fields]
        TLayoutField _ _ base ->
          countRuntimeUses globals target base
        TLayoutUpdate _ _ base value ->
          countRuntimeUses globals target base + countRuntimeUses globals target value
        TPi _ _ domain codomain ->
          countRuntimeUses globals target domain + countRuntimeUses globals (target + 1) codomain
        TLam _ _ body ->
          countRuntimeUses globals (target + 1) body
        TMatch scrutinee cases ->
          countRuntimeUses globals target scrutinee
            + sum [countRuntimeUses globals (target + length binders) body | CaseTerm _ binders body <- cases]
        TApp fn arg ->
          countRuntimeUses globals target fn + countRuntimeUses globals target arg

countGlobalAppUses :: Globals -> Int -> Name -> [Term] -> Int
countGlobalAppUses globals target name args =
  case lookupGlobalMaybe globals name of
    Nothing ->
      sum (map (countRuntimeUses globals target) args)
    Just entry ->
      sum
        [ if quantity == Q0 then 0 else countRuntimeUses globals target arg
        | (arg, quantity) <- zip args (termBinderQuantities (globalTypeTerm entry) ++ repeat QOmega)
        ]

termBinderQuantities :: Term -> [Quantity]
termBinderQuantities term =
  case term of
    TPi _ quantity _ body -> quantity : termBinderQuantities body
    _ -> []

unfoldApps :: Term -> (Term, [Term])
unfoldApps =
  go []
  where
    go args (TApp fn arg) = go (arg : args) fn
    go args headTerm = (headTerm, args)

countVarUses :: Int -> Term -> Int
countVarUses target term =
  case term of
    TVar index
      | index == target -> 1
      | otherwise -> 0
    TGlobal _ -> 0
    TUniverse _ -> 0
    TU8 _ -> 0
    TU64 _ -> 0
    TAddr _ -> 0
    TStaticBytesPtr _ -> 0
    TStaticCellPtr _ -> 0
    TStaticValuePtr _ -> 0
    TLayout _ fields ->
      sum [countVarUses target value | LayoutFieldInit _ value <- fields]
    TLayoutField _ _ base ->
      countVarUses target base
    TLayoutUpdate _ _ base value ->
      countVarUses target base + countVarUses target value
    TPi _ _ domain codomain ->
      countVarUses target domain + countVarUses (target + 1) codomain
    TLam _ _ body ->
      countVarUses (target + 1) body
    TMatch scrutinee cases ->
      countVarUses target scrutinee + sum [countVarUses (target + length binders) body | CaseTerm _ binders body <- cases]
    TApp fn arg ->
      countVarUses target fn + countVarUses target arg

renderQuantity :: Quantity -> String
renderQuantity quantity =
  case quantity of
    Q0 -> "0"
    Q1 -> "1"
    QOmega -> "omega"

instantiate :: Closure -> Value -> Value
instantiate (Closure globals env body) value =
  eval globals (value : env) body

instantiateMatchClosure :: MatchClosure -> [Value] -> Value
instantiateMatchClosure (MatchClosure _ binders (Closure globals env body)) values =
  if length binders /= length values
    then error "internal error: constructor arm arity mismatch during evaluation"
    else eval globals (reverse values ++ env) body

eval :: Globals -> Env -> Term -> Value
eval globals env term =
  case term of
    TVar index ->
      env !! index
    TGlobal name ->
      case primitiveArity name of
        Just _ -> VPrim name []
        Nothing ->
          case lookupConstructorInfoMaybe globals name of
            Just _ -> VPrim name []
            Nothing ->
              case lookupGlobalMaybe globals name of
                Just entry ->
                  case globalValue entry of
                    Just value -> value
                    Nothing -> VNeutral (NGlobal name)
                Nothing ->
                  VNeutral (NGlobal name)
    TUniverse level ->
      VUniverse level
    TU8 value ->
      VU8 value
    TU64 value ->
      VU64 value
    TAddr value ->
      VAddr value
    TStaticBytesPtr name ->
      VStaticBytesPtr name
    TStaticCellPtr name ->
      VStaticCellPtr name
    TStaticValuePtr name ->
      VStaticValuePtr name
    TLayout name fields ->
      VLayout name [LayoutFieldInit fieldName (eval globals env value) | LayoutFieldInit fieldName value <- fields]
    TLayoutField layoutName fieldName base ->
      vLayoutField globals layoutName fieldName (eval globals env base)
    TLayoutUpdate layoutName fieldName base value ->
      vLayoutUpdate globals layoutName fieldName (eval globals env base) (eval globals env value)
    TPi name quantity domain codomain ->
      VPi name quantity (eval globals env domain) (Closure globals env codomain)
    TLam name quantity body ->
      VLam name quantity (Closure globals env body)
    TMatch scrutinee cases ->
      vMatch globals env (eval globals env scrutinee) cases
    TApp fn arg ->
      vApp globals (eval globals env fn) (eval globals env arg)

vApp :: Globals -> Value -> Value -> Value
vApp globals fn arg =
  case fn of
    VLam _ _ closure -> instantiate closure arg
    VNeutral neutral -> VNeutral (NApp neutral arg)
    VPrim name args -> mkSymbolValue globals name (args ++ [arg])
    _ -> error "internal error: attempted to apply a non-function value"

vMatch :: Globals -> Env -> Value -> [CaseTerm] -> Value
vMatch globals env scrutinee cases =
  case scrutinee of
    VPrim ctorName args ->
      case lookupConstructorInfoMaybe globals ctorName of
        Nothing -> error ("internal error: attempted to match on non-constructor " ++ ctorName)
        Just ctorInfo ->
          case [closure | closure@(MatchClosure caseCtor _ _) <- matchClosures, caseCtor == ctorName] of
            [closure] ->
              instantiateMatchClosure closure (drop (constructorParamCount ctorInfo) args)
            [] ->
              error ("internal error: missing constructor arm during evaluation for " ++ ctorName)
            _ ->
              error ("internal error: duplicate constructor arm during evaluation for " ++ ctorName)
    VNeutral neutral ->
      VNeutral (NMatch neutral matchClosures)
    _ ->
      error "internal error: attempted to match on a non-neutral, non-constructor value"
  where
    matchClosures = [MatchClosure ctorName binders (Closure globals env body) | CaseTerm ctorName binders body <- cases]

vLayoutField :: Globals -> Name -> Name -> Value -> Value
vLayoutField _ layoutName fieldName base =
  case base of
    VLayout _ fields ->
      case [value | LayoutFieldInit candidate value <- fields, candidate == fieldName] of
        [value] -> value
        [] -> error ("internal error: missing field " ++ layoutName ++ "." ++ fieldName ++ " during evaluation")
        _ -> error ("internal error: duplicate field " ++ layoutName ++ "." ++ fieldName ++ " during evaluation")
    VNeutral (NLayoutUpdate updatedLayout updatedField neutral updatedValue)
      | updatedLayout == layoutName && updatedField == fieldName ->
          updatedValue
      | otherwise ->
          VNeutral (NLayoutField layoutName fieldName (NLayoutUpdate updatedLayout updatedField neutral updatedValue))
    VNeutral neutral ->
      VNeutral (NLayoutField layoutName fieldName neutral)
    _ ->
      error ("internal error: attempted to project field " ++ layoutName ++ "." ++ fieldName ++ " from a non-layout value")

vLayoutUpdate :: Globals -> Name -> Name -> Value -> Value -> Value
vLayoutUpdate globals layoutName fieldName base newValue =
  case base of
    VLayout name fields ->
      if name /= layoutName
        then error ("internal error: attempted to update layout " ++ layoutName ++ " from a " ++ name ++ " value")
        else VLayout name (rewriteFields fields)
    VNeutral neutral ->
      VNeutral (NLayoutUpdate layoutName fieldName neutral newValue)
    _ ->
      error ("internal error: attempted to update field " ++ layoutName ++ "." ++ fieldName ++ " on a non-layout value")
  where
    rewriteFields fields =
      if any matchesField fields
        then [if matchesField field then LayoutFieldInit fieldName newValue else field | field <- fields]
        else
          case lookupLayoutInfoMaybe globals layoutName of
            Just layoutInfo ->
              error ("internal error: field " ++ fieldName ++ " missing during layout update for declared layout with fields " ++ show (layoutFieldOrder layoutInfo))
            Nothing ->
              error ("internal error: unknown layout during update " ++ layoutName)
    matchesField (LayoutFieldInit candidate _) = candidate == fieldName

mkSymbolValue :: Globals -> Name -> [Value] -> Value
mkSymbolValue globals name args =
  case primitiveArity name of
    Just arity
      | length args < arity -> VPrim name args
      | length args == arity ->
          case reducePrimitive globals name args of
            Just value -> value
            Nothing -> VPrim name args
      | otherwise ->
          error ("internal error: primitive over-applied: " ++ name)
    Nothing ->
      case lookupConstructorInfoMaybe globals name of
        Just ctorInfo
          | length args <= constructorParamCount ctorInfo + length (constructorFieldTypes ctorInfo) ->
              VPrim name args
          | otherwise ->
              error ("internal error: constructor over-applied: " ++ name)
        Nothing ->
          VNeutral (foldNeutral name args)

foldNeutral :: Name -> [Value] -> Neutral
foldNeutral name args =
  foldl NApp (NGlobal name) args

reducePrimitive :: Globals -> Name -> [Value] -> Maybe Value
reducePrimitive globals name args =
  case (name, args) of
    ("u8-to-u64", [VU8 value]) ->
      Just (VU64 value)
    ("u64-to-u8", [VU64 value]) ->
      Just (VU8 (value .&. 255))
    ("u8-eq", [VU8 left, VU8 right]) ->
      Just (if left == right then VPrim "True" [] else VPrim "False" [])
    ("u64-add", [VU64 left, VU64 right]) ->
      Just (VU64 (left + right))
    ("u64-sub", [VU64 left, VU64 right]) ->
      Just (VU64 (left - right))
    ("u64-mul", [VU64 left, VU64 right]) ->
      Just (VU64 (left * right))
    ("u64-div", [VU64 _left, VU64 0]) ->
      Just (VU64 0)
    ("u64-div", [VU64 left, VU64 right]) ->
      Just (VU64 (left `div` right))
    ("u64-rem", [VU64 left, VU64 0]) ->
      Just (VU64 left)
    ("u64-rem", [VU64 left, VU64 right]) ->
      Just (VU64 (left `rem` right))
    ("u64-and", [VU64 left, VU64 right]) ->
      Just (VU64 (left .&. right))
    ("u64-or", [VU64 left, VU64 right]) ->
      Just (VU64 (left .|. right))
    ("u64-xor", [VU64 left, VU64 right]) ->
      Just (VU64 (xor left right))
    ("u64-shl", [VU64 left, VU64 right]) ->
      Just (VU64 (left `shiftL` finiteShift right))
    ("u64-shr", [VU64 left, VU64 right]) ->
      Just (VU64 (left `shiftR` finiteShift right))
    ("u64-eq", [VU64 left, VU64 right]) ->
      Just (if left == right then VPrim "True" [] else VPrim "False" [])
    ("u64-lt", [VU64 left, VU64 right]) ->
      Just (if left < right then VPrim "True" [] else VPrim "False" [])
    ("u64-lte", [VU64 left, VU64 right]) ->
      Just (if left <= right then VPrim "True" [] else VPrim "False" [])
    ("addr-add", [VAddr base, VU64 offset]) ->
      Just (VAddr (base + offset))
    ("addr-diff", [VAddr hi, VAddr lo]) ->
      Just (VU64 (hi - lo))
    ("addr-eq", [VAddr left, VAddr right]) ->
      Just (if left == right then VPrim "True" [] else VPrim "False" [])
    ("size-of", [ty]) -> do
      (size, _) <- runtimeTypeLayoutValue globals ty
      Just (VU64 size)
    ("align-of", [ty]) -> do
      (_, align) <- runtimeTypeLayoutValue globals ty
      Just (VU64 align)
    ("ptr-to-addr", [_a, VPrim "ptr-from-addr" [_a', addr]]) ->
      Just addr
    ("ptr-add", [a, VPrim "ptr-from-addr" [_a', VAddr base], VU64 offset]) ->
      Just (VPrim "ptr-from-addr" [a, VAddr (base + offset)])
    ("ptr-step", [a, VPrim "ptr-from-addr" [_a', VAddr base], VU64 count]) -> do
      (size, _) <- runtimeTypeLayoutValue globals a
      Just (VPrim "ptr-from-addr" [a, VAddr (base + count * size)])
    ("bind", [_pre, _mid, _post, _a, _b, VPrim "pure" [_innerCap, _innerA, value], k]) ->
      Just (vApp globals k value)
    ("bool-case", [_resultTy, _falseCase, trueCase, VPrim "True" []]) ->
      Just trueCase
    ("bool-case", [_resultTy, falseCase, _trueCase, VPrim "False" []]) ->
      Just falseCase
    ("nat-case", [_resultTy, zeroCase, _succCase, VPrim "Z" []]) ->
      Just zeroCase
    ("nat-case", [_resultTy, _zeroCase, succCase, VPrim "S" [n]]) ->
      Just (vApp globals succCase n)
    ("nat-elim", [_resultTy, zeroCase, _succCase, VPrim "Z" []]) ->
      Just zeroCase
    ("nat-elim", [resultTy, zeroCase, succCase, VPrim "S" [n]]) ->
      let recursive = mkSymbolValue globals "nat-elim" [resultTy, zeroCase, succCase, n]
       in Just (vApp globals (vApp globals succCase n) recursive)
    _ ->
      Nothing

quote :: Int -> Value -> Term
quote depth value =
  case value of
    VUniverse level -> TUniverse level
    VU8 word -> TU8 word
    VU64 word -> TU64 word
    VAddr word -> TAddr word
    VStaticBytesPtr name -> TStaticBytesPtr name
    VStaticCellPtr name -> TStaticCellPtr name
    VStaticValuePtr name -> TStaticValuePtr name
    VLayout name fields ->
      TLayout name [LayoutFieldInit fieldName (quote depth fieldValue) | LayoutFieldInit fieldName fieldValue <- fields]
    VPi name quantity domain closure ->
      let local = VNeutral (NLocal depth)
       in TPi name quantity (quote depth domain) (quote (depth + 1) (instantiate closure local))
    VLam name quantity closure ->
      let local = VNeutral (NLocal depth)
       in TLam name quantity (quote (depth + 1) (instantiate closure local))
    VNeutral neutral ->
      quoteNeutral depth neutral
    VPrim name args ->
      apps (TGlobal name) (map (quote depth) args)

quoteNeutral :: Int -> Neutral -> Term
quoteNeutral depth neutral =
  case neutral of
    NLocal level ->
      TVar (depth - level - 1)
    NGlobal name ->
      TGlobal name
    NApp fn arg ->
      TApp (quoteNeutral depth fn) (quote depth arg)
    NLayoutField layoutName fieldName base ->
      TLayoutField layoutName fieldName (quoteNeutral depth base)
    NLayoutUpdate layoutName fieldName base value ->
      TLayoutUpdate layoutName fieldName (quoteNeutral depth base) (quote depth value)
    NMatch scrutinee cases ->
      TMatch (quoteNeutral depth scrutinee) (map (quoteMatchClosure depth) cases)

quoteMatchClosure :: Int -> MatchClosure -> CaseTerm
quoteMatchClosure depth (MatchClosure ctorName binders (Closure globals env body)) =
  let locals = [VNeutral (NLocal (depth + offset)) | offset <- [0 .. length binders - 1]]
      bodyValue = eval globals (reverse locals ++ env) body
   in CaseTerm ctorName binders (quote (depth + length binders) bodyValue)

apps :: Term -> [Term] -> Term
apps =
  foldl TApp

asDataApplication :: Globals -> Value -> Maybe (Name, [Value])
asDataApplication globals value =
  case value of
    VPrim name args
      | Map.member name (globalsDataInfos globals) -> Just (name, args)
      | otherwise -> Nothing
    VNeutral neutral ->
      go [] neutral
    _ ->
      Nothing
  where
    go args neutral =
      case neutral of
        NGlobal name
          | Map.member name (globalsDataInfos globals) -> Just (name, args)
          | otherwise -> Nothing
        NApp fn arg ->
          go (arg : args) fn
        _ ->
          Nothing

natTypeValue :: Value
natTypeValue = VPrim "Nat" []

u8TypeValue :: Value
u8TypeValue = VPrim "U8" []

u64TypeValue :: Value
u64TypeValue = VPrim "U64" []

addrTypeValue :: Value
addrTypeValue = VPrim "Addr" []

runtimeTypeLayoutValue :: Globals -> Value -> Maybe (Word64, Word64)
runtimeTypeLayoutValue globals value =
  case value of
    VPrim "Unit" [] -> Just (1, 1)
    VPrim "Bool" [] -> Just (1, 1)
    VPrim "Nat" [] -> Just (8, 8)
    VPrim "U8" [] -> Just (1, 1)
    VPrim "U64" [] -> Just (8, 8)
    VPrim "Addr" [] -> Just (8, 8)
    VPrim "Ptr" [_] -> Just (8, 8)
    VPrim name []
      | Just info <- lookupLayoutInfoMaybe globals name ->
          Just (layoutSize info, layoutAlign info)
    VNeutral (NGlobal name)
      | Just info <- lookupLayoutInfoMaybe globals name ->
          Just (layoutSize info, layoutAlign info)
    _ -> Nothing

runtimeTypeLayoutTerm :: Globals -> Term -> Maybe (Word64, Word64)
runtimeTypeLayoutTerm globals term =
  runtimeTypeLayoutValue globals (eval globals [] term)

reifyType :: Int -> Value -> Either String Term
reifyType depth value =
  Right (quote depth value)

primitiveArity :: Name -> Maybe Int
primitiveArity name =
  Map.lookup name primitiveArities

primitiveArities :: Map.Map Name Int
primitiveArities =
  Map.fromList
    [ ("Unit", 0)
    , ("tt", 0)
    , ("Console", 0)
    , ("Heap", 0)
    , ("Eff", 3)
    , ("pure", 3)
    , ("bind", 7)
    , ("Bool", 0)
    , ("True", 0)
    , ("False", 0)
    , ("U8", 0)
    , ("u8-to-u64", 1)
    , ("u64-to-u8", 1)
    , ("u8-eq", 2)
    , ("U64", 0)
    , ("u64-add", 2)
    , ("u64-sub", 2)
    , ("u64-mul", 2)
    , ("u64-div", 2)
    , ("u64-rem", 2)
    , ("u64-and", 2)
    , ("u64-or", 2)
    , ("u64-xor", 2)
    , ("u64-shl", 2)
    , ("u64-shr", 2)
    , ("u64-eq", 2)
    , ("u64-lt", 2)
    , ("u64-lte", 2)
    , ("Addr", 0)
    , ("addr-add", 2)
    , ("addr-diff", 2)
    , ("addr-eq", 2)
    , ("size-of", 1)
    , ("align-of", 1)
    , ("Ptr", 1)
    , ("ptr-from-addr", 2)
    , ("ptr-to-addr", 2)
    , ("ptr-add", 3)
    , ("ptr-step", 3)
    , ("load", 3)
    , ("store", 5)
    , ("load-u64", 2)
    , ("store-u64", 4)
    , ("load-addr", 2)
    , ("store-addr", 4)
    , ("x86-out8", 4)
    , ("x86-in8", 2)
    , ("Nat", 0)
    , ("Z", 0)
    , ("S", 1)
    , ("bool-case", 4)
    , ("nat-case", 4)
    , ("nat-elim", 4)
    ]

builtinsGlobals :: Globals
builtinsGlobals =
  let globals =
        Globals
          { globalsEntries = builtinEntries globals
          , globalsDataInfos = builtinDataInfos
          , globalsConstructorInfos = builtinConstructorInfos
          , globalsLayoutInfos = Map.empty
          , globalsTargetContracts = Map.empty
          , globalsBootContracts = Map.empty
          }
   in globals

builtinEntries :: Globals -> Map.Map Name GlobalEntry
builtinEntries globals =
  Map.fromList
    [ builtinEntry globals "Unit" (TUniverse 0)
    , builtinEntry globals "tt" (TGlobal "Unit")
    , builtinEntry globals "Console" (TUniverse 0)
    , builtinEntry globals "Heap" (TUniverse 0)
    , builtinEntry globals "Eff" effType
    , builtinEntry globals "pure" pureType
    , builtinEntry globals "bind" bindType
    , builtinEntry globals "Bool" (TUniverse 0)
    , builtinEntry globals "True" (TGlobal "Bool")
    , builtinEntry globals "False" (TGlobal "Bool")
    , builtinEntry globals "bool-case" boolCaseType
    , builtinEntry globals "U8" (TUniverse 0)
    , builtinEntry globals "u8-to-u64" u8ToU64Type
    , builtinEntry globals "u64-to-u8" u64ToU8Type
    , builtinEntry globals "u8-eq" u8CompareType
    , builtinEntry globals "U64" (TUniverse 0)
    , builtinEntry globals "u64-add" u64BinaryType
    , builtinEntry globals "u64-sub" u64BinaryType
    , builtinEntry globals "u64-mul" u64BinaryType
    , builtinEntry globals "u64-div" u64BinaryType
    , builtinEntry globals "u64-rem" u64BinaryType
    , builtinEntry globals "u64-and" u64BinaryType
    , builtinEntry globals "u64-or" u64BinaryType
    , builtinEntry globals "u64-xor" u64BinaryType
    , builtinEntry globals "u64-shl" u64BinaryType
    , builtinEntry globals "u64-shr" u64BinaryType
    , builtinEntry globals "u64-eq" u64CompareType
    , builtinEntry globals "u64-lt" u64CompareType
    , builtinEntry globals "u64-lte" u64CompareType
    , builtinEntry globals "Addr" (TUniverse 0)
    , builtinEntry globals "addr-add" addrAddType
    , builtinEntry globals "addr-diff" addrDiffType
    , builtinEntry globals "addr-eq" addrCompareType
    , builtinEntry globals "size-of" sizeOfType
    , builtinEntry globals "align-of" alignOfType
    , builtinEntry globals "Ptr" ptrType
    , builtinEntry globals "ptr-from-addr" ptrFromAddrType
    , builtinEntry globals "ptr-to-addr" ptrToAddrType
    , builtinEntry globals "ptr-add" ptrAddType
    , builtinEntry globals "ptr-step" ptrStepType
    , builtinEntry globals "load" loadType
    , builtinEntry globals "store" storeType
    , builtinEntry globals "load-u64" loadU64Type
    , builtinEntry globals "store-u64" storeU64Type
    , builtinEntry globals "load-addr" loadAddrType
    , builtinEntry globals "store-addr" storeAddrType
    , builtinEntry globals "x86-out8" x86Out8Type
    , builtinEntry globals "x86-in8" x86In8Type
    , builtinEntry globals "Nat" (TUniverse 0)
    , builtinEntry globals "Z" (TGlobal "Nat")
    , builtinEntry globals "S" (TPi "n" Q1 (TGlobal "Nat") (TGlobal "Nat"))
    , builtinEntry globals "nat-case" natCaseType
    , builtinEntry globals "nat-elim" natElimType
    ]

builtinDataInfos :: Map.Map Name DataInfo
builtinDataInfos =
  Map.fromList
    [ ("Unit", DataInfo ["tt"])
    , ("Bool", DataInfo ["True", "False"])
    , ("Nat", DataInfo ["Z", "S"])
    ]

builtinConstructorInfos :: Map.Map Name ConstructorInfo
builtinConstructorInfos =
  Map.fromList
    [ ("tt", ConstructorInfo "tt" "Unit" 0 [])
    , ("True", ConstructorInfo "True" "Bool" 0 [])
    , ("False", ConstructorInfo "False" "Bool" 0 [])
    , ("Z", ConstructorInfo "Z" "Nat" 0 [])
    , ("S", ConstructorInfo "S" "Nat" 0 [TGlobal "Nat"])
    ]

builtinEntry :: Globals -> Name -> Term -> (Name, GlobalEntry)
builtinEntry globals name tyTerm =
  ( name
  , GlobalEntry
      { globalTypeTerm = tyTerm
      , globalTypeValue = eval globals [] tyTerm
      , globalDefinition = Nothing
      , globalValue = Nothing
      , globalExternSymbol = Nothing
      , globalExportSymbol = Nothing
      , globalSectionName = Nothing
      , globalCallingConvention = Nothing
      , globalEntryPoint = False
      }
  )

boolCaseType :: Term
boolCaseType =
  TPi "R" Q0 (TUniverse 0) $
    TPi "falseCase" Q1 (TVar 0) $
      TPi "trueCase" Q1 (TVar 1) $
        TPi "b" Q1 (TGlobal "Bool") $
          TVar 3

natCaseType :: Term
natCaseType =
  TPi "R" Q0 (TUniverse 0) $
    TPi "z" Q1 (TVar 0) $
      TPi "s" Q1 (TPi "n" QOmega (TGlobal "Nat") (TVar 2)) $
        TPi "n" Q1 (TGlobal "Nat") $
          TVar 3

natElimType :: Term
natElimType =
  TPi "R" Q0 (TUniverse 0) $
    TPi "z" Q1 (TVar 0) $
      TPi "s" Q1 (TPi "n" QOmega (TGlobal "Nat") (TPi "rec" QOmega (TVar 2) (TVar 3))) $
        TPi "n" Q1 (TGlobal "Nat") $
          TVar 3

effType :: Term
effType =
  TPi "pre" Q0 (TUniverse 0) $
    TPi "post" Q0 (TUniverse 0) $
      TPi "a" Q0 (TUniverse 0) $
        TUniverse 0

pureType :: Term
pureType =
  TPi "cap" Q0 (TUniverse 0) $
    TPi "a" Q0 (TUniverse 0) $
      TPi "x" Q1 (TVar 0) $
        apps (TGlobal "Eff") [TVar 2, TVar 2, TVar 1]

bindType :: Term
bindType =
  TPi "pre" Q0 (TUniverse 0) $
    TPi "mid" Q0 (TUniverse 0) $
      TPi "post" Q0 (TUniverse 0) $
        TPi "a" Q0 (TUniverse 0) $
          TPi "b" Q0 (TUniverse 0) $
            TPi "m" Q1 (apps (TGlobal "Eff") [TVar 4, TVar 3, TVar 1]) $
              TPi
                "k"
                Q1
                (TPi "x" Q1 (TVar 2) (apps (TGlobal "Eff") [TVar 5, TVar 4, TVar 2]))
                (apps (TGlobal "Eff") [TVar 6, TVar 4, TVar 2])

u64BinaryType :: Term
u64BinaryType =
  TPi "x" Q1 (TGlobal "U64") $
    TPi "y" Q1 (TGlobal "U64") $
      TGlobal "U64"

u64CompareType :: Term
u64CompareType =
  TPi "x" Q1 (TGlobal "U64") $
    TPi "y" Q1 (TGlobal "U64") $
      TGlobal "Bool"

u8ToU64Type :: Term
u8ToU64Type =
  TPi "x" Q1 (TGlobal "U8") $
    TGlobal "U64"

u64ToU8Type :: Term
u64ToU8Type =
  TPi "x" Q1 (TGlobal "U64") $
    TGlobal "U8"

u8CompareType :: Term
u8CompareType =
  TPi "x" Q1 (TGlobal "U8") $
    TPi "y" Q1 (TGlobal "U8") $
      TGlobal "Bool"

addrAddType :: Term
addrAddType =
  TPi "base" Q1 (TGlobal "Addr") $
    TPi "offset" Q1 (TGlobal "U64") $
      TGlobal "Addr"

addrDiffType :: Term
addrDiffType =
  TPi "hi" Q1 (TGlobal "Addr") $
    TPi "lo" Q1 (TGlobal "Addr") $
      TGlobal "U64"

addrCompareType :: Term
addrCompareType =
  TPi "x" Q1 (TGlobal "Addr") $
    TPi "y" Q1 (TGlobal "Addr") $
      TGlobal "Bool"

ptrType :: Term
ptrType =
  TPi "A" Q0 (TUniverse 0) $
    TUniverse 0

ptrFromAddrType :: Term
ptrFromAddrType =
  TPi "A" Q0 (TUniverse 0) $
    TPi "addr" Q1 (TGlobal "Addr") $
      TApp (TGlobal "Ptr") (TVar 1)

ptrToAddrType :: Term
ptrToAddrType =
  TPi "A" Q0 (TUniverse 0) $
    TPi "ptr" Q1 (TApp (TGlobal "Ptr") (TVar 0)) $
      TGlobal "Addr"

ptrAddType :: Term
ptrAddType =
  TPi "A" Q0 (TUniverse 0) $
    TPi "ptr" Q1 (TApp (TGlobal "Ptr") (TVar 0)) $
      TPi "count" Q1 (TGlobal "U64") $
        TApp (TGlobal "Ptr") (TVar 2)

sizeOfType :: Term
sizeOfType =
  TPi "A" Q0 (TUniverse 0) $
    TGlobal "U64"

alignOfType :: Term
alignOfType =
  TPi "A" Q0 (TUniverse 0) $
    TGlobal "U64"

ptrStepType :: Term
ptrStepType =
  TPi "A" Q0 (TUniverse 0) $
    TPi "ptr" Q1 (TApp (TGlobal "Ptr") (TVar 0)) $
      TPi "count" Q1 (TGlobal "U64") $
        TApp (TGlobal "Ptr") (TVar 2)

loadType :: Term
loadType =
  TPi "cap" Q0 (TUniverse 0) $
    TPi "A" Q0 (TUniverse 0) $
      TPi "ptr" Q1 (TApp (TGlobal "Ptr") (TVar 0)) $
        apps (TGlobal "Eff") [TVar 2, TVar 2, TVar 1]

storeType :: Term
storeType =
  TPi "pre" Q0 (TUniverse 0) $
    TPi "post" Q0 (TUniverse 0) $
      TPi "A" Q0 (TUniverse 0) $
        TPi "ptr" Q1 (TApp (TGlobal "Ptr") (TVar 0)) $
          TPi "value" Q1 (TVar 1) $
            apps (TGlobal "Eff") [TVar 4, TVar 3, TGlobal "Unit"]

loadU64Type :: Term
loadU64Type =
  TPi "cap" Q0 (TUniverse 0) $
    TPi "ptr" Q1 (TApp (TGlobal "Ptr") (TGlobal "U64")) $
      apps (TGlobal "Eff") [TVar 1, TVar 1, TGlobal "U64"]

storeU64Type :: Term
storeU64Type =
  TPi "pre" Q0 (TUniverse 0) $
    TPi "post" Q0 (TUniverse 0) $
      TPi "ptr" Q1 (TApp (TGlobal "Ptr") (TGlobal "U64")) $
        TPi "value" Q1 (TGlobal "U64") $
          apps (TGlobal "Eff") [TVar 3, TVar 2, TGlobal "Unit"]

loadAddrType :: Term
loadAddrType =
  TPi "cap" Q0 (TUniverse 0) $
    TPi "ptr" Q1 (TApp (TGlobal "Ptr") (TGlobal "Addr")) $
      apps (TGlobal "Eff") [TVar 1, TVar 1, TGlobal "Addr"]

storeAddrType :: Term
storeAddrType =
  TPi "pre" Q0 (TUniverse 0) $
    TPi "post" Q0 (TUniverse 0) $
      TPi "ptr" Q1 (TApp (TGlobal "Ptr") (TGlobal "Addr")) $
        TPi "value" Q1 (TGlobal "Addr") $
          apps (TGlobal "Eff") [TVar 3, TVar 2, TGlobal "Unit"]

x86Out8Type :: Term
x86Out8Type =
  TPi "pre" Q0 (TUniverse 0) $
    TPi "post" Q0 (TUniverse 0) $
      TPi "port" Q1 (TGlobal "U64") $
        TPi "value" Q1 (TGlobal "U64") $
          apps (TGlobal "Eff") [TVar 3, TVar 2, TGlobal "Unit"]

x86In8Type :: Term
x86In8Type =
  TPi "cap" Q0 (TUniverse 0) $
    TPi "port" Q1 (TGlobal "U64") $
      apps (TGlobal "Eff") [TVar 1, TVar 1, TGlobal "U64"]

finiteShift :: Word64 -> Int
finiteShift amount =
  fromIntegral (amount .&. 63)

shift :: Int -> Int -> Term -> Term
shift cutoff delta term =
  case term of
    TVar index
      | index >= cutoff -> TVar (index + delta)
      | otherwise -> TVar index
    TGlobal name -> TGlobal name
    TUniverse level -> TUniverse level
    TU8 value -> TU8 value
    TU64 value -> TU64 value
    TAddr value -> TAddr value
    TStaticBytesPtr name -> TStaticBytesPtr name
    TStaticCellPtr name -> TStaticCellPtr name
    TStaticValuePtr name -> TStaticValuePtr name
    TLayout name fields ->
      TLayout name [LayoutFieldInit fieldName (shift cutoff delta value) | LayoutFieldInit fieldName value <- fields]
    TLayoutField layoutName fieldName base ->
      TLayoutField layoutName fieldName (shift cutoff delta base)
    TLayoutUpdate layoutName fieldName base value ->
      TLayoutUpdate layoutName fieldName (shift cutoff delta base) (shift cutoff delta value)
    TPi name quantity domain codomain ->
      TPi name quantity (shift cutoff delta domain) (shift (cutoff + 1) delta codomain)
    TLam name quantity body ->
      TLam name quantity (shift (cutoff + 1) delta body)
    TMatch scrutinee cases ->
      TMatch (shift cutoff delta scrutinee) (map shiftCase cases)
      where
        shiftCase (CaseTerm ctorName binders body) =
          CaseTerm ctorName binders (shift (cutoff + length binders) delta body)
    TApp fn arg ->
      TApp (shift cutoff delta fn) (shift cutoff delta arg)

subst :: Int -> Term -> Term -> Term
subst index replacement term =
  case term of
    TVar current
      | current == index -> replacement
      | otherwise -> TVar current
    TGlobal name -> TGlobal name
    TUniverse level -> TUniverse level
    TU8 value -> TU8 value
    TU64 value -> TU64 value
    TAddr value -> TAddr value
    TStaticBytesPtr name -> TStaticBytesPtr name
    TStaticCellPtr name -> TStaticCellPtr name
    TStaticValuePtr name -> TStaticValuePtr name
    TLayout name fields ->
      TLayout name [LayoutFieldInit fieldName (subst index replacement value) | LayoutFieldInit fieldName value <- fields]
    TLayoutField layoutName fieldName base ->
      TLayoutField layoutName fieldName (subst index replacement base)
    TLayoutUpdate layoutName fieldName base value ->
      TLayoutUpdate layoutName fieldName (subst index replacement base) (subst index replacement value)
    TPi name quantity domain codomain ->
      TPi
        name
        quantity
        (subst index replacement domain)
        (subst (index + 1) (shift 0 1 replacement) codomain)
    TLam name quantity body ->
      TLam name quantity (subst (index + 1) (shift 0 1 replacement) body)
    TMatch scrutinee cases ->
      TMatch (subst index replacement scrutinee) (map substCase cases)
      where
        substCase (CaseTerm ctorName binders body) =
          CaseTerm ctorName binders (subst (index + length binders) (shift 0 (length binders) replacement) body)
    TApp fn arg ->
      TApp (subst index replacement fn) (subst index replacement arg)

substTop :: Term -> Term -> Term
substTop replacement body =
  shift 0 (-1) (subst 0 (shift 0 1 replacement) body)

renderCheckedDecl :: CheckedDecl -> String
renderCheckedDecl checked =
  case checked of
    CheckedClaim name ty ->
      name ++ " : " ++ prettyTerm ty
    CheckedDef name ty term ->
      name ++ " : " ++ prettyTerm ty ++ "\n= " ++ prettyTerm term
    CheckedExtern name ty symbol ->
      name ++ " : " ++ prettyTerm ty ++ "\nextern " ++ symbol
    CheckedExport name symbol ->
      name ++ "\nexport " ++ symbol
    CheckedSection name sectionName ->
      name ++ "\nsection " ++ sectionName
    CheckedCallingConvention name conventionName ->
      name ++ "\ncalling-convention " ++ conventionName
    CheckedEntry name ->
      name ++ "\nentry"
    CheckedAbiContract name clauses ->
      name ++ "\nabi-contract " ++ unwords (map renderAbiContractClause clauses)
    CheckedTargetContract target clauses ->
      "target-contract " ++ target ++ " " ++ unwords (map renderTargetContractClause clauses)
    CheckedBootContract name clauses ->
      "boot-contract " ++ name ++ " " ++ unwords (map renderBootContractClause clauses)
    CheckedLayout name size align fields ->
      unlines
        ( [name ++ " : Type", "layout size=" ++ show size ++ " align=" ++ show align]
        ++ [ fieldName ++ " : " ++ prettyTerm fieldTy ++ " @" ++ show fieldOffset
           | CheckedLayoutField fieldName fieldTy fieldOffset <- fields
           ]
        )
    CheckedStaticBytes name values ->
      name
        ++ " : (Ptr U8)\nstatic-bytes len="
        ++ show (length values)
        ++ "\n"
        ++ staticBytesLengthName name
        ++ " : U64"
    CheckedStaticCell name ty ->
      name ++ " : (Ptr " ++ prettyTerm ty ++ ")\nstatic-cell"
    CheckedStaticValue name ty sectionName _value ->
      name ++ " : (Ptr " ++ prettyTerm ty ++ ")\nstatic-value section=" ++ sectionName
    CheckedData name ty ctors ->
      unlines
        ( (name ++ " : " ++ prettyTerm ty)
        : [ctorName ++ " : " ++ prettyTerm ctorTy | CheckedConstructor ctorName ctorTy <- ctors]
        )

renderAbiContractClause :: AbiContractClause -> String
renderAbiContractClause clause =
  case clause of
    AbiContractEntry ->
      "(entry)"
    AbiContractSymbol symbol ->
      "(symbol " ++ symbol ++ ")"
    AbiContractSection sectionName ->
      "(section " ++ sectionName ++ ")"
    AbiContractCallingConvention conventionName ->
      "(calling-convention " ++ conventionName ++ ")"
    AbiContractFreestanding ->
      "(freestanding)"

renderTargetContractClause :: TargetContractClause -> String
renderTargetContractClause clause =
  case clause of
    TargetContractFormat formatName ->
      "(format " ++ formatName ++ ")"
    TargetContractArch archName ->
      "(arch " ++ archName ++ ")"
    TargetContractAbi abiName ->
      "(abi " ++ abiName ++ ")"
    TargetContractEntry entryName ->
      "(entry " ++ entryName ++ ")"
    TargetContractSymbol symbol ->
      "(symbol " ++ symbol ++ ")"
    TargetContractSection sectionName ->
      "(section " ++ sectionName ++ ")"
    TargetContractCallingConvention conventionName ->
      "(calling-convention " ++ conventionName ++ ")"
    TargetContractEntryAddress address ->
      "(entry-address " ++ show address ++ ")"
    TargetContractRedZone mode ->
      "(red-zone " ++ mode ++ ")"
    TargetContractFreestanding ->
      "(freestanding)"

renderBootContractClause :: BootContractClause -> String
renderBootContractClause clause =
  case clause of
    BootContractProtocol protocol ->
      "(protocol " ++ protocol ++ ")"
    BootContractTarget target ->
      "(target " ++ target ++ ")"
    BootContractEntry entryName ->
      "(entry " ++ entryName ++ ")"
    BootContractKernelPath path ->
      "(kernel-path " ++ path ++ ")"
    BootContractConfigPath path ->
      "(config-path " ++ path ++ ")"
    BootContractFreestanding ->
      "(freestanding)"
