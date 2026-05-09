module Silt.PackageDoc (docPackage) where

import Data.List (intercalate)
import Silt.Package
  ( Package (..)
  , PackageTarget (..)
  , PackageTargetKind (..)
  , readPackageFile
  )
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.Exit (die)
import System.FilePath ((</>), takeDirectory)

docPackage :: IO ()
docPackage = do
  let manifestPath = "Silt.pkg"
  exists <- doesFileExist manifestPath
  if exists
    then do
      packageResult <- readPackageFile manifestPath
      package <- either die pure packageResult
      let root = takeDirectory manifestPath
      let outDir = root </> "out" </> "silt" </> "doc"
      let outputPath = outDir </> "index.html"
      createDirectoryIfMissing True outDir
      writeFile outputPath (renderPackageDoc package)
      putStrLn ("Wrote package docs to " ++ outputPath)
    else die "missing Silt.pkg in current directory"

renderPackageDoc :: Package -> String
renderPackageDoc package =
  unlines
    [ "<!doctype html>"
    , "<html lang=\"en\">"
    , "<head>"
    , "  <meta charset=\"utf-8\">"
    , "  <title>Silt package: " ++ escapeHtml (packageName package) ++ "</title>"
    , "</head>"
    , "<body>"
    , "  <main>"
    , "    <h1>" ++ escapeHtml (packageName package) ++ "</h1>"
    , "    <p>Stage0 package documentation generated from Silt.pkg.</p>"
    , "    <h2>Targets</h2>"
    , "    <table>"
    , "      <thead>"
    , "        <tr><th>Kind</th><th>Name</th><th>Entry</th><th>Sources</th></tr>"
    , "      </thead>"
    , "      <tbody>"
    ]
    ++ concatMap renderTargetRow (packageTargets package)
    ++ unlines
      [ "      </tbody>"
      , "    </table>"
      , "  </main>"
      , "</body>"
      , "</html>"
      ]

renderTargetRow :: PackageTarget -> String
renderTargetRow target =
  unlines
    [ "        <tr>"
    , "          <td><code>" ++ escapeHtml (renderTargetKind (packageTargetKind target)) ++ "</code></td>"
    , "          <td><code>" ++ escapeHtml (packageTargetName target) ++ "</code></td>"
    , "          <td><code>" ++ escapeHtml (packageTargetEntry target) ++ "</code></td>"
    , "          <td>" ++ renderSourceList (packageTargetSources target) ++ "</td>"
    , "        </tr>"
    ]

renderSourceList :: [FilePath] -> String
renderSourceList paths =
  intercalate ", " ["<code>" ++ escapeHtml path ++ "</code>" | path <- paths]

renderTargetKind :: PackageTargetKind -> String
renderTargetKind kind =
  case kind of
    PackageBin -> "bin"
    PackageTest -> "test"

escapeHtml :: String -> String
escapeHtml =
  concatMap escapeChar

escapeChar :: Char -> String
escapeChar ch =
  case ch of
    '&' -> "&amp;"
    '<' -> "&lt;"
    '>' -> "&gt;"
    '"' -> "&quot;"
    '\'' -> "&#39;"
    _ -> [ch]
