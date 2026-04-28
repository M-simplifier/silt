module Site.File
  ( dirname
  , ensureDirectory
  , writeTextFile
  ) where

import Effect (Effect)
import Data.Unit (Unit)

foreign import dirname :: String -> String
foreign import ensureDirectory :: String -> Effect Unit
foreign import writeTextFile :: String -> String -> Effect Unit
