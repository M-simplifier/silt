module Silt.Codegen.C
  ( emitDefinitionC
  , emitDefinitionsC
  , emitDefinitionFreestandingC
  , emitDefinitionsFreestandingC
  ) where

import Data.Char (isAlphaNum)
import Data.List (intercalate)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Word (Word64)
import Silt.Elab (CheckedDecl (..), CheckedLayoutField (..), checkProgram, normalizeDefinitionTerm)
import Silt.Syntax

data CType
  = CUnit
  | CNat
  | CU8
  | CU64
  | CAddr
  | CPtr
  | CBool
  | CLayout Name
  deriving (Eq, Show)

data RuntimeBinding
  = ErasedBinding
  | RuntimeBinding String CType
  deriving (Eq, Show)

data CStmt
  = CDecl CType String (Maybe String)
  | CAssign String String
  | CIf String [CStmt] [CStmt]
  | CFor String [CStmt]
  | CRaw String
  deriving (Eq, Show)

data PiBinder = PiBinder Name Quantity Term
  deriving (Eq, Show)

data LamBinder = LamBinder Name Quantity
  deriving (Eq, Show)

data ExternSpec = ExternSpec
  { externInternalName :: Name
  , externSymbolName :: Name
  , externTypeTerm :: Term
  }
  deriving (Eq, Show)

data ExportSpec = ExportSpec
  { exportInternalName :: Name
  , exportSymbolName :: Name
  }
  deriving (Eq, Show)

data SectionSpec = SectionSpec
  { sectionInternalName :: Name
  , sectionName :: Name
  }
  deriving (Eq, Show)

data CallingConventionSpec = CallingConventionSpec
  { callingConventionInternalName :: Name
  , callingConventionName :: Name
  }
  deriving (Eq, Show)

data EntrySpec = EntrySpec
  { entryInternalName :: Name
  }
  deriving (Eq, Show)

data LayoutSpec = LayoutSpec
  { layoutTypeName :: Name
  , layoutTypeSize :: Word64
  , layoutTypeAlign :: Word64
  , layoutTypeFields :: [LayoutFieldSpec]
  }
  deriving (Eq, Show)

data LayoutFieldSpec = LayoutFieldSpec
  { layoutFieldSpecName :: Name
  , layoutFieldSpecType :: Term
  , layoutFieldSpecOffset :: Word64
  }
  deriving (Eq, Show)

data CodegenEnv = CodegenEnv
  { codegenExterns :: [ExternSpec]
  , codegenExports :: [ExportSpec]
  , codegenSections :: [SectionSpec]
  , codegenCallingConventions :: [CallingConventionSpec]
  , codegenEntries :: [EntrySpec]
  , codegenLayouts :: [LayoutSpec]
  }
  deriving (Eq, Show)

data CodegenMode
  = HostedC
  | FreestandingC
  deriving (Eq, Show)

emitDefinitionC :: Program -> Name -> Either String String
emitDefinitionC =
  emitDefinitionWith HostedC

emitDefinitionFreestandingC :: Program -> Name -> Either String String
emitDefinitionFreestandingC =
  emitDefinitionWith FreestandingC

emitDefinitionsC :: Program -> [Name] -> Either String String
emitDefinitionsC =
  emitDefinitionsWith HostedC

emitDefinitionsFreestandingC :: Program -> [Name] -> Either String String
emitDefinitionsFreestandingC =
  emitDefinitionsWith FreestandingC

