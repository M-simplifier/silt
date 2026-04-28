module Site.Html
  ( Attribute
  , Node
  , attr
  , cls
  , el
  , html
  , link
  , meta
  , renderDocument
  , script
  , text
  , voidEl
  ) where

import Prelude

import Data.Foldable (foldMap)
import Data.String.Common (replaceAll)
import Data.String.Pattern (Pattern(..), Replacement(..))

type Attribute =
  { key :: String
  , value :: String
  }

data Node
  = Element String (Array Attribute) (Array Node)
  | TextNode String
  | VoidElement String (Array Attribute)

attr :: String -> String -> Attribute
attr key value = { key, value }

cls :: String -> Attribute
cls = attr "class"

el :: String -> Array Attribute -> Array Node -> Node
el = Element

voidEl :: String -> Array Attribute -> Node
voidEl = VoidElement

text :: String -> Node
text = TextNode

html :: Array Attribute -> Array Node -> Node
html = el "html"

meta :: Array Attribute -> Node
meta = voidEl "meta"

link :: Array Attribute -> Node
link = voidEl "link"

script :: Array Attribute -> Array Node -> Node
script = el "script"

renderDocument :: Node -> String
renderDocument node = "<!doctype html>\n" <> renderNode node <> "\n"

renderNode :: Node -> String
renderNode = case _ of
  TextNode content -> escapeText content
  VoidElement tag attrs -> "<" <> tag <> renderAttrs attrs <> ">"
  Element tag attrs children ->
    "<" <> tag <> renderAttrs attrs <> ">"
      <> foldMap renderNode children
      <> "</" <> tag <> ">"

renderAttrs :: Array Attribute -> String
renderAttrs =
  foldMap renderAttr

renderAttr :: Attribute -> String
renderAttr item =
  " " <> item.key <> "=\"" <> escapeAttribute item.value <> "\""

escapeText :: String -> String
escapeText =
  replaceAll (Pattern "&") (Replacement "&amp;")
    >>> replaceAll (Pattern "<") (Replacement "&lt;")
    >>> replaceAll (Pattern ">") (Replacement "&gt;")

escapeAttribute :: String -> String
escapeAttribute =
  escapeText
    >>> replaceAll (Pattern "\"") (Replacement "&quot;")
