module Silt.LSP
  ( LspState
  , initialLspState
  , handleLspMessage
  , renderJsonString
  , runLanguageServer
  ) where

import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import Data.Char (chr, digitToInt, isDigit, isHexDigit, isSpace, toLower)
import Data.List (intercalate, stripPrefix)
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import Silt.Lint (LintDiagnostic (..), lintSourceText)
import System.Exit (ExitCode (..), exitWith)
import System.IO
  ( BufferMode (NoBuffering)
  , Handle
  , hIsEOF
  , hSetBinaryMode
  , hSetBuffering
  , stdin
  , stdout
  )

data LspState = LspState
  { lspInitialized :: Bool
  , lspShutdownRequested :: Bool
  , lspDocuments :: Map.Map String String
  }
  deriving (Eq, Show)

initialLspState :: LspState
initialLspState = LspState False False Map.empty

data JsonValue
  = JsonNull
  | JsonBool Bool
  | JsonNumber String
  | JsonString String
  | JsonArray [JsonValue]
  | JsonObject [(String, JsonValue)]
  deriving (Eq, Show)

handleLspMessage :: LspState -> String -> (LspState, [String], Maybe ExitCode)
handleLspMessage state body =
  case parseJson body of
    Left err ->
      (state, [renderErrorResponse JsonNull (-32700) ("parse error: " ++ err)], Nothing)
    Right value ->
      case jsonStringAt ["method"] value of
        Nothing -> (state, [], Nothing)
        Just method ->
          case jsonLookup "id" value of
            Just requestId -> handleRequest state requestId method value
            Nothing -> handleNotification state method value

handleRequest :: LspState -> JsonValue -> String -> JsonValue -> (LspState, [String], Maybe ExitCode)
handleRequest state requestId method _value =
  case method of
    "initialize" ->
      (state {lspInitialized = True}, [renderInitializeResult requestId], Nothing)
    "shutdown" ->
      (state {lspShutdownRequested = True}, [renderResponse requestId JsonNull], Nothing)
    _ ->
      (state, [renderErrorResponse requestId (-32601) ("method not found: " ++ method)], Nothing)

