module Silt.Syntax
  ( Name
  , SExpr (..)
  , Program (..)
  , Decl (..)
  , AbiContractClause (..)
  , TargetContractClause (..)
  , BootContractClause (..)
  , LayoutFieldDecl (..)
  , LayoutFieldInit (..)
  , LayoutBinding (..)
  , ConstructorDecl (..)
  , Quantity (..)
  , Binder (..)
  , PatternBinder (..)
  , Surface (..)
  , MatchArm (..)
  , MatchPattern (..)
  , CaseTerm (..)
  , Term (..)
  , prettyTerm
  , prettyDecl
  ) where

import Data.Word (Word64)

type Name = String

data SExpr
  = Atom String
  | List [SExpr]
  deriving (Eq, Show)

newtype Program = Program [Decl]
  deriving (Eq, Show)

data Decl
  = Claim Name Surface
  | Define Name Surface
  | Extern Name Surface (Maybe Name)
  | Export Name Name
  | Section Name Name
  | CallingConvention Name Name
  | Entry Name
  | AbiContract Name [AbiContractClause]
  | TargetContract Name [TargetContractClause]
  | BootContract Name [BootContractClause]
  | LayoutDecl Name Word64 Word64 [LayoutFieldDecl]
  | StaticBytes Name [Word64]
  | DataDecl Name [Binder Surface] [ConstructorDecl]
  deriving (Eq, Show)

data AbiContractClause
  = AbiContractEntry
  | AbiContractSymbol Name
  | AbiContractSection Name
  | AbiContractCallingConvention Name
  | AbiContractFreestanding
  deriving (Eq, Show)

data TargetContractClause
  = TargetContractFormat Name
  | TargetContractArch Name
  | TargetContractAbi Name
  | TargetContractEntry Name
  | TargetContractSymbol Name
  | TargetContractSection Name
  | TargetContractCallingConvention Name
  | TargetContractEntryAddress Word64
  | TargetContractRedZone Name
  | TargetContractFreestanding
  deriving (Eq, Show)

data BootContractClause
  = BootContractProtocol Name
  | BootContractTarget Name
  | BootContractEntry Name
  | BootContractKernelPath Name
  | BootContractConfigPath Name
  | BootContractFreestanding
  deriving (Eq, Show)

data LayoutFieldDecl = LayoutFieldDecl Name Surface Word64
  deriving (Eq, Show)

data LayoutFieldInit a = LayoutFieldInit Name a
  deriving (Eq, Show)

data LayoutBinding = LayoutBinding
  { layoutBindingField :: Name
  , layoutBindingQuantity :: Quantity
  , layoutBindingName :: Name
  }
  deriving (Eq, Show)

data ConstructorDecl = ConstructorDecl Name [Surface]
  deriving (Eq, Show)

data Quantity
  = Q0
  | Q1
  | QOmega
  deriving (Eq, Ord, Show)

data Binder a = Binder
  { binderName :: Name
  , binderQuantity :: Quantity
  , binderPayload :: a
  }
  deriving (Eq, Show)

data PatternBinder = PatternBinder
  { patternBinderName :: Name
  , patternBinderQuantity :: Quantity
  }
  deriving (Eq, Show)

data Surface
  = SVar Name
  | SUniverse Int
  | SU8 Word64
  | SU64 Word64
  | SAddr Word64
  | SPi [Binder Surface] Surface
  | SLam [Binder Surface] Surface
  | SLet [Binder Surface] Surface
  | SLetLayout Name [LayoutBinding] Surface Surface
  | SLetLoadLayout Surface Name [LayoutBinding] Surface Surface
  | SWithFields Name Surface [LayoutFieldInit Surface]
  | SStoreFields Surface Name Surface [LayoutFieldInit Surface]
  | SMatch Surface [MatchArm]
  | SLayout Name [LayoutFieldInit Surface]
  | SLayoutValues Name [Surface]
  | SApp Surface [Surface]
  | SAnn Surface Surface
  deriving (Eq, Show)

data MatchArm = MatchArm MatchPattern Surface
  deriving (Eq, Show)

data MatchPattern
  = PConstructor Name [PatternBinder]
  deriving (Eq, Show)

data CaseTerm = CaseTerm Name [PatternBinder] Term
  deriving (Eq, Show)

data Term
  = TVar Int
  | TGlobal Name
  | TUniverse Int
  | TU8 Word64
  | TU64 Word64
  | TAddr Word64
  | TStaticBytesPtr Name
  | TPi Name Quantity Term Term
  | TLam Name Quantity Term
  | TMatch Term [CaseTerm]
  | TLayout Name [LayoutFieldInit Term]
  | TLayoutField Name Name Term
  | TLayoutUpdate Name Name Term Term
  | TApp Term Term
  deriving (Eq, Show)

