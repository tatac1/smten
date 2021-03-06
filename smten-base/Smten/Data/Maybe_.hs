
{-# LANGUAGE NoImplicitPrelude #-}
module Smten.Data.Maybe_ (
    Maybe(Nothing, Just), maybe,
    isJust, isNothing, fromJust, fromMaybe,
    listToMaybe, maybeToList, catMaybes, mapMaybe,
    ) where

-- Note: this module is hardwired in the smten plugin to generate code to
-- Smten.Compiled.Data.Maybe instead of Smten.Compiled.Smten.Data.Maybe_

import GHC.Base

data Maybe a = Nothing | Just a
    deriving (Eq, Ord)

instance Functor Maybe where
    fmap _ Nothing = Nothing
    fmap f (Just a) = Just (f a)

instance Monad Maybe where
    (Just x) >>= k      = k x
    Nothing  >>= _      = Nothing

    (Just _) >>  k      = k
    Nothing  >>  _      = Nothing

    return              = Just
    fail _              = Nothing
 

maybe :: b -> (a -> b) -> Maybe a -> b
maybe n _ Nothing = n
maybe _ f (Just x) = f x

isJust :: Maybe a -> Bool
isJust Nothing = False
isJust _ = True

isNothing :: Maybe a -> Bool
isNothing Nothing = True
isNothing _ = False

fromJust :: Maybe a -> a
fromJust Nothing = error "Maybe.fromJust: Nothing"
fromJust (Just x) = x

fromMaybe :: a -> Maybe a -> a
fromMaybe d x = case x of {Nothing -> d; Just v -> v}

maybeToList :: Maybe a -> [a]
maybeToList Nothing = []
maybeToList (Just x) = [x]

listToMaybe :: [a] -> Maybe a
listToMaybe [] = Nothing
listToMaybe (a:_) = Just a

catMaybes :: [Maybe a] -> [a]
catMaybes ls = [x | Just x <- ls]

mapMaybe :: (a -> Maybe b) -> [a] -> [b]
mapMaybe _ [] = []
mapMaybe f (x:xs) =
  let rs = mapMaybe f xs in
  case f x of
    Nothing -> rs
    Just r -> r:rs

