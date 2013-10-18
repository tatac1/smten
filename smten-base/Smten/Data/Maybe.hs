
{-# LANGUAGE NoImplicitPrelude #-}
module Smten.Data.Maybe (
    Maybe(Nothing, Just), maybe,
    isJust, isNothing, fromJust, fromMaybe,
    listToMaybe, maybeToList, catMaybes, mapMaybe,
    ) where

import Smten.Control.Monad
import Smten.Data.Bool
import Smten.Data.Eq
import Smten.Data.Functor
import Smten.Data.List0
import Smten.Data.Show
import Smten.Smten.Base

data Maybe a = Nothing | Just a

instance (Eq a) => Eq (Maybe a) where
    (==) Nothing Nothing = True
    (==) (Just a) (Just b) = a == b
    (==) _ _ = False

instance (Show a) => Show (Maybe a) where
    show (Just x) = "Just " ++ show x
    show Nothing = "Nothing"

instance Functor Maybe where
    fmap _ Nothing = Nothing
    fmap f (Just a) = Just (f a)

instance Monad Maybe where
    (>>=) (Just v) f = f v
    (>>=) Nothing f = Nothing
    return = Just
    fail s = Nothing


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

