
{-# LANGUAGE PatternGuards #-}

module Seri.Lit (
    Lit(),
    integerL, de_integerL,
    charL, de_charL,
    ) where

import Data.Typeable
import Data.Dynamic

import Seri.Ppr

data Lit = Lit Dynamic
    deriving (Show)

instance Eq Lit where
    (==) a b
      | Just ai <- de_integerL a
      , Just bi <- de_integerL b = ai == bi
      | Just ac <- de_charL a
      , Just bc <- de_charL b = ac == bc
      | otherwise = False

dynamicL :: (Typeable a) => a -> Lit
dynamicL = Lit . toDyn

de_dynamicL :: (Typeable a) => Lit -> Maybe a
de_dynamicL (Lit x) = fromDynamic x

integerL :: Integer -> Lit
integerL = dynamicL

de_integerL :: Lit -> Maybe Integer
de_integerL = de_dynamicL

charL :: Char -> Lit
charL = dynamicL

de_charL :: Lit -> Maybe Char
de_charL = de_dynamicL

instance Ppr Lit where
    ppr l
      | Just i <- de_integerL l = integer i
      | Just c <- de_charL l = text (show c)

