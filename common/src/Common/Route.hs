{-# LANGUAGE EmptyCase #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE EmptyCase #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedStrings #-}

module Common.Route where

{- -- You will probably want these imports for composing Encoders.
import Prelude hiding (id, (.))
import Control.Category
-}

------------------------------------------------------------------------------
import           Control.Monad.Except
import           Data.Text (Text)
import qualified Data.Text as T
import           Data.Functor.Identity
import           Data.Functor.Sum
import qualified Obelisk.ExecutableConfig as ObConfig
import           Obelisk.Route
import           Obelisk.Route.TH
------------------------------------------------------------------------------

-- This needs to match the BackendRoute_GithubHook line below. Will figure out
-- how to make it DRY later.
githubHookPath :: Text
githubHookPath = "hook/github"

data BackendRoute :: * -> * where
  -- | Used to handle unparseable routes.
  BackendRoute_Missing :: BackendRoute ()
  BackendRoute_GithubHook :: BackendRoute ()
  BackendRoute_Ping :: BackendRoute ()
  BackendRoute_Websocket :: BackendRoute ()

data FrontendRoute :: * -> * where
  FrontendRoute_Main :: FrontendRoute ()
  FrontendRoute_Jobs :: FrontendRoute ()
  FrontendRoute_Repos :: FrontendRoute ()
  --FrontendRoute_Repos :: FrontendRoute (R CrudRoute)
  FrontendRoute_Accounts :: FrontendRoute ()
  -- This type is used to define frontend routes, i.e. ones for which the backend will serve the frontend.

type FullRoute = Sum BackendRoute (ObeliskRoute FrontendRoute)

backendRouteEncoder
  :: Encoder (Either Text) Identity (R FullRoute) PageName
backendRouteEncoder = handleEncoder (const (InL BackendRoute_Missing :/ ())) $
  pathComponentEncoder $ \case
    InL backendRoute -> case backendRoute of
      BackendRoute_Missing -> PathSegment "missing" $ unitEncoder mempty
      BackendRoute_GithubHook -> PathSegment "hook" $ unitEncoder (["github"], mempty)
      BackendRoute_Ping -> PathSegment "ping" $ unitEncoder mempty
      BackendRoute_Websocket -> PathSegment "ws" $ unitEncoder mempty
    InR obeliskRoute -> obeliskRouteSegment obeliskRoute $ \case
      -- The encoder given to PathEnd determines how to parse query parameters,
      -- in this example, we have none, so we insist on it.
      FrontendRoute_Main -> PathEnd $ unitEncoder mempty
      FrontendRoute_Jobs -> PathSegment "jobs" $ unitEncoder mempty
      FrontendRoute_Repos -> PathSegment "repos" $ unitEncoder mempty
      FrontendRoute_Accounts -> PathSegment "accounts" $ unitEncoder mempty

-- | Stolen from Obelisk as it is not exported. (Probably for a reason, but it
-- seems to do what we want right now.
pathOnlyEncoderIgnoringQuery :: (Applicative check, MonadError Text parse) => Encoder check parse [Text] PageName
pathOnlyEncoderIgnoringQuery = unsafeMkEncoder $ EncoderImpl
  { _encoderImpl_decode = \(path, _query) -> pure path
  , _encoderImpl_encode = \path -> (path, mempty)
  }

concat <$> mapM deriveRouteComponent
  [ ''BackendRoute
  , ''FrontendRoute
  ]

getAppRoute :: IO Text
getAppRoute = do
    mroute <- ObConfig.get "config/common/route"
    case mroute of
      Nothing -> fail "Error getAppRoute: config/common/route not defined"
      Just r -> return $ T.dropWhileEnd (== '/') $ T.strip r