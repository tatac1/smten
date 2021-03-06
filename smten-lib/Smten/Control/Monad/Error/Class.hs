
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE NoImplicitPrelude #-}
module Smten.Control.Monad.Error.Class (
    Error(..), MonadError(..),
    )  where

import Smten.Prelude

class Error a where
    noMsg :: a
    noMsg = strMsg ""

    strMsg :: String -> a
    strMsg _ = noMsg

instance Error String where
    noMsg = ""
    strMsg = id

class (Monad m) => MonadError e m | m -> e where
    throwError :: e -> m a
    catchError :: m a -> (e -> m a) -> m a