prettyDecl :: Decl -> String
prettyDecl decl =
  case decl of
    Claim name ty -> "(claim " ++ name ++ " " ++ prettySurface ty ++ ")"
    Define name expr -> "(def " ++ name ++ " " ++ prettySurface expr ++ ")"
    Extern name ty maybeSymbol ->
      "(extern "
        ++ name
        ++ " "
        ++ prettySurface ty
        ++ maybe "" (" " ++) maybeSymbol
        ++ ")"
    Export name symbol ->
      "(export " ++ name ++ " " ++ symbol ++ ")"
    Section name sectionName ->
      "(section " ++ name ++ " " ++ sectionName ++ ")"
    CallingConvention name conventionName ->
      "(calling-convention " ++ name ++ " " ++ conventionName ++ ")"
    Entry name ->
      "(entry " ++ name ++ ")"
    AbiContract name clauses ->
      "(abi-contract " ++ name ++ " (" ++ unwords (map prettyAbiContractClause clauses) ++ "))"
    TargetContract target clauses ->
      "(target-contract " ++ target ++ " (" ++ unwords (map prettyTargetContractClause clauses) ++ "))"
    BootContract name clauses ->
      "(boot-contract " ++ name ++ " (" ++ unwords (map prettyBootContractClause clauses) ++ "))"
    LayoutDecl name size align fields ->
      "(layout "
        ++ name
        ++ " "
        ++ show size
        ++ " "
        ++ show align
        ++ case fields of
             [] -> ""
             _ -> " (" ++ unwords (map prettyLayoutFieldDecl fields) ++ ")"
        ++ ")"
    StaticBytes name values ->
      "(static-bytes "
        ++ name
        ++ " ("
        ++ unwords ["(u8 " ++ show value ++ ")" | value <- values]
        ++ "))"
    DataDecl name params ctors ->
      "(data "
        ++ name
        ++ " ("
        ++ unwords (map prettySurfaceBinder params)
        ++ ") "
        ++ unwords (map prettyConstructorDecl ctors)
        ++ ")"

prettyAbiContractClause :: AbiContractClause -> String
prettyAbiContractClause clause =
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

prettyTargetContractClause :: TargetContractClause -> String
prettyTargetContractClause clause =
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

prettyBootContractClause :: BootContractClause -> String
prettyBootContractClause clause =
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

