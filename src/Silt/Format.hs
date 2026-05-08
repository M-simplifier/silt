module Silt.Format
  ( formatSExprSource
  ) where

import Data.Char (isSpace)
import Data.List (intercalate)

data FormatNode
  = FormatAtom String
  | FormatList [FormatNode]
  | FormatComment String
  deriving (Eq, Show)

data Position = Position
  { posLine :: !Int
  , posColumn :: !Int
  }
  deriving (Eq, Show)

formatSExprSource :: String -> Either String String
formatSExprSource input = do
  nodes <- parseFormatNodes input
  pure (formatSExprs nodes)

formatSExprs :: [FormatNode] -> String
formatSExprs nodes =
  case nodes of
    [] -> ""
    _ -> intercalate "\n\n" (map (formatNode 0) nodes) ++ "\n"

parseFormatNodes :: String -> Either String [FormatNode]
parseFormatNodes =
  parseMany (Position 1 1) []

parseMany :: Position -> [FormatNode] -> String -> Either String [FormatNode]
parseMany pos acc input =
  case skipSpace pos input of
    (_, []) -> Right (reverse acc)
    (pos', ')':_) -> Left ("unexpected ')' at " ++ showPos pos')
    (pos', rest) -> do
      (node, pos'', rest') <- parseNode pos' rest
      parseMany pos'' (node : acc) rest'

parseNode :: Position -> String -> Either String (FormatNode, Position, String)
parseNode pos input =
  case input of
    [] -> Left "unexpected end of input"
    '(' : rest -> parseList (advance pos '(') pos [] rest
    ')' : _ -> Left ("unexpected ')' at " ++ showPos pos)
    ';' : rest ->
      let (comment, pos', rest') = scanComment (advance pos ';') rest
       in Right (FormatComment (';' : comment), pos', rest')
    _ ->
      let (atom, pos', rest') = scanAtom [] pos input
       in Right (FormatAtom atom, pos', rest')

parseList :: Position -> Position -> [FormatNode] -> String -> Either String (FormatNode, Position, String)
parseList _ start _ [] =
  Left ("unclosed '(' starting at " ++ showPos start)
parseList pos start acc input =
  case skipSpace pos input of
    (_, []) -> Left ("unclosed '(' starting at " ++ showPos start)
    (pos', ')' : rest) -> Right (FormatList (reverse acc), advance pos' ')', rest)
    (pos', rest) -> do
      (node, pos'', rest') <- parseNode pos' rest
      parseList pos'' start (node : acc) rest'

skipSpace :: Position -> String -> (Position, String)
skipSpace pos [] = (pos, [])
skipSpace pos input@(c:cs)
  | isSpace c = skipSpace (advance pos c) cs
  | otherwise = (pos, input)

scanComment :: Position -> String -> (String, Position, String)
scanComment pos [] = ("", pos, [])
scanComment pos (c:cs)
  | c == '\n' = ("", advance pos c, cs)
  | otherwise =
      let (comment, pos', rest) = scanComment (advance pos c) cs
       in (c : comment, pos', rest)

scanAtom :: String -> Position -> String -> (String, Position, String)
scanAtom acc pos [] = (reverse acc, pos, [])
scanAtom acc pos input@(c:cs)
  | isDelimiter c = (reverse acc, pos, input)
  | otherwise = scanAtom (c : acc) (advance pos c) cs

isDelimiter :: Char -> Bool
isDelimiter c =
  isSpace c || c == '(' || c == ')' || c == ';'

advance :: Position -> Char -> Position
advance (Position line column) c
  | c == '\n' = Position (line + 1) 1
  | otherwise = Position line (column + 1)

showPos :: Position -> String
showPos (Position line column) =
  show line ++ ":" ++ show column

formatNode :: Int -> FormatNode -> String
formatNode indent node =
  case node of
    FormatAtom atom -> spaces indent ++ atom
    FormatComment comment -> spaces indent ++ comment
    FormatList nodes -> formatList indent nodes

formatList :: Int -> [FormatNode] -> String
formatList indent nodes =
  case renderInline (FormatList nodes) of
    Just inline | indent + length inline <= maxLineWidth -> spaces indent ++ inline
    _ -> formatMultilineList indent nodes

formatMultilineList :: Int -> [FormatNode] -> String
formatMultilineList indent nodes =
  case nodes of
    [] -> spaces indent ++ "()"
    FormatAtom headAtom : rest ->
      closeLastLine ((spaces indent ++ "(" ++ headAtom) : map (formatNode (indent + 2)) rest)
    first : rest ->
      case lines (formatNode (indent + 1) first) of
        [] -> spaces indent ++ "()"
        firstLine : moreFirstLines ->
          closeLastLine
            ( (spaces indent ++ "(" ++ dropWhile (== ' ') firstLine)
                : moreFirstLines
                  ++ map (formatNode (indent + 1)) rest
            )

closeLastLine :: [String] -> String
closeLastLine [] = ")"
closeLastLine lines' =
  intercalate "\n" (init lines' ++ [last lines' ++ ")"])

renderInline :: FormatNode -> Maybe String
renderInline node =
  case node of
    FormatAtom atom -> Just atom
    FormatComment _ -> Nothing
    FormatList nodes -> do
      rendered <- traverse renderInline nodes
      let inline = "(" ++ unwords rendered ++ ")"
      if length inline <= maxLineWidth then Just inline else Nothing

maxLineWidth :: Int
maxLineWidth = 88

spaces :: Int -> String
spaces n =
  replicate n ' '
