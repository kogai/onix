{-# LANGUAGE LambdaCase #-}

module Xsd
  ( module Xsd.Types,
    module Xsd.Parser,
    Schema (..),
    getSchema,
    mergeSchemata,
  )
where

import Control.Monad.IO.Class
import Control.Monad.Trans.State
import Data.Map (Map)
import qualified Data.Map as Map
import Data.Maybe
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Network.HTTP.Client as Http
import qualified Network.HTTP.Client.TLS as Http
import Network.URI (URI)
import qualified Network.URI as URI
import System.FilePath
import Xsd.Parser
import Xsd.Types

data Schema = Schema
  { schemaTypes :: Map QName Type,
    schemaElements :: Map QName ElementInline,
    schemaAttributes :: Map QName Attribute
  }
  deriving (Show)

emptySchema :: Schema
emptySchema =
  Schema
    { schemaTypes = Map.empty,
      schemaElements = Map.empty,
      schemaAttributes = Map.empty
    }

mergeSchemata :: Schema -> Schema -> Schema
mergeSchemata s1 s2 =
  Schema
    { schemaTypes = schemaTypes s1 <> schemaTypes s2,
      schemaElements = schemaElements s1 <> schemaElements s2,
      schemaAttributes = schemaAttributes s1 <> schemaAttributes s2
    }

instance Semigroup Schema where
  (<>) = mergeSchemata

instance Monoid Schema where
  mempty = emptySchema

-- | Get schema from file or URL
getSchema :: String -> IO Schema
getSchema source = do
  uri <-
    maybe
      (fail "Can't parse the source URI")
      return
      (URI.parseURIReference source)
  mconcat <$> evalStateT (go uri []) Set.empty
  where
    go uri schemata = do
      skip <- gets (Set.member uri)
      if skip
        then return schemata
        else do
          xsd <- liftIO $ fetchXsd uri
          modify' (Set.insert uri)
          let schema = xsdToSchema xsd
              includes = flip mapMaybe (children xsd) $ \case
                ChildInclude i -> Just i
                _ -> Nothing
              imports =
                flip mapMaybe (children xsd) $ \case
                  ChildImport i -> Just i
                  _ -> Nothing
          goInclude uri includes (schema : schemata)
            >>= goImports uri imports

    goInclude _ [] schemata = return schemata
    goInclude uri (i : is) schemata = do
      let location = includeLocation i
      uri' <-
        maybe
          (fail ("Can't parse the location URI " <> show location))
          (return . combineURIs uri)
          (URI.parseURIReference (Text.unpack location))
      go uri' schemata
        >>= goInclude uri is

    goImports _ [] schemata = return schemata
    goImports uri (i : is) schemata =
      case importLocation i of
        Nothing -> goImports uri is schemata
        Just location -> do
          uri' <-
            maybe
              (fail ("Can't parse the location URI " <> show location))
              (return . combineURIs uri)
              (URI.parseURIReference (Text.unpack location))
          go uri' schemata
            >>= goImports uri is

-- | If the second URI is relative, then make it relative to the first one
combineURIs :: URI -> URI -> URI
combineURIs u1 u2
  | URI.uriIsAbsolute u2 = u2
  | isLocal u1 = u1 {URI.uriPath = dropFileName (URI.uriPath u1) </> URI.uriPath u2}
  | otherwise = u2 `URI.relativeTo` u1

xsdToSchema :: Xsd -> Schema
xsdToSchema xsd =
  Schema
    { schemaTypes = Map.fromList types,
      schemaElements = Map.fromList elements,
      schemaAttributes = Map.fromList attributes
    }
  where
    (types, elements, attributes) = go ([], [], []) (children xsd)
    go res [] = res
    go (ts, es, as) (c : cs) = case c of
      ChildType n t -> go ((n, t) : ts, es, as) cs
      ChildElement (InlineElement e) -> go (ts, (elementName e, e) : es, as) cs
      ChildAttribute (AttributeGroupInline n as') -> go (ts, es, (n, AttributeGroupInline n as') : as) cs
      _ -> go (ts, es, as) cs

fetchXsd :: URI -> IO Xsd
fetchXsd uri = do
  let path = URI.uriToString id uri ""
      onParseErr e = fail $ path ++ ": " ++ show e
  if isLocal uri
    then
      parseFile path
        >>= either onParseErr return
    else fetchHttp path

fetchHttp :: String -> IO Xsd
fetchHttp url = do
  mgr <- Http.newTlsManager
  req <- Http.parseUrlThrow url
  resp <- Http.responseBody <$> Http.httpLbs req mgr
  either onErr return $
    parseLazyByteString resp
  where
    onErr e = fail $ url ++ ": " ++ show e

isLocal :: URI -> Bool
isLocal uri = case URI.uriScheme uri of
  "http:" -> False
  "https:" -> False
  _ -> True
