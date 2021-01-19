{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}

module Code
  ( codeTypes,
    CodeTypes,
    CodeType (..),
    Code (..),
    collectCodes,
    topLevelElementToCode,
    topLevelTypeToCode,
    collectTypes,
    collectAttributes,
    topLevelAttributeCode,
  )
where

import qualified Data.Map as M
import Data.Text (Text, pack)
import qualified Data.Text as T
import Data.Vector (Vector, fromList)
import GHC.Generics (Generic)
import Model (Model, content, contentAttributes, fieldsOfAttribute, findFixedOf, topLevelAttribute, typeToText)
import Text.Mustache (ToMustache (..), object, (~>))
import Util
import qualified Xsd as X

data Code = Code
  { value :: Text,
    codeDescription :: Text,
    notes :: Text
  }
  deriving (Generic, Show, Eq)

instance ToMustache Code where
  toMustache Code {value, codeDescription, notes} =
    object
      [ "value" ~> value,
        "description" ~> codeDescription,
        "notes" ~> notes
      ]

data CodeType = CodeType
  { xmlReferenceName :: Text,
    description :: Text,
    codes :: Vector Code,
    spaceSeparatable :: Bool,
    elements :: [Model]
  }
  deriving (Generic, Show, Eq)

instance ToMustache CodeType where
  toMustache CodeType {xmlReferenceName, description, codes, spaceSeparatable, elements} =
    object
      [ "xmlReferenceName" ~> xmlReferenceName,
        "description" ~> description,
        "codes" ~> toMustache codes,
        "spaceSeparatable" ~> spaceSeparatable,
        "elements" ~> elements,
        "hasCodes" ~> not (null codes),
        "hasElements" ~> not (null elements)
      ]

type CodeTypes = Vector CodeType

codeTypes :: [CodeType] -> CodeTypes
codeTypes = fromList

typeAnnotations :: X.Type -> [X.Annotation]
typeAnnotations ty =
  case ty of
    (X.TypeSimple (X.AtomicType _ annotations)) -> annotations
    (X.TypeSimple (X.ListType _ annotations)) -> annotations
    (X.TypeSimple (X.UnionType _ annotations)) -> annotations
    (X.TypeComplex X.ComplexType {X.complexAnnotations}) -> complexAnnotations

typeConstraints :: X.Type -> [X.Constraint]
typeConstraints ty =
  case ty of
    (X.TypeSimple (X.AtomicType X.SimpleRestriction {X.simpleRestrictionConstraints} _)) -> simpleRestrictionConstraints
    (X.TypeSimple (X.ListType _ _)) -> []
    (X.TypeSimple (X.UnionType _ _)) -> []
    (X.TypeComplex X.ComplexType {X.complexAnnotations = _}) -> []

topLevelTypeToCode :: X.Schema -> (X.QName, X.Type) -> CodeType
topLevelTypeToCode _scm (_, X.TypeSimple (X.AtomicType _ _)) = throw Unreachable
topLevelTypeToCode scm (ref, X.TypeSimple (X.ListType ty _)) =
  case ty of
    X.Ref key_ ->
      -- NOTE: Codelists does not contain namespaces which refer to `http://www.editeur.org/onix/2.1/reference`
      let key = X.QName Nothing $ X.qnName key_
          t = (unwrap . M.lookup key . X.schemaTypes) scm
          spaceSeparatable_ = case key of
            X.QName {X.qnName = "List49"} -> True
            X.QName {X.qnName = "List91"} -> True
            _ -> False
          desc = (T.intercalate ". " . map (\(X.Documentation x) -> x) . typeAnnotations) t
          constraints = typeConstraints t
          codes_ =
            map
              ( \(X.Enumeration v docs) ->
                  let docs_ = map (\(X.Documentation d) -> d) docs
                   in Code {value = v, codeDescription = head docs_, notes = last docs_}
              )
              constraints
          refname = X.qnName ref
       in CodeType
            { xmlReferenceName = refname,
              description = desc,
              codes = fromList codes_,
              spaceSeparatable = spaceSeparatable_,
              elements = []
            }
    X.Inline _ -> throw Unreachable
topLevelTypeToCode _scm (_, X.TypeSimple (X.UnionType _ _)) = throw Unreachable
topLevelTypeToCode _scm (_, X.TypeComplex _) = throw Unreachable