emitDefinitionWith :: CodegenMode -> Program -> Name -> Either String String
emitDefinitionWith mode program name = do
  checked <- checkProgram program
  let codegenEnv = codegenSpecs checked
  (ty, nf) <- normalizeDefinitionTerm program name
  let usedExterns = filterUsedExterns codegenEnv [ty, nf]
  prototypes <- traverse (renderExternPrototype codegenEnv) usedExterns
  lines' <- renderDefinitionLines codegenEnv name ty nf
  pure (renderTranslationUnit mode (codegenLayouts codegenEnv) prototypes [lines'])

emitDefinitionsWith :: CodegenMode -> Program -> [Name] -> Either String String
emitDefinitionsWith mode program names = do
  checked <- checkProgram program
  let codegenEnv = codegenSpecs checked
  defs <-
    mapM
      (\name -> do
          (ty, nf) <- normalizeDefinitionTerm program name
          pure (name, ty, nf)
      )
      names
  let usedExterns = filterUsedExterns codegenEnv [term | (_, ty, nf) <- defs, term <- [ty, nf]]
  prototypes <- traverse (renderExternPrototype codegenEnv) usedExterns
  lines' <-
    mapM
      (\(name, ty, nf) ->
          renderDefinitionLines codegenEnv name ty nf
      )
      defs
  pure (renderTranslationUnit mode (codegenLayouts codegenEnv) prototypes lines')

renderDefinitionLines :: CodegenEnv -> Name -> Term -> Term -> Either String [String]
renderDefinitionLines codegenEnv name ty nf = do
  let piBinders = flattenPis ty
  let (lamBinders, body) = flattenLams nf
  if length piBinders /= length lamBinders
    then Left "normalized term does not match its Pi-typed arity"
    else do
      let binderPairs = zip piBinders lamBinders
      resultType <- compileRuntimeType codegenEnv (resultTypeOf ty)
      (params, env) <- buildSignatureEnv codegenEnv binderPairs
      (_, stmts, resultExpr) <- compileExpr codegenEnv 0 (reverse env) resultType body
      let symbolName = definitionSymbol codegenEnv name
      attrs <- definitionAttributes codegenEnv name
      Right
        ( [ attrs
                ++ cTypeName resultType
                ++ " "
                ++ symbolName
                ++ "("
                ++ renderParams params
                ++ ") {"
          ]
            ++ concatMap (renderStmt 1) (stmts ++ [CAssign "__result" resultExpr])
            ++ ["}"]
        )

renderTranslationUnit :: CodegenMode -> [LayoutSpec] -> [String] -> [[String]] -> String
renderTranslationUnit mode layouts prototypes definitions =
  unlines
    ( preludeLines mode
        ++ layoutLines
        ++ (if null layoutLines then [] else [""])
        ++ prototypes
        ++ (if null prototypes then [] else [""])
        ++ intercalate [""] definitions
    )
  where
    layoutLines = concatMap renderLayoutTypedef layouts

buildSignatureEnv :: CodegenEnv -> [(PiBinder, LamBinder)] -> Either String ([(CType, String)], [RuntimeBinding])
buildSignatureEnv codegenEnv =
  go []
  where
    go params [] = Right (reverse params, [])
    go params ((PiBinder piName piQuantity piType, LamBinder lamName lamQuantity) : rest) = do
      if piQuantity /= lamQuantity
        then Left ("normalized lambda quantity for " ++ lamName ++ " does not match its type")
        else
          case piQuantity of
            Q0 -> do
              (params', env) <- go params rest
              Right (params', ErasedBinding : env)
            _ -> do
              cType <- compileRuntimeType codegenEnv piType
              let varName = cName (if null lamName then piName else lamName)
              (params', env) <- go ((cType, varName) : params) rest
              Right (params', RuntimeBinding varName cType : env)

compileExpr :: CodegenEnv -> Int -> [RuntimeBinding] -> CType -> Term -> Either String (Int, [CStmt], String)
compileExpr codegenEnv fresh env expected term =
  case term of
    TVar index ->
      case lookupBinding env index of
        ErasedBinding ->
          Left "erased variable reached runtime code generation"
        RuntimeBinding name actualType ->
          if actualType == expected
            then Right (fresh, [], name)
            else
              Left
                ( "runtime type mismatch for variable "
                    ++ name
                    ++ ": expected "
                    ++ cTypeName expected
                    ++ ", got "
                    ++ cTypeName actualType
                )
    TU64 value ->
      expectType expected CU64 "u64 literal" >>
      Right (fresh, [], show value ++ "ULL")
    TU8 value ->
      expectType expected CU8 "u8 literal" >>
      Right (fresh, [], "((uint8_t)" ++ show value ++ "u)")
    TAddr value ->
      expectType expected CAddr "addr literal" >>
      Right (fresh, [], "((uintptr_t)" ++ show value ++ "ULL)")
    TLayout layoutName fields ->
      compileLayoutLiteral codegenEnv fresh env expected layoutName fields
    TLayoutField layoutName fieldName base ->
      compileLayoutFieldAccess codegenEnv fresh env expected layoutName fieldName base
    TLayoutUpdate layoutName fieldName base value ->
      compileLayoutFieldUpdate codegenEnv fresh env expected layoutName fieldName base value
    _ ->
      compileApplication codegenEnv fresh env expected term

compileLayoutLiteral ::
     CodegenEnv
  -> Int
  -> [RuntimeBinding]
  -> CType
  -> Name
  -> [LayoutFieldInit Term]
  -> Either String (Int, [CStmt], String)
compileLayoutLiteral codegenEnv fresh env expected layoutName fields = do
  expectType expected (CLayout layoutName) "layout literal"
  layoutSpec <-
    case lookupLayoutSpec codegenEnv layoutName of
      Nothing -> Left ("unknown layout for C backend: " ++ layoutName)
      Just spec -> Right spec
  let expectedFields = layoutTypeFields layoutSpec
  if map layoutFieldSpecName expectedFields /= [fieldName | LayoutFieldInit fieldName _ <- fields]
    then Left ("layout literal field order mismatch during C code generation for " ++ layoutName)
    else do
      let (fresh1, tempName) = freshVar (cName layoutName) fresh
      (fresh2, fieldStmts) <- compileLayoutFieldStores codegenEnv fresh1 env tempName (zip expectedFields fields)
      Right
        ( fresh2
        , CDecl (CLayout layoutName) tempName (Just "{0}") : fieldStmts
        , tempName
        )

compileLayoutFieldStores ::
     CodegenEnv
  -> Int
  -> [RuntimeBinding]
  -> String
  -> [(LayoutFieldSpec, LayoutFieldInit Term)]
  -> Either String (Int, [CStmt])
compileLayoutFieldStores codegenEnv =
  go []
  where
    go acc fresh _ _ [] =
      Right (fresh, acc)
    go acc fresh env tempName ((fieldSpec, LayoutFieldInit fieldName valueTerm) : rest)
      | layoutFieldSpecName fieldSpec /= fieldName =
          Left ("internal error: mismatched layout field " ++ fieldName ++ " during C code generation")
      | otherwise = do
          cType <- compileRuntimeType codegenEnv (layoutFieldSpecType fieldSpec)
          (fresh1, valueStmts, valueExpr) <- compileExpr codegenEnv fresh env cType valueTerm
          let fieldAddrExpr =
                "((uintptr_t)&" ++ tempName ++ " + " ++ show (layoutFieldSpecOffset fieldSpec) ++ "ULL)"
          let assignStmt = CAssign (derefExpr cType fieldAddrExpr) valueExpr
          go (acc ++ valueStmts ++ [assignStmt]) fresh1 env tempName rest

compileLayoutFieldAccess ::
     CodegenEnv
  -> Int
  -> [RuntimeBinding]
  -> CType
  -> Name
  -> Name
  -> Term
  -> Either String (Int, [CStmt], String)
compileLayoutFieldAccess codegenEnv fresh env expected layoutName fieldName base = do
  layoutSpec <-
    case lookupLayoutSpec codegenEnv layoutName of
      Nothing -> Left ("unknown layout for C backend: " ++ layoutName)
      Just spec -> Right spec
  fieldSpec <-
    case [spec | spec <- layoutTypeFields layoutSpec, layoutFieldSpecName spec == fieldName] of
      [spec] -> Right spec
      [] -> Left ("unknown layout field for C backend: " ++ layoutName ++ "." ++ fieldName)
      _ -> Left ("duplicate layout field in C backend metadata: " ++ layoutName ++ "." ++ fieldName)
  fieldType <- compileRuntimeType codegenEnv (layoutFieldSpecType fieldSpec)
  expectType expected fieldType "field"
  (fresh1, baseStmts, baseExpr) <- compileExpr codegenEnv fresh env (CLayout layoutName) base
  let (fresh2, tempName) = freshVar (cName fieldName) fresh1
  let fieldAddrExpr =
        "((uintptr_t)&" ++ tempName ++ " + " ++ show (layoutFieldSpecOffset fieldSpec) ++ "ULL)"
  Right
    ( fresh2
    , baseStmts ++ [CDecl (CLayout layoutName) tempName (Just baseExpr)]
    , derefExpr fieldType fieldAddrExpr
    )

compileLayoutFieldUpdate ::
     CodegenEnv
  -> Int
  -> [RuntimeBinding]
  -> CType
  -> Name
  -> Name
  -> Term
  -> Term
  -> Either String (Int, [CStmt], String)
compileLayoutFieldUpdate codegenEnv fresh env expected layoutName fieldName base value = do
  expectType expected (CLayout layoutName) "with-field"
  layoutSpec <-
    case lookupLayoutSpec codegenEnv layoutName of
      Nothing -> Left ("unknown layout for C backend: " ++ layoutName)
      Just spec -> Right spec
  fieldSpec <-
    case [spec | spec <- layoutTypeFields layoutSpec, layoutFieldSpecName spec == fieldName] of
      [spec] -> Right spec
      [] -> Left ("unknown layout field for C backend: " ++ layoutName ++ "." ++ fieldName)
      _ -> Left ("duplicate layout field in C backend metadata: " ++ layoutName ++ "." ++ fieldName)
  (fresh1, baseStmts, baseExpr) <- compileExpr codegenEnv fresh env (CLayout layoutName) base
  fieldType <- compileRuntimeType codegenEnv (layoutFieldSpecType fieldSpec)
  (fresh2, valueStmts, valueExpr) <- compileExpr codegenEnv fresh1 env fieldType value
  let (fresh3, tempName) = freshVar (cName layoutName) fresh2
  let fieldAddrExpr =
        "((uintptr_t)&" ++ tempName ++ " + " ++ show (layoutFieldSpecOffset fieldSpec) ++ "ULL)"
  Right
    ( fresh3
    , baseStmts
        ++ valueStmts
        ++ [ CDecl (CLayout layoutName) tempName (Just baseExpr)
           , CAssign (derefExpr fieldType fieldAddrExpr) valueExpr
           ]
    , tempName
    )

compileApplication :: CodegenEnv -> Int -> [RuntimeBinding] -> CType -> Term -> Either String (Int, [CStmt], String)
compileApplication codegenEnv fresh env expected term =
  case collectApps term of
    (TGlobal "Z", []) ->
      expectType expected CNat "Z" >>
      Right (fresh, [], "0ULL")
    (TGlobal "tt", []) ->
      expectType expected CUnit "tt" >>
      Right (fresh, [], "0u")
    (TGlobal "True", []) ->
      expectType expected CBool "True" >>
      Right (fresh, [], "1u")
    (TGlobal "False", []) ->
      expectType expected CBool "False" >>
      Right (fresh, [], "0u")
    (TGlobal "S", [arg]) -> do
      expectType expected CNat "S"
      (fresh', stmts, expr) <- compileExpr codegenEnv fresh env CNat arg
      Right (fresh', stmts, "(" ++ expr ++ " + 1ULL)")
    (TGlobal "u8-to-u64", [value]) -> do
      expectType expected CU64 "u8-to-u64"
      (fresh1, valueStmts, valueExpr) <- compileExpr codegenEnv fresh env CU8 value
      Right (fresh1, valueStmts, "((uint64_t)" ++ valueExpr ++ ")")
    (TGlobal "u64-to-u8", [value]) -> do
      expectType expected CU8 "u64-to-u8"
      (fresh1, valueStmts, valueExpr) <- compileExpr codegenEnv fresh env CU64 value
      Right (fresh1, valueStmts, "((uint8_t)(" ++ valueExpr ++ "))")
    (TGlobal "u8-eq", [left, right]) -> do
      expectType expected CBool "u8-eq"
      (fresh1, leftStmts, leftExpr) <- compileExpr codegenEnv fresh env CU8 left
      (fresh2, rightStmts, rightExpr) <- compileExpr codegenEnv fresh1 env CU8 right
      Right (fresh2, leftStmts ++ rightStmts, "((" ++ leftExpr ++ " == " ++ rightExpr ++ ") ? 1u : 0u)")
    (TGlobal "u64-add", [left, right]) -> do
      expectType expected CU64 "u64-add"
      (fresh1, leftStmts, leftExpr) <- compileExpr codegenEnv fresh env CU64 left
      (fresh2, rightStmts, rightExpr) <- compileExpr codegenEnv fresh1 env CU64 right
      Right (fresh2, leftStmts ++ rightStmts, "(" ++ leftExpr ++ " + " ++ rightExpr ++ ")")
    (TGlobal "u64-sub", [left, right]) -> do
      expectType expected CU64 "u64-sub"
      (fresh1, leftStmts, leftExpr) <- compileExpr codegenEnv fresh env CU64 left
      (fresh2, rightStmts, rightExpr) <- compileExpr codegenEnv fresh1 env CU64 right
      Right (fresh2, leftStmts ++ rightStmts, "(" ++ leftExpr ++ " - " ++ rightExpr ++ ")")
    (TGlobal "u64-mul", [left, right]) -> do
      expectType expected CU64 "u64-mul"
      (fresh1, leftStmts, leftExpr) <- compileExpr codegenEnv fresh env CU64 left
      (fresh2, rightStmts, rightExpr) <- compileExpr codegenEnv fresh1 env CU64 right
      Right (fresh2, leftStmts ++ rightStmts, "(" ++ leftExpr ++ " * " ++ rightExpr ++ ")")
    (TGlobal "u64-div", [left, right]) -> do
      expectType expected CU64 "u64-div"
      (fresh1, leftStmts, leftExpr) <- compileExpr codegenEnv fresh env CU64 left
      (fresh2, rightStmts, rightExpr) <- compileExpr codegenEnv fresh1 env CU64 right
      Right
        ( fresh2
        , leftStmts ++ rightStmts
        , "((" ++ rightExpr ++ " == 0ULL) ? 0ULL : (" ++ leftExpr ++ " / " ++ rightExpr ++ "))"
        )
    (TGlobal "u64-rem", [left, right]) -> do
      expectType expected CU64 "u64-rem"
      (fresh1, leftStmts, leftExpr) <- compileExpr codegenEnv fresh env CU64 left
      (fresh2, rightStmts, rightExpr) <- compileExpr codegenEnv fresh1 env CU64 right
      Right
        ( fresh2
        , leftStmts ++ rightStmts
        , "((" ++ rightExpr ++ " == 0ULL) ? " ++ leftExpr ++ " : (" ++ leftExpr ++ " % " ++ rightExpr ++ "))"
        )
    (TGlobal "u64-and", [left, right]) -> do
      expectType expected CU64 "u64-and"
      (fresh1, leftStmts, leftExpr) <- compileExpr codegenEnv fresh env CU64 left
      (fresh2, rightStmts, rightExpr) <- compileExpr codegenEnv fresh1 env CU64 right
      Right (fresh2, leftStmts ++ rightStmts, "(" ++ leftExpr ++ " & " ++ rightExpr ++ ")")
    (TGlobal "u64-or", [left, right]) -> do
      expectType expected CU64 "u64-or"
      (fresh1, leftStmts, leftExpr) <- compileExpr codegenEnv fresh env CU64 left
      (fresh2, rightStmts, rightExpr) <- compileExpr codegenEnv fresh1 env CU64 right
      Right (fresh2, leftStmts ++ rightStmts, "(" ++ leftExpr ++ " | " ++ rightExpr ++ ")")
    (TGlobal "u64-xor", [left, right]) -> do
      expectType expected CU64 "u64-xor"
      (fresh1, leftStmts, leftExpr) <- compileExpr codegenEnv fresh env CU64 left
      (fresh2, rightStmts, rightExpr) <- compileExpr codegenEnv fresh1 env CU64 right
      Right (fresh2, leftStmts ++ rightStmts, "(" ++ leftExpr ++ " ^ " ++ rightExpr ++ ")")
    (TGlobal "u64-shl", [left, right]) -> do
      expectType expected CU64 "u64-shl"
      (fresh1, leftStmts, leftExpr) <- compileExpr codegenEnv fresh env CU64 left
      (fresh2, rightStmts, rightExpr) <- compileExpr codegenEnv fresh1 env CU64 right
      Right (fresh2, leftStmts ++ rightStmts, "(" ++ leftExpr ++ " << (" ++ rightExpr ++ " & 63ULL))")
    (TGlobal "u64-shr", [left, right]) -> do
      expectType expected CU64 "u64-shr"
      (fresh1, leftStmts, leftExpr) <- compileExpr codegenEnv fresh env CU64 left
      (fresh2, rightStmts, rightExpr) <- compileExpr codegenEnv fresh1 env CU64 right
      Right (fresh2, leftStmts ++ rightStmts, "(" ++ leftExpr ++ " >> (" ++ rightExpr ++ " & 63ULL))")
    (TGlobal "u64-eq", [left, right]) -> do
      expectType expected CBool "u64-eq"
      (fresh1, leftStmts, leftExpr) <- compileExpr codegenEnv fresh env CU64 left
      (fresh2, rightStmts, rightExpr) <- compileExpr codegenEnv fresh1 env CU64 right
      Right (fresh2, leftStmts ++ rightStmts, "((" ++ leftExpr ++ " == " ++ rightExpr ++ ") ? 1u : 0u)")
    (TGlobal "u64-lt", [left, right]) -> do
      expectType expected CBool "u64-lt"
      (fresh1, leftStmts, leftExpr) <- compileExpr codegenEnv fresh env CU64 left
      (fresh2, rightStmts, rightExpr) <- compileExpr codegenEnv fresh1 env CU64 right
      Right (fresh2, leftStmts ++ rightStmts, "((" ++ leftExpr ++ " < " ++ rightExpr ++ ") ? 1u : 0u)")
    (TGlobal "u64-lte", [left, right]) -> do
      expectType expected CBool "u64-lte"
      (fresh1, leftStmts, leftExpr) <- compileExpr codegenEnv fresh env CU64 left
      (fresh2, rightStmts, rightExpr) <- compileExpr codegenEnv fresh1 env CU64 right
      Right (fresh2, leftStmts ++ rightStmts, "((" ++ leftExpr ++ " <= " ++ rightExpr ++ ") ? 1u : 0u)")
    (TGlobal "addr-add", [base, offset]) -> do
      expectType expected CAddr "addr-add"
      (fresh1, baseStmts, baseExpr) <- compileExpr codegenEnv fresh env CAddr base
      (fresh2, offsetStmts, offsetExpr) <- compileExpr codegenEnv fresh1 env CU64 offset
      Right (fresh2, baseStmts ++ offsetStmts, "((uintptr_t)(" ++ baseExpr ++ " + " ++ offsetExpr ++ "))")
    (TGlobal "addr-diff", [hi, lo]) -> do
      expectType expected CU64 "addr-diff"
      (fresh1, hiStmts, hiExpr) <- compileExpr codegenEnv fresh env CAddr hi
      (fresh2, loStmts, loExpr) <- compileExpr codegenEnv fresh1 env CAddr lo
      Right (fresh2, hiStmts ++ loStmts, "((uint64_t)(" ++ hiExpr ++ " - " ++ loExpr ++ "))")
    (TGlobal "addr-eq", [left, right]) -> do
      expectType expected CBool "addr-eq"
      (fresh1, leftStmts, leftExpr) <- compileExpr codegenEnv fresh env CAddr left
      (fresh2, rightStmts, rightExpr) <- compileExpr codegenEnv fresh1 env CAddr right
      Right (fresh2, leftStmts ++ rightStmts, "((" ++ leftExpr ++ " == " ++ rightExpr ++ ") ? 1u : 0u)")
    (TGlobal "size-of", [ty]) -> do
      expectType expected CU64 "size-of"
      (size, _) <- runtimeTypeLayoutTerm codegenEnv ty
      Right (fresh, [], show size ++ "ULL")
    (TGlobal "align-of", [ty]) -> do
      expectType expected CU64 "align-of"
      (_, align) <- runtimeTypeLayoutTerm codegenEnv ty
      Right (fresh, [], show align ++ "ULL")
    (TGlobal "ptr-from-addr", [_ty, addr]) -> do
      expectType expected CPtr "ptr-from-addr"
      (fresh1, addrStmts, addrExpr) <- compileExpr codegenEnv fresh env CAddr addr
      Right (fresh1, addrStmts, "((uintptr_t)" ++ addrExpr ++ ")")
    (TGlobal "ptr-to-addr", [_ty, ptr]) -> do
      expectType expected CAddr "ptr-to-addr"
      (fresh1, ptrStmts, ptrExpr) <- compileExpr codegenEnv fresh env CPtr ptr
      Right (fresh1, ptrStmts, "((uintptr_t)" ++ ptrExpr ++ ")")
    (TGlobal "ptr-add", [_ty, ptr, count]) -> do
      expectType expected CPtr "ptr-add"
      (fresh1, ptrStmts, ptrExpr) <- compileExpr codegenEnv fresh env CPtr ptr
      (fresh2, countStmts, countExpr) <- compileExpr codegenEnv fresh1 env CU64 count
      Right (fresh2, ptrStmts ++ countStmts, "((uintptr_t)(" ++ ptrExpr ++ " + " ++ countExpr ++ "))")
    (TGlobal "ptr-step", [ty, ptr, count]) -> do
      expectType expected CPtr "ptr-step"
      (size, _) <- runtimeTypeLayoutTerm codegenEnv ty
      (fresh1, ptrStmts, ptrExpr) <- compileExpr codegenEnv fresh env CPtr ptr
      (fresh2, countStmts, countExpr) <- compileExpr codegenEnv fresh1 env CU64 count
      Right
        ( fresh2
        , ptrStmts ++ countStmts
        , "((uintptr_t)(" ++ ptrExpr ++ " + (" ++ countExpr ++ " * " ++ show size ++ "ULL)))"
        )
    (TGlobal "load", [_cap, ty, ptr]) -> do
      actualType <- compileRuntimeType codegenEnv ty
      expectType expected actualType "load"
      (fresh1, ptrStmts, ptrExpr) <- compileExpr codegenEnv fresh env CPtr ptr
      Right (fresh1, ptrStmts, derefExpr actualType ptrExpr)
    (TGlobal "store", [_pre, _post, ty, ptr, value]) -> do
      valueType <- compileRuntimeType codegenEnv ty
      expectType expected CUnit "store"
      (fresh1, ptrStmts, ptrExpr) <- compileExpr codegenEnv fresh env CPtr ptr
      (fresh2, valueStmts, valueExpr) <- compileExpr codegenEnv fresh1 env valueType value
      Right
        ( fresh2
        , ptrStmts ++ valueStmts ++ [CAssign (derefExpr valueType ptrExpr) valueExpr]
        , "0u"
        )
    (TGlobal "load-u64", [_cap, ptr]) -> do
      expectType expected CU64 "load-u64"
      (fresh1, ptrStmts, ptrExpr) <- compileExpr codegenEnv fresh env CPtr ptr
      Right (fresh1, ptrStmts, derefExpr CU64 ptrExpr)
    (TGlobal "store-u64", [_pre, _post, ptr, value]) -> do
      expectType expected CUnit "store-u64"
      (fresh1, ptrStmts, ptrExpr) <- compileExpr codegenEnv fresh env CPtr ptr
      (fresh2, valueStmts, valueExpr) <- compileExpr codegenEnv fresh1 env CU64 value
      Right
        ( fresh2
        , ptrStmts ++ valueStmts ++ [CAssign (derefExpr CU64 ptrExpr) valueExpr]
        , "0u"
        )
    (TGlobal "load-addr", [_cap, ptr]) -> do
      expectType expected CAddr "load-addr"
      (fresh1, ptrStmts, ptrExpr) <- compileExpr codegenEnv fresh env CPtr ptr
      Right (fresh1, ptrStmts, derefExpr CAddr ptrExpr)
    (TGlobal "store-addr", [_pre, _post, ptr, value]) -> do
      expectType expected CUnit "store-addr"
      (fresh1, ptrStmts, ptrExpr) <- compileExpr codegenEnv fresh env CPtr ptr
      (fresh2, valueStmts, valueExpr) <- compileExpr codegenEnv fresh1 env CAddr value
      Right
        ( fresh2
        , ptrStmts ++ valueStmts ++ [CAssign (derefExpr CAddr ptrExpr) valueExpr]
        , "0u"
        )
    (TGlobal "x86-out8", [_pre, _post, port, value]) -> do
      expectType expected CUnit "x86-out8"
      (fresh1, portStmts, portExpr) <- compileExpr codegenEnv fresh env CU64 port
      (fresh2, valueStmts, valueExpr) <- compileExpr codegenEnv fresh1 env CU64 value
      Right
        ( fresh2
        , portStmts
            ++ valueStmts
            ++ [ CRaw
                   ( "__asm__ volatile (\"outb %0, %1\" : : \"a\"((uint8_t)("
                       ++ valueExpr
                       ++ ")), \"Nd\"((uint16_t)("
                       ++ portExpr
                       ++ ")));"
                   )
               ]
        , "0u"
        )
    (TGlobal "x86-in8", [_cap, port]) -> do
      expectType expected CU64 "x86-in8"
      (fresh1, portStmts, portExpr) <- compileExpr codegenEnv fresh env CU64 port
      let (fresh2, temp) = freshVar "in8" fresh1
      Right
        ( fresh2
        , portStmts
            ++ [ CDecl CBool temp Nothing
               , CRaw
                   ( "__asm__ volatile (\"inb %1, %0\" : \"=a\"("
                       ++ temp
                       ++ ") : \"Nd\"((uint16_t)("
                       ++ portExpr
                       ++ ")));"
                   )
               ]
        , "((uint64_t)" ++ temp ++ ")"
        )
    (TGlobal "pure", [_cap, _a, value]) ->
      compileExpr codegenEnv fresh env expected value
    (TGlobal "bind", [_pre, _mid, _post, aTy, _bTy, action, k]) -> do
      (binderName, binderQuantity, body) <- expectUnaryLambda k
      if binderQuantity == Q0
        then Left "bind continuation binder cannot be erased in C codegen"
        else do
          actionType <- compileRuntimeType codegenEnv aTy
          (fresh1, actionStmts, actionExpr) <- compileExpr codegenEnv fresh env actionType action
          if countVarUses 0 body == 0
            then do
              (fresh2, bodyStmts, bodyExpr) <- compileExpr codegenEnv fresh1 (ErasedBinding : env) expected body
              Right
                ( fresh2
                , actionStmts ++ [CRaw ("(void)(" ++ actionExpr ++ ");")] ++ bodyStmts
                , bodyExpr
                )
            else do
              let (fresh2, actionTemp) = freshVar (cName binderName) fresh1
              (fresh3, bodyStmts, bodyExpr) <-
                compileExpr codegenEnv fresh2 (RuntimeBinding actionTemp actionType : env) expected body
              Right
                ( fresh3
                , actionStmts ++ [CDecl actionType actionTemp (Just actionExpr)] ++ bodyStmts
                , bodyExpr
                )
    (TGlobal "bool-case", [resultTy, falseCase, trueCase, scrutinee]) -> do
      actualResult <- compileRuntimeType codegenEnv resultTy
      expectType expected actualResult "bool-case"
      (fresh1, scrutineeStmts, scrutineeExpr) <- compileExpr codegenEnv fresh env CBool scrutinee
      (fresh2, falseStmts, falseExpr) <- compileExpr codegenEnv fresh1 env expected falseCase
      (fresh3, trueStmts, trueExpr) <- compileExpr codegenEnv fresh2 env expected trueCase
      let (fresh4, temp) = freshVar "result" fresh3
      let stmts =
            scrutineeStmts
              ++ [ CDecl expected temp Nothing
                 , CIf
                     scrutineeExpr
                     (trueStmts ++ [CAssign temp trueExpr])
                     (falseStmts ++ [CAssign temp falseExpr])
                 ]
      Right (fresh4, stmts, temp)
    (TGlobal "nat-case", [resultTy, zeroCase, succCase, scrutinee]) -> do
      actualResult <- compileRuntimeType codegenEnv resultTy
      expectType expected actualResult "nat-case"
      (binderName, binderQuantity, stepBody) <- expectUnaryLambda succCase
      if binderQuantity == Q0
        then Left "nat-case successor binder cannot be erased in C codegen"
        else do
          (fresh1, scrutineeStmts, scrutineeExpr) <- compileExpr codegenEnv fresh env CNat scrutinee
          (fresh2, zeroStmts, zeroExpr) <- compileExpr codegenEnv fresh1 env expected zeroCase
          let (fresh3, scrutineeTemp) = freshVar "scrutinee" fresh2
          let (fresh4, resultTemp) = freshVar "result" fresh3
          let (fresh5, predTemp) = freshVar (cName binderName) fresh4
          (fresh6, succStmts, succExpr) <-
            compileExpr codegenEnv fresh5 (RuntimeBinding predTemp CNat : env) expected stepBody
          let stmts =
                scrutineeStmts
                  ++ [ CDecl CNat scrutineeTemp (Just scrutineeExpr)
                     , CDecl expected resultTemp Nothing
                     , CIf
                         (scrutineeTemp ++ " == 0ULL")
                         (zeroStmts ++ [CAssign resultTemp zeroExpr])
                         ( [CDecl CNat predTemp (Just (scrutineeTemp ++ " - 1ULL"))]
                             ++ succStmts
                             ++ [CAssign resultTemp succExpr]
                         )
                     ]
          Right (fresh6, stmts, resultTemp)
    (TGlobal "nat-elim", [resultTy, zeroCase, succCase, scrutinee]) -> do
      actualResult <- compileRuntimeType codegenEnv resultTy
      expectType expected actualResult "nat-elim"
      (kName, kQuantity, _recName, recQuantity, stepBody) <- expectBinaryLambda succCase
      if kQuantity == Q0 || recQuantity == Q0
        then Left "nat-elim step binders cannot be erased in C codegen"
        else do
          (fresh1, scrutineeStmts, scrutineeExpr) <- compileExpr codegenEnv fresh env CNat scrutinee
          (fresh2, zeroStmts, zeroExpr) <- compileExpr codegenEnv fresh1 env expected zeroCase
          let (fresh3, limitTemp) = freshVar "limit" fresh2
          let (fresh4, accTemp) = freshVar "acc" fresh3
          let (fresh5, iTemp) = freshVar (cName kName) fresh4
          (fresh6, bodyStmts, bodyExpr) <-
            compileExpr
              codegenEnv
              fresh5
              (RuntimeBinding accTemp expected : RuntimeBinding iTemp CNat : env)
              expected
              stepBody
          let loopStmts = bodyStmts ++ [CAssign accTemp bodyExpr]
          let stmts =
                scrutineeStmts
                  ++ [ CDecl CNat limitTemp (Just scrutineeExpr)
                     ]
                  ++ zeroStmts
                  ++ [ CDecl expected accTemp (Just zeroExpr)
                     , CFor ("uint64_t " ++ iTemp ++ " = 0ULL; " ++ iTemp ++ " < " ++ limitTemp ++ "; ++" ++ iTemp) loopStmts
                     ]
          Right (fresh6, stmts, accTemp)
    (TGlobal name, args) ->
      case lookupExternSpec (codegenExterns codegenEnv) name of
        Nothing ->
          Left ("unsupported residual runtime term: " ++ prettyTerm term)
        Just externSpec ->
          compileExternCall codegenEnv fresh env expected externSpec args
    _ ->
      Left ("unsupported residual runtime term: " ++ prettyTerm term)

compileExternCall ::
     CodegenEnv
  -> Int
  -> [RuntimeBinding]
  -> CType
  -> ExternSpec
  -> [Term]
  -> Either String (Int, [CStmt], String)
compileExternCall codegenEnv fresh env expected externSpec args = do
  let binders = flattenPis (externTypeTerm externSpec)
  if length binders /= length args
    then Left ("extern call arity mismatch for " ++ externInternalName externSpec)
    else do
      actualResult <- compileRuntimeType codegenEnv (resultTypeOf (externTypeTerm externSpec))
      expectType expected actualResult ("extern " ++ externInternalName externSpec)
      (fresh', stmts, argExprs) <- compileExternArgs codegenEnv fresh env binders args
      Right (fresh', stmts, externSymbolName externSpec ++ "(" ++ commaSep0 argExprs ++ ")")

compileExternArgs ::
     CodegenEnv
  -> Int
  -> [RuntimeBinding]
  -> [PiBinder]
  -> [Term]
  -> Either String (Int, [CStmt], [String])
compileExternArgs codegenEnv =
  go []
  where
    go accExprs fresh _ [] [] =
      Right (fresh, [], reverse accExprs)
    go accExprs fresh env (PiBinder _ quantity domain : binders) (arg : args) =
      case quantity of
        Q0 -> go accExprs fresh env binders args
        _ -> do
          cType <- compileRuntimeType codegenEnv domain
          (fresh1, stmts1, expr1) <- compileExpr codegenEnv fresh env cType arg
          (fresh2, stmts2, exprs) <- go (expr1 : accExprs) fresh1 env binders args
          Right (fresh2, stmts1 ++ stmts2, exprs)
    go _ _ _ _ _ =
      Left "internal error: extern binder/arg mismatch"

expectUnaryLambda :: Term -> Either String (Name, Quantity, Term)
expectUnaryLambda term =
  case term of
    TLam name quantity body ->
      Right (name, quantity, body)
    _ ->
      Left ("expected unary lambda in code generation, found " ++ prettyTerm term)

expectBinaryLambda :: Term -> Either String (Name, Quantity, Name, Quantity, Term)
expectBinaryLambda term =
  case term of
    TLam firstName firstQuantity inner ->
      case inner of
        TLam secondName secondQuantity body ->
          Right (firstName, firstQuantity, secondName, secondQuantity, body)
        _ ->
          Left ("expected binary lambda in code generation, found " ++ prettyTerm term)
    _ ->
      Left ("expected binary lambda in code generation, found " ++ prettyTerm term)

compileRuntimeType :: CodegenEnv -> Term -> Either String CType
compileRuntimeType codegenEnv term =
  case term of
    TGlobal "Unit" -> Right CUnit
    TGlobal "Nat" -> Right CNat
    TGlobal "U8" -> Right CU8
    TGlobal "U64" -> Right CU64
    TGlobal "Addr" -> Right CAddr
    TGlobal "Bool" -> Right CBool
    TApp (TGlobal "Ptr") _ -> Right CPtr
    TApp (TApp (TApp (TGlobal "Eff") _) _) resultTy -> compileRuntimeType codegenEnv resultTy
    TGlobal name ->
      case lookupLayoutSpec codegenEnv name of
        Just _ -> Right (CLayout name)
        Nothing -> Left ("unsupported runtime type for C backend: " ++ prettyTerm term)
    _ -> Left ("unsupported runtime type for C backend: " ++ prettyTerm term)

runtimeTypeLayoutTerm :: CodegenEnv -> Term -> Either String (Word64, Word64)
runtimeTypeLayoutTerm codegenEnv term =
  case term of
    TGlobal "Unit" -> Right (1, 1)
    TGlobal "Bool" -> Right (1, 1)
    TGlobal "Nat" -> Right (8, 8)
    TGlobal "U8" -> Right (1, 1)
    TGlobal "U64" -> Right (8, 8)
    TGlobal "Addr" -> Right (8, 8)
    TApp (TGlobal "Ptr") _ -> Right (8, 8)
    TGlobal name ->
      case lookupLayoutSpec codegenEnv name of
        Just layoutSpec -> Right (layoutTypeSize layoutSpec, layoutTypeAlign layoutSpec)
        Nothing -> Left ("unsupported runtime layout query for C backend: " ++ prettyTerm term)
    _ -> Left ("unsupported runtime layout query for C backend: " ++ prettyTerm term)

renderExternPrototype :: CodegenEnv -> ExternSpec -> Either String String
renderExternPrototype codegenEnv externSpec = do
  resultType <- compileRuntimeType codegenEnv (resultTypeOf (externTypeTerm externSpec))
  params <- renderExternParams codegenEnv (flattenPis (externTypeTerm externSpec))
  attrs <- externAttributes codegenEnv (externInternalName externSpec)
  pure (attrs ++ cTypeName resultType ++ " " ++ externSymbolName externSpec ++ "(" ++ renderParams params ++ ");")

renderExternParams :: CodegenEnv -> [PiBinder] -> Either String [(CType, String)]
renderExternParams codegenEnv binders =
  traverse renderParam (zip [0 :: Int ..] binders) >>= pure . foldr keepRuntime []
  where
    renderParam (index, PiBinder name quantity domain) =
      case quantity of
        Q0 -> Right Nothing
        _ -> do
          cType <- compileRuntimeType codegenEnv domain
          let paramName =
                cName
                  (if null name
                     then "arg" ++ show index
                     else name)
          pure (Just (cType, paramName))
    keepRuntime maybeParam acc =
      case maybeParam of
        Nothing -> acc
        Just param -> param : acc

externSpecs :: [CheckedDecl] -> [ExternSpec]
externSpecs checked =
  [ ExternSpec name symbol ty
  | CheckedExtern name ty symbol <- checked
  ]

exportSpecs :: [CheckedDecl] -> [ExportSpec]
exportSpecs checked =
  [ ExportSpec name symbol
  | CheckedExport name symbol <- checked
  ]

sectionSpecs :: [CheckedDecl] -> [SectionSpec]
sectionSpecs checked =
  [ SectionSpec name sectionName
  | CheckedSection name sectionName <- checked
  ]

callingConventionSpecs :: [CheckedDecl] -> [CallingConventionSpec]
callingConventionSpecs checked =
  [ CallingConventionSpec name conventionName
  | CheckedCallingConvention name conventionName <- checked
  ]

entrySpecs :: [CheckedDecl] -> [EntrySpec]
entrySpecs checked =
  [ EntrySpec name
  | CheckedEntry name <- checked
  ]

layoutSpecs :: [CheckedDecl] -> [LayoutSpec]
layoutSpecs checked =
  [ LayoutSpec
      name
      size
      align
      [ LayoutFieldSpec fieldName fieldTy fieldOffset
      | CheckedLayoutField fieldName fieldTy fieldOffset <- fields
      ]
  | CheckedLayout name size align fields <- checked
  ]

codegenSpecs :: [CheckedDecl] -> CodegenEnv
codegenSpecs checked =
  CodegenEnv
    { codegenExterns = externSpecs checked
    , codegenExports = exportSpecs checked
    , codegenSections = sectionSpecs checked
    , codegenCallingConventions = callingConventionSpecs checked
    , codegenEntries = entrySpecs checked
    , codegenLayouts = layoutSpecs checked
    }

lookupExternSpec :: [ExternSpec] -> Name -> Maybe ExternSpec
lookupExternSpec externs target =
  Map.lookup target (Map.fromList [(externInternalName extern, extern) | extern <- externs])

definitionSymbol :: CodegenEnv -> Name -> String
definitionSymbol codegenEnv name =
  case Map.lookup name (Map.fromList [(exportInternalName export, exportSymbolName export) | export <- codegenExports codegenEnv]) of
    Just symbol -> symbol
    Nothing -> cName name

externAttributes :: CodegenEnv -> Name -> Either String String
externAttributes =
  callingConventionAttributes

definitionAttributes :: CodegenEnv -> Name -> Either String String
definitionAttributes codegenEnv name =
  do
    callAttrs <- callingConventionAttributes codegenEnv name
    let entryAttrs =
          if name `elem` [entryInternalName entry | entry <- codegenEntries codegenEnv]
            then "__attribute__((used)) "
            else ""
    let sectionAttrs =
          case Map.lookup name (Map.fromList [(sectionInternalName section, sectionName section) | section <- codegenSections codegenEnv]) of
            Just sectionName' -> "__attribute__((section(\"" ++ sectionName' ++ "\"))) "
            Nothing -> ""
    pure (entryAttrs ++ callAttrs ++ sectionAttrs)

callingConventionAttributes :: CodegenEnv -> Name -> Either String String
callingConventionAttributes codegenEnv name =
  case Map.lookup name (Map.fromList [(callingConventionInternalName convention, callingConventionName convention) | convention <- codegenCallingConventions codegenEnv]) of
    Nothing -> Right ""
    Just conventionName' ->
      case cCallingConventionAttribute conventionName' of
        Just attr -> Right attr
        Nothing -> Left ("unsupported C calling convention: " ++ conventionName')

cCallingConventionAttribute :: Name -> Maybe String
cCallingConventionAttribute conventionName =
  case conventionName of
    "c" -> Just ""
    "sysv-abi" -> Just "__attribute__((sysv_abi)) "
    "ms-abi" -> Just "__attribute__((ms_abi)) "
    _ -> Nothing

lookupLayoutSpec :: CodegenEnv -> Name -> Maybe LayoutSpec
lookupLayoutSpec codegenEnv target =
  Map.lookup target (Map.fromList [(layoutTypeName layout, layout) | layout <- codegenLayouts codegenEnv])

filterUsedExterns :: CodegenEnv -> [Term] -> [ExternSpec]
filterUsedExterns codegenEnv terms =
  [ extern
  | extern <- codegenExterns codegenEnv
  , externInternalName extern `Set.member` used
  ]
  where
    externNames = Set.fromList (map externInternalName (codegenExterns codegenEnv))
    used = Set.unions (map (termGlobals externNames) terms)

termGlobals :: Set.Set Name -> Term -> Set.Set Name
termGlobals externNames term =
  case term of
    TVar _ -> Set.empty
    TGlobal name ->
      if name `Set.member` externNames
        then Set.singleton name
        else Set.empty
    TUniverse _ -> Set.empty
    TU8 _ -> Set.empty
    TU64 _ -> Set.empty
    TAddr _ -> Set.empty
    TLayout _ fields ->
      Set.unions [termGlobals externNames value | LayoutFieldInit _ value <- fields]
    TLayoutField _ _ base ->
      termGlobals externNames base
    TLayoutUpdate _ _ base value ->
      termGlobals externNames base `Set.union` termGlobals externNames value
    TPi _ _ domain codomain ->
      termGlobals externNames domain `Set.union` termGlobals externNames codomain
    TLam _ _ body ->
      termGlobals externNames body
    TMatch scrutinee cases ->
      Set.unions (termGlobals externNames scrutinee : [termGlobals externNames body | CaseTerm _ _ body <- cases])
    TApp fn arg ->
      termGlobals externNames fn `Set.union` termGlobals externNames arg

flattenPis :: Term -> [PiBinder]
flattenPis =
  go []
  where
    go acc term =
      case term of
        TPi name quantity domain codomain ->
          go (PiBinder name quantity domain : acc) codomain
        _ ->
          reverse acc

flattenLams :: Term -> ([LamBinder], Term)
flattenLams =
  go []
  where
    go acc term =
      case term of
        TLam name quantity body ->
          go (LamBinder name quantity : acc) body
        _ ->
          (reverse acc, term)

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

resultTypeOf :: Term -> Term
resultTypeOf term =
  case term of
    TPi _ _ _ codomain -> resultTypeOf codomain
    _ -> term

collectApps :: Term -> (Term, [Term])
collectApps =
  go []
  where
    go args term =
      case term of
        TApp fn arg -> go (arg : args) fn
        _ -> (term, args)

lookupBinding :: [RuntimeBinding] -> Int -> RuntimeBinding
lookupBinding env index =
  case drop index env of
    binding : _ -> binding
    [] -> ErasedBinding

expectType :: CType -> CType -> String -> Either String ()
expectType expected actual label =
  if expected == actual
    then Right ()
    else
      Left
        ( label
            ++ " expected runtime type "
            ++ cTypeName expected
            ++ " but compiled to "
            ++ cTypeName actual
        )

freshVar :: String -> Int -> (Int, String)
freshVar prefix fresh =
  (fresh + 1, prefix ++ "_" ++ show fresh)

renderParams :: [(CType, String)] -> String
renderParams params =
  case params of
    [] -> "void"
    _ -> commaSep [cTypeName ty ++ " " ++ name | (ty, name) <- params]

commaSep0 :: [String] -> String
commaSep0 values =
  case values of
    [] -> ""
    _ -> commaSep values

renderStmt :: Int -> CStmt -> [String]
renderStmt indentLevel stmt =
  case stmt of
    CDecl cType name maybeExpr ->
      [indent indentLevel $
       cTypeName cType
         ++ " "
         ++ name
         ++ maybe ";" (\expr -> " = " ++ expr ++ ";") maybeExpr]
    CAssign name expr ->
      if name == "__result"
        then [indent indentLevel ("return " ++ expr ++ ";")]
        else [indent indentLevel (name ++ " = " ++ expr ++ ";")]
    CIf cond thenStmts elseStmts ->
      [indent indentLevel ("if (" ++ cond ++ ") {")]
        ++ concatMap (renderStmt (indentLevel + 1)) thenStmts
        ++ [indent indentLevel "} else {"]
        ++ concatMap (renderStmt (indentLevel + 1)) elseStmts
        ++ [indent indentLevel "}"]
    CFor header body ->
      [indent indentLevel ("for (" ++ header ++ ") {")]
        ++ concatMap (renderStmt (indentLevel + 1)) body
        ++ [indent indentLevel "}"]
    CRaw line ->
      [indent indentLevel line]

cTypeName :: CType -> String
cTypeName cType =
  case cType of
    CUnit -> "uint8_t"
    CNat -> "uint64_t"
    CU8 -> "uint8_t"
    CU64 -> "uint64_t"
    CAddr -> "uintptr_t"
    CPtr -> "uintptr_t"
    CBool -> "uint8_t"
    CLayout name -> layoutTypeNameC name

derefExpr :: CType -> String -> String
derefExpr cType expr =
  "(*((" ++ cTypeName cType ++ "*)(" ++ expr ++ ")))"

preludeLines :: CodegenMode -> [String]
preludeLines mode =
  case mode of
    HostedC ->
      ["#include <stdint.h>", ""]
    FreestandingC ->
      [ "typedef __UINT8_TYPE__ uint8_t;"
      , "typedef __UINT16_TYPE__ uint16_t;"
      , "typedef __UINT64_TYPE__ uint64_t;"
      , "typedef __UINTPTR_TYPE__ uintptr_t;"
      , ""
      ]

renderLayoutTypedef :: LayoutSpec -> [String]
renderLayoutTypedef layout =
  [ "typedef struct {"
  , "  _Alignas(" ++ show (layoutTypeAlign layout) ++ ") uint8_t bytes[" ++ show (layoutTypeSize layout) ++ "];"
  , "} " ++ layoutTypeNameC (layoutTypeName layout) ++ ";"
  ]

layoutTypeNameC :: Name -> String
layoutTypeNameC name =
  "silt_layout_" ++ cName name

commaSep :: [String] -> String
commaSep =
  foldr1 (\left right -> left ++ ", " ++ right)

indent :: Int -> String -> String
indent level line =
  replicate (level * 2) ' ' ++ line

cName :: Name -> String
cName [] = "silt_value"
cName name =
  let mapped = map normalize name
   in if isAlphaNum (head mapped) then mapped else "silt_" ++ mapped
  where
    normalize c
      | isAlphaNum c = c
      | otherwise = '_'
