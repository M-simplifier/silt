module Silt.Parse
  ( parseProgram
  , parseProgramFromSExprs
  , parseSExprs
  ) where

import Data.Char (isDigit, isSpace)
import Data.Word (Word64)
import Silt.Syntax

data Position = Position
  { posLine :: !Int
  , posColumn :: !Int
  }
  deriving (Eq, Show)

data Token
  = TLParen Position
  | TRParen Position
  | TAtom Position String
  deriving (Eq, Show)

parseProgram :: String -> Either String Program
parseProgram input = do
  sexprs <- parseSExprs input
  parseProgramFromSExprs sexprs

parseProgramFromSExprs :: [SExpr] -> Either String Program
parseProgramFromSExprs sexprs =
  Program <$> traverse sexprToDecl sexprs

parseSExprs :: String -> Either String [SExpr]
parseSExprs input = do
  tokens <- lexTokens input
  parseMany tokens

lexTokens :: String -> Either String [Token]
lexTokens = go (Position 1 1) []
  where
    go _ acc [] = Right (reverse acc)
    go pos acc (c:cs)
      | isSpace c =
          go (advance pos c) acc cs
      | c == ';' =
          let (pos', rest) = skipComment (advance pos c) cs
           in go pos' acc rest
      | c == '(' =
          go (advance pos c) (TLParen pos : acc) cs
      | c == ')' =
          go (advance pos c) (TRParen pos : acc) cs
      | otherwise =
          let (atom, pos', rest) = scanAtom pos (c : cs)
           in go pos' (TAtom pos atom : acc) rest

skipComment :: Position -> String -> (Position, String)
skipComment pos [] = (pos, [])
skipComment pos (c:cs)
  | c == '\n' = (advance pos c, cs)
  | otherwise = skipComment (advance pos c) cs

scanAtom :: Position -> String -> (String, Position, String)
scanAtom = go []
  where
    go acc pos [] = (reverse acc, pos, [])
    go acc pos chars@(c:cs)
      | isDelimiter c = (reverse acc, pos, chars)
      | otherwise = go (c : acc) (advance pos c) cs

isDelimiter :: Char -> Bool
isDelimiter c =
  isSpace c || c == '(' || c == ')' || c == ';'

advance :: Position -> Char -> Position
advance (Position line column) c
  | c == '\n' = Position (line + 1) 1
  | otherwise = Position line (column + 1)

parseMany :: [Token] -> Either String [SExpr]
parseMany [] = Right []
parseMany tokens = do
  (expr, rest) <- parseOne tokens
  (expr :) <$> parseMany rest

parseOne :: [Token] -> Either String (SExpr, [Token])
parseOne [] =
  Left "unexpected end of input"
parseOne (TAtom _ atom : rest) =
  Right (Atom atom, rest)
parseOne (TRParen pos : _) =
  Left ("unexpected ')' at " ++ showPos pos)
parseOne (TLParen pos : rest) =
  parseList pos [] rest

parseList :: Position -> [SExpr] -> [Token] -> Either String (SExpr, [Token])
parseList start _ [] =
  Left ("unclosed '(' starting at " ++ showPos start)
parseList _ acc (TRParen _ : rest) =
  Right (List (reverse acc), rest)
parseList start acc tokens = do
  (expr, rest) <- parseOne tokens
  parseList start (expr : acc) rest

showPos :: Position -> String
showPos (Position line column) =
  show line ++ ":" ++ show column

sexprToDecl :: SExpr -> Either String Decl
sexprToDecl sexpr =
  case sexpr of
    List (Atom "data" : Atom name : List params : ctors) ->
      DataDecl name <$> traverse sexprToBinder params <*> traverse sexprToConstructorDecl ctors
    List [Atom "layout", Atom name, Atom size, Atom align] ->
      (\size' align' -> LayoutDecl name size' align' []) <$> parseNatural size <*> parseNatural align
    List [Atom "layout", Atom name, Atom size, Atom align, List fields] ->
      LayoutDecl name <$> parseNatural size <*> parseNatural align <*> traverse sexprToLayoutFieldDecl fields
    List [Atom "static-bytes", Atom name, List values] ->
      StaticBytes name <$> traverse sexprToStaticByte values
    List [Atom "static-cell", Atom name, ty] ->
      StaticCell name <$> sexprToSurface ty
    List [Atom "static-value", Atom name, ty, Atom sectionName, value] ->
      StaticValue name <$> sexprToSurface ty <*> pure sectionName <*> sexprToSurface value
    List [Atom "extern", Atom name, ty] ->
      (\ty' -> Extern name ty' Nothing) <$> sexprToSurface ty
    List [Atom "extern", Atom name, ty, Atom symbol] ->
      (\ty' -> Extern name ty' (Just symbol)) <$> sexprToSurface ty
    List [Atom "export", Atom name, Atom symbol] ->
      Right (Export name symbol)
    List [Atom "section", Atom name, Atom sectionName] ->
      Right (Section name sectionName)
    List [Atom "calling-convention", Atom name, Atom conventionName] ->
      Right (CallingConvention name conventionName)
    List [Atom "entry", Atom name] ->
      Right (Entry name)
    List [Atom "abi-contract", Atom name, List clauses] ->
      AbiContract name <$> traverse sexprToAbiContractClause clauses
    List [Atom "target-contract", Atom target, List clauses] ->
      TargetContract target <$> traverse sexprToTargetContractClause clauses
    List [Atom "boot-contract", Atom name, List clauses] ->
      BootContract name <$> traverse sexprToBootContractClause clauses
    List [Atom "claim", Atom name, ty] ->
      Claim name <$> sexprToSurface ty
    List [Atom "def", Atom name, expr] ->
      Define name <$> sexprToSurface expr
    _ ->
      Left ("expected top-level (data ...), (layout ...), (static-bytes ...), (static-cell ...), (static-value ...), (extern ...), (export ...), (section ...), (calling-convention ...), (entry ...), (abi-contract ...), (target-contract ...), (boot-contract ...), (claim ...), or (def ...), found " ++ show sexpr)

sexprToAbiContractClause :: SExpr -> Either String AbiContractClause
sexprToAbiContractClause sexpr =
  case sexpr of
    List [Atom "entry"] ->
      Right AbiContractEntry
    List [Atom "symbol", Atom symbol] ->
      Right (AbiContractSymbol symbol)
    List [Atom "section", Atom sectionName] ->
      Right (AbiContractSection sectionName)
    List [Atom "calling-convention", Atom conventionName] ->
      Right (AbiContractCallingConvention conventionName)
    List [Atom "freestanding"] ->
      Right AbiContractFreestanding
    _ ->
      Left ("expected abi-contract clause (entry), (symbol ...), (section ...), (calling-convention ...), or (freestanding), found " ++ show sexpr)

sexprToTargetContractClause :: SExpr -> Either String TargetContractClause
sexprToTargetContractClause sexpr =
  case sexpr of
    List [Atom "format", Atom formatName] ->
      Right (TargetContractFormat formatName)
    List [Atom "arch", Atom archName] ->
      Right (TargetContractArch archName)
    List [Atom "abi", Atom abiName] ->
      Right (TargetContractAbi abiName)
    List [Atom "entry", Atom entryName] ->
      Right (TargetContractEntry entryName)
    List [Atom "symbol", Atom symbol] ->
      Right (TargetContractSymbol symbol)
    List [Atom "section", Atom sectionName] ->
      Right (TargetContractSection sectionName)
    List [Atom "calling-convention", Atom conventionName] ->
      Right (TargetContractCallingConvention conventionName)
    List [Atom "entry-address", Atom address] ->
      TargetContractEntryAddress <$> parseNatural address
    List [Atom "red-zone", Atom mode] ->
      Right (TargetContractRedZone mode)
    List [Atom "freestanding"] ->
      Right TargetContractFreestanding
    _ ->
      Left ("expected target-contract clause (format ...), (arch ...), (abi ...), (entry ...), (symbol ...), (section ...), (calling-convention ...), (entry-address ...), (red-zone ...), or (freestanding), found " ++ show sexpr)

sexprToBootContractClause :: SExpr -> Either String BootContractClause
sexprToBootContractClause sexpr =
  case sexpr of
    List [Atom "protocol", Atom protocol] ->
      Right (BootContractProtocol protocol)
    List [Atom "target", Atom target] ->
      Right (BootContractTarget target)
    List [Atom "entry", Atom entryName] ->
      Right (BootContractEntry entryName)
    List [Atom "kernel-path", Atom path] ->
      Right (BootContractKernelPath path)
    List [Atom "config-path", Atom path] ->
      Right (BootContractConfigPath path)
    List [Atom "freestanding"] ->
      Right BootContractFreestanding
    _ ->
      Left ("expected boot-contract clause (protocol ...), (target ...), (entry ...), (kernel-path ...), (config-path ...), or (freestanding), found " ++ show sexpr)

sexprToSurface :: SExpr -> Either String Surface
sexprToSurface sexpr =
  case sexpr of
    Atom atom ->
      case parseUniverse atom of
        Just level -> Right (SUniverse level)
        Nothing -> Right (SVar atom)
    List [Atom "u64", Atom digits] ->
      SU64 <$> parseNatural digits
    List [Atom "u8", Atom digits] ->
      SU8 <$> parseU8 digits
    List [Atom "addr", Atom digits] ->
      SAddr <$> parseNatural digits
    List [Atom "let", List bindings, body] ->
      SLet <$> traverse sexprToLetBinding bindings <*> sexprToSurface body
    List [Atom "let-layout", Atom layoutName, List bindings, source, body] ->
      SLetLayout layoutName <$> traverse sexprToLayoutBinding bindings <*> sexprToSurface source <*> sexprToSurface body
    List [Atom "let-load-layout", Atom layoutName, List bindings, source, body] ->
      SLetLoadLayout (SVar "Heap") layoutName <$> traverse sexprToLayoutBinding bindings <*> sexprToSurface source <*> sexprToSurface body
    List [Atom "let-load-layout", cap, Atom layoutName, List bindings, source, body] ->
      SLetLoadLayout <$> sexprToSurface cap <*> pure layoutName <*> traverse sexprToLayoutBinding bindings <*> sexprToSurface source <*> sexprToSurface body
    List [Atom "with-fields", Atom layoutName, source, List fields] ->
      SWithFields layoutName <$> sexprToSurface source <*> traverse sexprToLayoutFieldInit fields
    List [Atom "store-fields", Atom layoutName, base, List fields] ->
      SStoreFields (SVar "Heap") layoutName <$> sexprToSurface base <*> traverse sexprToLayoutFieldInit fields
    List [Atom "store-fields", cap, Atom layoutName, base, List fields] ->
      SStoreFields <$> sexprToSurface cap <*> pure layoutName <*> sexprToSurface base <*> traverse sexprToLayoutFieldInit fields
    List (Atom "match" : scrutinee : arms) ->
      SMatch <$> sexprToSurface scrutinee <*> traverse sexprToMatchArm arms
    List [Atom "layout", Atom name, List fields] ->
      SLayout name <$> traverse sexprToLayoutFieldInit fields
    List (Atom "layout-values" : Atom name : values) ->
      SLayoutValues name <$> traverse sexprToSurface values
    List [Atom "Pi", List binders, body] ->
      SPi <$> traverse sexprToBinder binders <*> sexprToSurface body
    List [Atom "fn", List binders, body] ->
      SLam <$> traverse sexprToBinder binders <*> sexprToSurface body
    List [Atom "the", ty, expr] ->
      SAnn <$> sexprToSurface expr <*> sexprToSurface ty
    List [] ->
      Left "empty application is not valid surface syntax"
    List (fn : args) ->
      SApp <$> sexprToSurface fn <*> traverse sexprToSurface args

sexprToBinder :: SExpr -> Either String (Binder Surface)
sexprToBinder sexpr =
  case sexpr of
    List [Atom name, Atom quantity, ty] ->
      Binder name <$> parseQuantity quantity <*> sexprToSurface ty
    List [Atom name, ty] ->
      Binder name QOmega <$> sexprToSurface ty
    _ ->
      Left ("expected binder pair (name type), found " ++ show sexpr)

parseUniverse :: String -> Maybe Int
parseUniverse "Type" = Just 0
parseUniverse atom =
  case splitAt 4 atom of
    ("Type", digits)
      | not (null digits) && all isDigit digits -> Just (read digits)
    _ -> Nothing

sexprToLetBinding :: SExpr -> Either String (Binder Surface)
sexprToLetBinding sexpr =
  case sexpr of
    List [Atom name, Atom quantity, expr] ->
      Binder name <$> parseQuantity quantity <*> sexprToSurface expr
    List [Atom name, expr] ->
      Binder name QOmega <$> sexprToSurface expr
    _ ->
      Left ("expected let binding (name expr), found " ++ show sexpr)

sexprToMatchArm :: SExpr -> Either String MatchArm
sexprToMatchArm sexpr =
  case sexpr of
    List [patternSExpr, body] ->
      MatchArm <$> sexprToPattern patternSExpr <*> sexprToSurface body
    _ ->
      Left ("expected match arm ((Pattern ...) body), found " ++ show sexpr)

sexprToPattern :: SExpr -> Either String MatchPattern
sexprToPattern sexpr =
  case sexpr of
    List (Atom name : binders) ->
      PConstructor name <$> traverse sexprToPatternBinder binders
    _ ->
      Left ("unsupported match pattern " ++ show sexpr)

sexprToPatternBinder :: SExpr -> Either String PatternBinder
sexprToPatternBinder sexpr =
  case sexpr of
    Atom name ->
      Right (PatternBinder name QOmega)
    List [Atom name, Atom quantity] ->
      PatternBinder name <$> parseQuantity quantity
    _ ->
      Left ("unsupported pattern binder " ++ show sexpr)

parseQuantity :: String -> Either String Quantity
parseQuantity atom =
  case atom of
    "0" -> Right Q0
    "1" -> Right Q1
    "w" -> Right QOmega
    "omega" -> Right QOmega
    _ -> Left ("unsupported quantity " ++ show atom)

parseNatural :: String -> Either String Word64
parseNatural digits
  | not (null digits) && all isDigit digits =
      let value = read digits :: Integer
       in if value <= fromIntegral (maxBound :: Word64)
            then Right (fromIntegral value)
            else Left ("u64 literal out of range: " ++ digits)
  | otherwise = Left ("expected natural-number literal, found " ++ show digits)

parseU8 :: String -> Either String Word64
parseU8 digits = do
  value <- parseNatural digits
  if value <= 255
    then Right value
    else Left ("u8 literal out of range: " ++ digits)

sexprToStaticByte :: SExpr -> Either String Word64
sexprToStaticByte sexpr =
  case sexpr of
    List [Atom "u8", Atom digits] ->
      parseU8 digits
    _ ->
      Left ("expected static byte literal (u8 n), found " ++ show sexpr)

sexprToConstructorDecl :: SExpr -> Either String ConstructorDecl
sexprToConstructorDecl sexpr =
  case sexpr of
    List (Atom name : fields) ->
      ConstructorDecl name <$> traverse sexprToSurface fields
    _ ->
      Left ("expected constructor declaration, found " ++ show sexpr)

sexprToLayoutFieldDecl :: SExpr -> Either String LayoutFieldDecl
sexprToLayoutFieldDecl sexpr =
  case sexpr of
    List [Atom name, ty, Atom offset] ->
      LayoutFieldDecl name <$> sexprToSurface ty <*> parseNatural offset
    _ ->
      Left ("expected layout field declaration (name type offset), found " ++ show sexpr)

sexprToLayoutFieldInit :: SExpr -> Either String (LayoutFieldInit Surface)
sexprToLayoutFieldInit sexpr =
  case sexpr of
    List [Atom name, value] ->
      LayoutFieldInit name <$> sexprToSurface value
    _ ->
      Left ("expected layout field initializer (name value), found " ++ show sexpr)

sexprToLayoutBinding :: SExpr -> Either String LayoutBinding
sexprToLayoutBinding sexpr =
  case sexpr of
    List [Atom fieldName, Atom quantity, Atom localName] ->
      LayoutBinding fieldName <$> parseQuantity quantity <*> pure localName
    List [Atom fieldName, Atom localName] ->
      Right (LayoutBinding fieldName QOmega localName)
    _ ->
      Left ("expected layout binding (field local) or (field quantity local), found " ++ show sexpr)
