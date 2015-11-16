{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE FlexibleInstances   #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies        #-}
{-# LANGUAGE TypeOperators       #-}

module Servant.Elm.Client where

import           Data.Proxy          (Proxy (Proxy))
import qualified Data.Text           as T
import           Elm                 (ToElmType, maybeToElmTypeSource,
                                      maybeToElmDecoderSource, toElmTypeName, toElmDecoderName)
import           GHC.TypeLits        (KnownSymbol, symbolVal)
import           Servant.API         ((:<|>) ((:<|>)), (:>), Capture, Get, Post,
                                      QueryFlag, QueryParam, QueryParams)
import           Servant.Foreign     (ArgType (..), QueryArg (..), Segment (..),
                                      SegmentType (..))

import           Servant.Elm.Request (Request (..), addArgName, setDecoder,
                                      addDecoderDef,
                                      addTypeDef, addFnName, addFnSignature,
                                      addUrlQueryStr, addUrlSegment, defRequest,
                                      setHttpMethod)

{-
TODO:
Servant API coverage
* MatrixFlag / MatrixParam / MatrixParams
* Header (request)
* Headers (response)
* Delete / Patch / Put / Raw?
* ReqBody
* Vault / RemoteHost / IsSecure

* Generate: use toString for params
* Generate Json encoders?
* ToText stuff for captures/params?
* Option to not use elm-export
-}


elmClient :: (HasElmClient layout)
          => Proxy layout -> ElmClient layout
elmClient p = elmClientWithRoute p defRequest


class HasElmClient layout where
  type ElmClient layout :: *
  elmClientWithRoute :: Proxy layout -> Request -> ElmClient layout


instance (HasElmClient a, HasElmClient b) => HasElmClient (a :<|> b) where
  type ElmClient (a :<|> b) = ElmClient a :<|> ElmClient b
  elmClientWithRoute Proxy result =
    elmClientWithRoute (Proxy :: Proxy a) result :<|>
    elmClientWithRoute (Proxy :: Proxy b) result


-- Capture name ArgType
instance (KnownSymbol capture, ToElmType a, HasElmClient sublayout)
      => HasElmClient (Capture capture a :> sublayout) where
  type ElmClient (Capture capture a :> sublayout) = ElmClient sublayout
  elmClientWithRoute Proxy result =
    elmClientWithRoute (Proxy :: Proxy sublayout)
                       ((addTypeDef (maybeToElmTypeSource argProxy)
                         . addFnSignature (toElmTypeName argProxy)
                         . addFnName "by"
                         . addArgName argName
                         . addUrlSegment (Segment (Cap (T.pack argName)))) result)
      where argProxy = Proxy :: Proxy a
            argName = symbolVal (Proxy :: Proxy capture)


-- QueryFlag name
instance (KnownSymbol sym, HasElmClient sublayout)
      => HasElmClient (QueryFlag sym :> sublayout) where
  type ElmClient (QueryFlag sym :> sublayout) = ElmClient sublayout
  elmClientWithRoute Proxy result =
    elmClientWithRoute (Proxy :: Proxy sublayout)
                       ((addArgName argName
                         . addFnSignature (toElmTypeName (Proxy :: Proxy Bool))
                         . addUrlQueryStr (QueryArg (T.pack argName) Flag)) result)
      where argName = symbolVal (Proxy :: Proxy sym)


-- QueryParam name ArgType
instance (KnownSymbol sym, ToElmType a, HasElmClient sublayout)
      => HasElmClient (QueryParams sym a :> sublayout) where
  type ElmClient (QueryParams sym a :> sublayout) = ElmClient sublayout
  elmClientWithRoute Proxy result =
    elmClientWithRoute (Proxy :: Proxy sublayout)
                       ((addArgName argName
                         . addTypeDef (maybeToElmTypeSource (Proxy :: Proxy [a]))
                         . addFnSignature (toElmTypeName (Proxy :: Proxy [a]))
                         . addUrlQueryStr (QueryArg (T.pack argName) List)) result)
      where argName = symbolVal (Proxy :: Proxy sym)


-- QueryParams name ArgType
instance (KnownSymbol sym, ToElmType a, HasElmClient sublayout)
      => HasElmClient (QueryParam sym a :> sublayout) where
  type ElmClient (QueryParam sym a :> sublayout) = ElmClient sublayout
  elmClientWithRoute Proxy result =
    elmClientWithRoute (Proxy :: Proxy sublayout)
                       ((addArgName argName
                         . addTypeDef (maybeToElmTypeSource (Proxy :: Proxy a))
                         . addFnSignature (toElmTypeName (Proxy :: Proxy a))
                         . addUrlQueryStr (QueryArg (T.pack argName) Normal)) result)
      where argName = symbolVal (Proxy :: Proxy sym)


-- Get '[cts] RequestType
instance {-# OVERLAPPABLE #-} (ToElmType apiRequest) => HasElmClient (Get (ct ': cts) apiRequest) where
  type ElmClient (Get (ct ': cts) apiRequest) = Request
  elmClientWithRoute Proxy =
    setHttpMethod "GET"
    . addFnSignature elmTypeName
    . addTypeDef (maybeToElmTypeSource apiRequestProxy)
    . addDecoderDef (maybeToElmDecoderSource apiRequestProxy)
    . setDecoder (toElmDecoderName apiRequestProxy)
    where
      apiRequestProxy = Proxy :: Proxy apiRequest
      elmTypeName = toElmTypeName apiRequestProxy


-- Get '[cts] ()
instance {-# OVERLAPPING #-} HasElmClient (Get (ct ': cts) ()) where
  type ElmClient (Get (ct ': cts) ()) = Request
  elmClientWithRoute Proxy =
    setHttpMethod "GET"
    . addFnSignature "()"
    . setDecoder "(succeed ())"


-- Post '[cts] RequestType
instance {-# OVERLAPPABLE #-} (ToElmType apiRequest) => HasElmClient (Post (ct ': cts) apiRequest) where
  type ElmClient (Post (ct ': cts) apiRequest) = Request
  elmClientWithRoute Proxy =
    setHttpMethod "POST"
    . addFnSignature elmTypeName
    . addTypeDef (maybeToElmTypeSource apiRequestProxy)
    . addDecoderDef (maybeToElmDecoderSource apiRequestProxy)
    . setDecoder (toElmDecoderName apiRequestProxy)
    where
      apiRequestProxy = Proxy :: Proxy apiRequest
      elmTypeName = toElmTypeName apiRequestProxy


-- Post '[cts] ()
instance {-# OVERLAPPING #-} HasElmClient (Post (ct ': cts) ()) where
  type ElmClient (Post (ct ': cts) ()) = Request
  elmClientWithRoute Proxy =
    setHttpMethod "POST"
    . addFnSignature "()"
    . setDecoder "(succeed ())"


-- path :> rest
instance (KnownSymbol path, HasElmClient sublayout) => HasElmClient (path :> sublayout) where
  type ElmClient (path :> sublayout) = ElmClient sublayout
  elmClientWithRoute Proxy result =
    elmClientWithRoute (Proxy :: Proxy sublayout)
                       ((addFnName p . addUrlSegment segment) result)
    where p = symbolVal (Proxy :: Proxy path)
          segment = Segment (Static (T.pack p))