prettySurface :: Surface -> String
prettySurface surface =
  case surface of
    SVar name -> name
    SUniverse 0 -> "Type"
    SUniverse level -> "Type" ++ show level
    SU8 value -> "(u8 " ++ show value ++ ")"
    SU64 value -> "(u64 " ++ show value ++ ")"
    SAddr value -> "(addr " ++ show value ++ ")"
    SPi binders body ->
      "(Pi (" ++ unwords (map prettySurfaceBinder binders) ++ ") " ++ prettySurface body ++ ")"
    SLam binders body ->
      "(fn (" ++ unwords (map prettySurfaceBinder binders) ++ ") " ++ prettySurface body ++ ")"
    SLet bindings body ->
      "(let (" ++ unwords (map prettyLetBinding bindings) ++ ") " ++ prettySurface body ++ ")"
    SLetLayout layoutName bindings source body ->
      "(let-layout "
        ++ layoutName
        ++ " ("
        ++ unwords (map prettyLayoutBinding bindings)
        ++ ") "
        ++ prettySurface source
        ++ " "
        ++ prettySurface body
        ++ ")"
    SLetLoadLayout cap layoutName bindings source body ->
      "(let-load-layout "
        ++ prettyCapabilityPrefix cap
        ++ layoutName
        ++ " ("
        ++ unwords (map prettyLayoutBinding bindings)
        ++ ") "
        ++ prettySurface source
        ++ " "
        ++ prettySurface body
        ++ ")"
    SWithFields layoutName source fields ->
      "(with-fields "
        ++ layoutName
        ++ " "
        ++ prettySurface source
        ++ " ("
        ++ unwords (map (prettyLayoutFieldInit prettySurface) fields)
        ++ "))"
    SStoreFields cap layoutName base fields ->
      "(store-fields "
        ++ prettyCapabilityPrefix cap
        ++ layoutName
        ++ " "
        ++ prettySurface base
        ++ " ("
        ++ unwords (map (prettyLayoutFieldInit prettySurface) fields)
        ++ "))"
    SMatch scrutinee arms ->
      "(match " ++ prettySurface scrutinee ++ " " ++ unwords (map prettyArm arms) ++ ")"
    SLayout name fields ->
      "(layout " ++ name ++ " (" ++ unwords (map (prettyLayoutFieldInit prettySurface) fields) ++ "))"
    SLayoutValues name values ->
      "(" ++ unwords ("layout-values" : name : map prettySurface values) ++ ")"
    SApp fn args ->
      "(" ++ unwords (map prettySurface (fn : args)) ++ ")"
    SAnn expr ty ->
      "(the " ++ prettySurface ty ++ " " ++ prettySurface expr ++ ")"
  where
    prettyLetBinding binder =
      "(" ++ binderName binder ++ prettyQuantity binder ++ " " ++ prettySurface (binderPayload binder) ++ ")"
    prettyArm (MatchArm pattern' body) =
      "(" ++ prettyPattern pattern' ++ " " ++ prettySurface body ++ ")"

prettySurfaceBinder :: Binder Surface -> String
prettySurfaceBinder binder =
  "(" ++ binderName binder ++ prettyQuantity binder ++ " " ++ prettySurface (binderPayload binder) ++ ")"

prettyCapabilityPrefix :: Surface -> String
prettyCapabilityPrefix cap =
  case cap of
    SVar "Heap" -> ""
    _ -> prettySurface cap ++ " "

prettyPattern :: MatchPattern -> String
prettyPattern pattern' =
  case pattern' of
    PConstructor name binders ->
      "(" ++ unwords (name : map prettyPatternBinder binders) ++ ")"

prettyTerm :: Term -> String
prettyTerm term =
  case term of
    TVar index -> "#" ++ show index
    TGlobal name -> name
    TUniverse 0 -> "Type"
    TUniverse level -> "Type" ++ show level
    TU8 value -> "(u8 " ++ show value ++ ")"
    TU64 value -> "(u64 " ++ show value ++ ")"
    TAddr value -> "(addr " ++ show value ++ ")"
    TStaticBytesPtr name -> "(static-bytes-ptr " ++ name ++ ")"
    TPi name quantity domain codomain ->
      "(Pi ((" ++ name ++ prettyQuantityAtom quantity ++ " " ++ prettyTerm domain ++ ")) " ++ prettyTerm codomain ++ ")"
    TLam name quantity body ->
      "(fn (" ++ lambdaBinder name quantity ++ ") " ++ prettyTerm body ++ ")"
    TMatch scrutinee cases ->
      "(match "
        ++ prettyTerm scrutinee
        ++ " "
        ++ unwords (map prettyCaseTerm cases)
        ++ ")"
    TLayout name fields ->
      "(layout " ++ name ++ " (" ++ unwords (map (prettyLayoutFieldInit prettyTerm) fields) ++ "))"
    TLayoutField layoutName fieldName base ->
      "(field " ++ layoutName ++ " " ++ fieldName ++ " " ++ prettyTerm base ++ ")"
    TLayoutUpdate layoutName fieldName base value ->
      "(with-field "
        ++ layoutName
        ++ " "
        ++ fieldName
        ++ " "
        ++ prettyTerm base
        ++ " "
        ++ prettyTerm value
        ++ ")"
    TApp fn arg ->
      "(" ++ prettyTerm fn ++ " " ++ prettyTerm arg ++ ")"

prettyQuantity :: Binder a -> String
prettyQuantity binder =
  case binderQuantity binder of
    QOmega -> ""
    quantity -> " " ++ quantityToken quantity

prettyQuantityAtom :: Quantity -> String
prettyQuantityAtom quantity =
  case quantity of
    QOmega -> ""
    _ -> " " ++ quantityToken quantity

lambdaBinder :: Name -> Quantity -> String
lambdaBinder name quantity =
  case quantity of
    QOmega -> name
    _ -> "(" ++ name ++ prettyQuantityAtom quantity ++ ")"

quantityToken :: Quantity -> String
quantityToken quantity =
  case quantity of
    Q0 -> "0"
    Q1 -> "1"
    QOmega -> "omega"

prettyConstructorDecl :: ConstructorDecl -> String
prettyConstructorDecl (ConstructorDecl name fields) =
  "(" ++ unwords (name : map prettySurface fields) ++ ")"

prettyLayoutFieldDecl :: LayoutFieldDecl -> String
prettyLayoutFieldDecl (LayoutFieldDecl name ty offset) =
  "(" ++ name ++ " " ++ prettySurface ty ++ " " ++ show offset ++ ")"

prettyLayoutFieldInit :: (a -> String) -> LayoutFieldInit a -> String
prettyLayoutFieldInit prettyPayload (LayoutFieldInit name value) =
  "(" ++ name ++ " " ++ prettyPayload value ++ ")"

prettyLayoutBinding :: LayoutBinding -> String
prettyLayoutBinding binding =
  case layoutBindingQuantity binding of
    QOmega ->
      "(" ++ layoutBindingField binding ++ " " ++ layoutBindingName binding ++ ")"
    quantity ->
      "("
        ++ layoutBindingField binding
        ++ " "
        ++ quantityToken quantity
        ++ " "
        ++ layoutBindingName binding
        ++ ")"

prettyCaseTerm :: CaseTerm -> String
prettyCaseTerm (CaseTerm name binders body) =
  "((" ++ unwords (name : map prettyPatternBinder binders) ++ ") " ++ prettyTerm body ++ ")"

prettyPatternBinder :: PatternBinder -> String
prettyPatternBinder binder =
  case patternBinderQuantity binder of
    QOmega -> patternBinderName binder
    quantity ->
      "(" ++ patternBinderName binder ++ " " ++ quantityToken quantity ++ ")"