topLevelElementToCode :: X.Schema -> X.ElementInline -> CodeType
topLevelElementToCode scm elm =
  let plainContentAttributes = contentAttributes elm
      keyOfType = case content elm of
        Just (X.ContentSimple (X.SimpleContentExtension X.SimpleExtension {X.simpleExtensionBase})) ->
          let qnName = X.qnName simpleExtensionBase
           in if T.isPrefixOf "List" qnName then Just simpleExtensionBase else Nothing
        Just (X.ContentSimple (X.SimpleContentRestriction _)) -> Nothing
        Just (X.ContentPlain X.PlainContent {}) -> Nothing
        Just (X.ContentComplex (X.ComplexContentExtension X.ComplexExtension {})) -> Nothing
        Just (X.ContentComplex (X.ComplexContentRestriction X.ComplexRestriction {})) -> Nothing
        Nothing -> Nothing
      spaceSeparatable_ = case keyOfType of
        Just X.QName {X.qnName = "List49"} -> True
        Just X.QName {X.qnName = "List91"} -> True
        Just _ -> False
        Nothing -> False
      ty = case keyOfType of
        Just key_ ->
          -- NOTE: Codelists does not contain namespaces which refer to `http://www.editeur.org/onix/2.1/reference`
          let key = X.QName Nothing $ X.qnName key_
           in (M.lookup key . X.schemaTypes) scm
        Nothing -> Nothing
      desc = case ty of
        Just t ->
          (T.intercalate ". " . map (\(X.Documentation x) -> x) . typeAnnotations) t
        Nothing -> pack ""
      codes_ = case ty of
        Just t ->
          let constraints = typeConstraints t
              enums =
                map
                  ( \(X.Enumeration v docs) ->
                      let docs_ = map (\(X.Documentation d) -> d) docs
                       in Code {value = v, codeDescription = head docs_, notes = last docs_}
                  )
                  constraints
           in enums
        Nothing -> []
      refname = unwrap $ findFixedOf "refname" plainContentAttributes
      elements =
        concatMap (fieldsOfAttribute scm)
          . filter topLevelAttribute
          $ plainContentAttributes
   in CodeType
        { xmlReferenceName = refname,
          description = desc,
          codes = fromList codes_,
          spaceSeparatable = spaceSeparatable_,
          elements = elements
        }

topLevelAttributeCode :: X.Schema -> X.Attribute -> CodeType
topLevelAttributeCode _scm (X.RefAttribute _) = throw Unreachable
topLevelAttributeCode _scm (X.AttributeGroupRef _) = throw Unreachable
topLevelAttributeCode _scm (X.AttributeGroupInline _ _) = throw Unreachable
topLevelAttributeCode scm (X.InlineAttribute X.AttributeInline {X.attributeInlineName, X.attributeInlineType}) =
  let name = X.qnName attributeInlineName
      typeName = case attributeInlineType of
        X.Ref n -> X.qnName n
        X.Inline t -> typeToText . X.TypeSimple $ t
      xmlReferenceName = case typeName of
        "string" -> T.toTitle name
        x -> if T.isPrefixOf "List" x then T.concat [T.toTitle name, x] else x
      ty = (M.lookup (X.QName Nothing typeName) . X.schemaTypes) scm
      codes_ = case ty of
        Just t ->
          let constraints = typeConstraints t
              enums =
                map
                  ( \(X.Enumeration v docs) ->
                      let docs_ = map (\(X.Documentation d) -> d) docs
                       in Code {value = v, codeDescription = head docs_, notes = last docs_}
                  )
                  constraints
           in enums
        Nothing -> []
      description = "has not document"
      spaceSeparatable = False
   in CodeType
        { xmlReferenceName = xmlReferenceName,
          description = description,
          codes = fromList codes_,
          elements = [],
          spaceSeparatable = spaceSeparatable
        }

collectCodes :: X.Schema -> [X.ElementInline]
collectCodes =
  map snd
    . M.toList
    . M.filter
      ( \x -> case content x of
          Just (X.ContentSimple (X.SimpleContentExtension X.SimpleExtension {X.simpleExtensionBase})) ->
            let qnName = X.qnName simpleExtensionBase
             in T.isPrefixOf "List" qnName
          Just (X.ContentSimple (X.SimpleContentRestriction _)) -> False
          Just (X.ContentPlain X.PlainContent {}) -> False
          Just (X.ContentComplex (X.ComplexContentExtension X.ComplexExtension {})) -> False
          Just (X.ContentComplex (X.ComplexContentRestriction X.ComplexRestriction {})) -> False
          Nothing -> False
      )
    . X.schemaElements

collectAttributes :: X.Schema -> [X.Attribute]
collectAttributes =
  concatMap snd
    . M.toList
    . M.map
      ( \case
          X.RefAttribute _ -> []
          X.InlineAttribute _ -> []
          X.AttributeGroupRef _ -> []
          X.AttributeGroupInline _ attrs -> attrs
      )
    . X.schemaAttributes

collectTypes :: X.Schema -> [(X.QName, X.Type)]
collectTypes =
  M.toList
    . M.filter
      ( \case
          X.TypeSimple (X.AtomicType _ _) -> False
          X.TypeSimple (X.ListType _ _) -> True
          X.TypeSimple (X.UnionType _ _) -> False
          X.TypeComplex _ -> False
      )
    . X.schemaTypes

instance GenSchema CodeTypes where
  readSchema = do
    xsd <- X.getSchema "./schema/2p1/ONIX_BookProduct_Release2.1_reference.xsd"
    let codeTypesFromTypes = (map (topLevelTypeToCode xsd) . collectTypes) xsd
        codeTypesFromElements = (map (topLevelElementToCode xsd) . collectCodes) xsd
        codeTypesFromAttributes = (map (topLevelAttributeCode xsd) . collectAttributes) xsd
    return $ codeTypes (codeTypesFromTypes ++ codeTypesFromElements ++ codeTypesFromAttributes)