handleNotification :: LspState -> String -> JsonValue -> (LspState, [String], Maybe ExitCode)
handleNotification state method value =
  case method of
    "initialized" ->
      (state, [], Nothing)
    "exit" ->
      (state, [], Just (if lspShutdownRequested state then ExitSuccess else ExitFailure 1))
    "textDocument/didOpen" ->
      if canProcessDocumentNotification state
        then case (jsonStringAt ["params", "textDocument", "uri"] value, jsonStringAt ["params", "textDocument", "text"] value) of
          (Just uri, Just text) ->
            let state' = state {lspDocuments = Map.insert uri text (lspDocuments state)}
             in (state', [renderTextDiagnostics uri text], Nothing)
          _ -> (state, [], Nothing)
        else (state, [], Nothing)
    "textDocument/didChange" ->
      if canProcessDocumentNotification state
        then case (jsonStringAt ["params", "textDocument", "uri"] value, lastTextChange value) of
          (Just uri, Just text) ->
            let state' = state {lspDocuments = Map.insert uri text (lspDocuments state)}
             in (state', [renderTextDiagnostics uri text], Nothing)
          _ -> (state, [], Nothing)
        else (state, [], Nothing)
    "textDocument/didClose" ->
      if canProcessDocumentNotification state
        then case jsonStringAt ["params", "textDocument", "uri"] value of
          Just uri ->
            let state' = state {lspDocuments = Map.delete uri (lspDocuments state)}
             in (state', [renderPublishDiagnostics uri []], Nothing)
          Nothing -> (state, [], Nothing)
        else (state, [], Nothing)
    _ ->
      (state, [], Nothing)

canProcessDocumentNotification :: LspState -> Bool
canProcessDocumentNotification state =
  lspInitialized state && not (lspShutdownRequested state)

lastTextChange :: JsonValue -> Maybe String
lastTextChange value = do
  JsonArray changes <- jsonAt ["params", "contentChanges"] value
  JsonObject fields <- lastMaybe changes
  case lookup "text" fields of
    Just (JsonString text) -> Just text
    _ -> Nothing

lastMaybe :: [a] -> Maybe a
lastMaybe values =
  case values of
    [] -> Nothing
    _ -> Just (last values)

renderTextDiagnostics :: String -> String -> String
renderTextDiagnostics uri text =
  renderPublishDiagnostics uri (lintSourceText (Just uri) text)

renderInitializeResult :: JsonValue -> String
renderInitializeResult requestId =
  renderResponse
    requestId
    ( JsonObject
        [ ( "capabilities"
          , JsonObject
              [ ( "textDocumentSync"
                , JsonObject
                    [ ("openClose", JsonBool True)
                    , ("change", JsonNumber "1")
                    ]
                )
              ]
          )
        , ( "serverInfo"
          , JsonObject
              [ ("name", JsonString "silt-lsp")
              , ("version", JsonString "0.1.0.0")
              ]
          )
        ]
    )

renderPublishDiagnostics :: String -> [LintDiagnostic] -> String
renderPublishDiagnostics uri diagnostics =
  renderJsonCompact
    ( JsonObject
        [ ("jsonrpc", JsonString "2.0")
        , ("method", JsonString "textDocument/publishDiagnostics")
        , ( "params"
          , JsonObject
              [ ("uri", JsonString uri)
              , ("diagnostics", JsonArray (map renderDiagnostic diagnostics))
              ]
          )
        ]
    )

renderDiagnostic :: LintDiagnostic -> JsonValue
renderDiagnostic diagnostic =
  JsonObject
    [ ( "range"
      , JsonObject
          [ ("start", JsonObject [("line", JsonNumber "0"), ("character", JsonNumber "0")])
          , ("end", JsonObject [("line", JsonNumber "0"), ("character", JsonNumber "1")])
          ]
      )
    , ("severity", JsonNumber "1")
    , ("source", JsonString "silt")
    , ("message", JsonString (lintDiagnosticMessage diagnostic))
    ]

renderResponse :: JsonValue -> JsonValue -> String
renderResponse requestId resultValue =
  renderJsonCompact
    ( JsonObject
        [ ("jsonrpc", JsonString "2.0")
        , ("id", requestId)
        , ("result", resultValue)
        ]
    )

renderErrorResponse :: JsonValue -> Int -> String -> String
renderErrorResponse requestId code message =
  renderJsonCompact
    ( JsonObject
        [ ("jsonrpc", JsonString "2.0")
        , ("id", requestId)
        , ( "error"
          , JsonObject
              [ ("code", JsonNumber (show code))
              , ("message", JsonString message)
              ]
          )
        ]
    )

runLanguageServer :: IO ()
runLanguageServer = do
  hSetBinaryMode stdin True
  hSetBinaryMode stdout True
  hSetBuffering stdin NoBuffering
  hSetBuffering stdout NoBuffering
  loop initialLspState
  where
    loop state = do
      message <- readLspMessage stdin
      case message of
        Nothing -> pure ()
        Just (Left err) -> do
          writeLspMessage (renderErrorResponse JsonNull (-32700) err)
          loop state
        Just (Right body) -> do
          let (state', responses, stopCode) = handleLspMessage state body
          mapM_ writeLspMessage responses
          case stopCode of
            Nothing -> loop state'
            Just code -> exitWith code

readLspMessage :: Handle -> IO (Maybe (Either String String))
readLspMessage handle = do
  eof <- hIsEOF handle
  if eof
    then pure Nothing
    else do
      headers <- readHeaders []
      case contentLength headers of
        Nothing -> pure Nothing
        Just lengthBytes -> do
          body <- BS.hGet handle lengthBytes
          if BS.length body /= lengthBytes
            then pure (Just (Left "short LSP message body"))
            else
              pure $
                Just $
                  case TextEncoding.decodeUtf8' body of
                    Left _ -> Left "invalid UTF-8 LSP message body"
                    Right text -> Right (Text.unpack text)
  where
    readHeaders headers = do
      line <- BSC.hGetLine handle
      let cleanLine = stripTrailingCR (BSC.unpack line)
      if null cleanLine
        then pure (reverse headers)
        else readHeaders (cleanLine : headers)

stripTrailingCR :: String -> String
stripTrailingCR text =
  case reverse text of
    '\r' : rest -> reverse rest
    _ -> text

contentLength :: [String] -> Maybe Int
contentLength headers =
  firstJust (map headerLength headers)
  where
    headerLength header = do
      rest <- stripPrefix "content-length:" (map toLower header)
      case reads (dropWhile isSpace rest) of
        [(value, rest')] | value >= 0 && all isSpace rest' -> Just value
        _ -> Nothing

firstJust :: [Maybe a] -> Maybe a
firstJust values =
  case values of
    [] -> Nothing
    Nothing : rest -> firstJust rest
    Just value : _ -> Just value

writeLspMessage :: String -> IO ()
writeLspMessage body =
  let bodyBytes = TextEncoding.encodeUtf8 (Text.pack body)
      header = BSC.pack ("Content-Length: " ++ show (BS.length bodyBytes) ++ "\r\n\r\n")
   in BS.hPut stdout (header <> bodyBytes)

jsonLookup :: String -> JsonValue -> Maybe JsonValue
jsonLookup key value =
  case value of
    JsonObject fields -> lookup key fields
    _ -> Nothing

jsonAt :: [String] -> JsonValue -> Maybe JsonValue
jsonAt path value =
  case path of
    [] -> Just value
    key : rest -> jsonLookup key value >>= jsonAt rest

jsonStringAt :: [String] -> JsonValue -> Maybe String
jsonStringAt path value =
  case jsonAt path value of
    Just (JsonString text) -> Just text
    _ -> Nothing

parseJson :: String -> Either String JsonValue
parseJson input = do
  (value, rest) <- parseValue (dropWhile isSpace input)
  case dropWhile isSpace rest of
    [] -> Right value
    _ -> Left "unexpected trailing JSON input"

parseValue :: String -> Either String (JsonValue, String)
parseValue input =
  case dropWhile isSpace input of
    '"' : rest -> do
      (text, rest') <- parseString rest
      Right (JsonString text, rest')
    '{' : rest -> parseObject [] (dropWhile isSpace rest)
    '[' : rest -> parseArray [] (dropWhile isSpace rest)
    't' : rest | Just rest' <- stripPrefix "rue" rest -> Right (JsonBool True, rest')
    'f' : rest | Just rest' <- stripPrefix "alse" rest -> Right (JsonBool False, rest')
    'n' : rest | Just rest' <- stripPrefix "ull" rest -> Right (JsonNull, rest')
    input'@(ch : _)
      | ch == '-' || isDigit ch -> parseNumber input'
    [] -> Left "unexpected end of JSON input"
    ch : _ -> Left ("unexpected JSON character: " ++ [ch])

parseObject :: [(String, JsonValue)] -> String -> Either String (JsonValue, String)
parseObject fields input =
  case dropWhile isSpace input of
    '}' : rest -> Right (JsonObject (reverse fields), rest)
    '"' : rest -> do
      (key, rest') <- parseString rest
      rest'' <- consumeChar ':' rest'
      (value, rest''') <- parseValue rest''
      case dropWhile isSpace rest''' of
        ',' : restNext -> parseObject ((key, value) : fields) restNext
        '}' : restNext -> Right (JsonObject (reverse ((key, value) : fields)), restNext)
        _ -> Left "expected ',' or '}' in JSON object"
    _ -> Left "expected object key"

parseArray :: [JsonValue] -> String -> Either String (JsonValue, String)
parseArray values input =
  case dropWhile isSpace input of
    ']' : rest -> Right (JsonArray (reverse values), rest)
    rest -> do
      (value, rest') <- parseValue rest
      case dropWhile isSpace rest' of
        ',' : restNext -> parseArray (value : values) restNext
        ']' : restNext -> Right (JsonArray (reverse (value : values)), restNext)
        _ -> Left "expected ',' or ']' in JSON array"

parseString :: String -> Either String (String, String)
parseString input =
  go [] input
  where
    go chars rest =
      case rest of
        [] -> Left "unterminated JSON string"
        '"' : rest' -> Right (reverse chars, rest')
        '\\' : escaped : rest' ->
          case escaped of
            '"' -> go ('"' : chars) rest'
            '\\' -> go ('\\' : chars) rest'
            '/' -> go ('/' : chars) rest'
            'b' -> go ('\b' : chars) rest'
            'f' -> go ('\f' : chars) rest'
            'n' -> go ('\n' : chars) rest'
            'r' -> go ('\r' : chars) rest'
            't' -> go ('\t' : chars) rest'
            'u' -> parseUnicode chars rest'
            _ -> Left ("unsupported JSON escape: \\" ++ [escaped])
        ch : rest' -> go (ch : chars) rest'

    parseUnicode chars rest =
      case splitAt 4 rest of
        (digits, rest') | length digits == 4 && all isHexDigit digits ->
          go (chr (foldl (\acc digit -> acc * 16 + digitToInt digit) 0 digits) : chars) rest'
        _ -> Left "bad JSON unicode escape"

parseNumber :: String -> Either String (JsonValue, String)
parseNumber input =
  let (number, rest) = span isJsonNumberChar input
   in if null number
        then Left "expected JSON number"
        else Right (JsonNumber number, rest)

isJsonNumberChar :: Char -> Bool
isJsonNumberChar ch =
  isDigit ch || ch == '-' || ch == '+' || ch == '.' || ch == 'e' || ch == 'E'

consumeChar :: Char -> String -> Either String String
consumeChar expected input =
  case dropWhile isSpace input of
    ch : rest | ch == expected -> Right rest
    _ -> Left ("expected '" ++ [expected] ++ "'")

renderJsonCompact :: JsonValue -> String
renderJsonCompact value =
  case value of
    JsonNull -> "null"
    JsonBool True -> "true"
    JsonBool False -> "false"
    JsonNumber number -> number
    JsonString text -> renderJsonString text
    JsonArray values -> "[" ++ intercalate "," (map renderJsonCompact values) ++ "]"
    JsonObject fields ->
      "{"
        ++ intercalate
          ","
          [renderJsonString key ++ ":" ++ renderJsonCompact fieldValue | (key, fieldValue) <- fields]
        ++ "}"

renderJsonString :: String -> String
renderJsonString text =
  "\"" ++ concatMap renderJsonChar text ++ "\""

renderJsonChar :: Char -> String
renderJsonChar ch =
  case ch of
    '"' -> "\\\""
    '\\' -> "\\\\"
    '\b' -> "\\b"
    '\f' -> "\\f"
    '\n' -> "\\n"
    '\r' -> "\\r"
    '\t' -> "\\t"
    _ | fromEnum ch < 32 -> renderJsonControl ch
    _ -> [ch]

renderJsonControl :: Char -> String
renderJsonControl ch =
  let value = fromEnum ch
      hex = "0123456789abcdef"
   in "\\u00" ++ [hex !! (value `div` 16), hex !! (value `mod` 16)]
