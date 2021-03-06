
{-# LANGUAGE PatternGuards #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NoImplicitPrelude #-}
module Smten.Compiled.Smten.Smten.Base (
    Char(..), Int(..), Integer(..),
    error,
    fromList__, toHSChar, toHSString, fromHSString,
    module Smten.Compiled.Smten.Smten.List,
    module Smten.Compiled.Smten.Smten.Tuple,
    module Smten.Compiled.Smten.Smten.Unit,
 )  where

import qualified Prelude as P

import Smten.Runtime.Formula
import Smten.Runtime.SmtenHS
import Smten.Runtime.SymbolicOf

import Smten.Compiled.Smten.Smten.Char
import Smten.Compiled.Smten.Smten.Int
import Smten.Compiled.Smten.Smten.Integer
import Smten.Compiled.Smten.Smten.List
import Smten.Compiled.Smten.Smten.Tuple
import Smten.Compiled.Smten.Smten.Unit

instance (SmtenHS0 a) => SymbolicOf [a] (List__ a) where
    tosym [] = __Nil__
    tosym (x:xs) = __Cons__ x (tosym xs)

    symapp f x = ite (gdNil__ x) (f []) (symapp (\xsl -> f ((flCons__1 x) : xsl)) (flCons__2 x))

instance SymbolicOf [P.Char] (List__ Char) where
    tosym [] = __Nil__
    tosym (x:xs) = __Cons__ (tosym x) (tosym xs)

    symapp f x = ite (gdNil__ x) (f []) (symapp2 (\xv xsv -> f (xv : xsv)) (flCons__1 x) (flCons__2 x))
                    
fromList__ :: List__ a -> [a]
fromList__ x
  | isTrueF (gdNil__ x) = []
  | isTrueF (gdCons__ x) = flCons__1 x : fromList__ (flCons__2 x)

error :: (SmtenHS0 a) => List__ Char -> a
error msg = {-# SCC "PRIM_ERROR" #-} P.error (toHSString msg)

-- Because there is no way to make use of an IO computation in constructing a
-- formula, it doesn't matter what we do with ite1 and unreachable1. So just
-- do nothing.
instance SmtenHS1 P.IO where
  ite1 _ _ _ = P.return unreachable
  unreachable1 = P.return unreachable

toHSString :: List__ Char -> P.String
toHSString x = P.map toHSChar (fromList__ x)

fromHSString :: P.String -> List__ Char
fromHSString x = tosym (P.map tosym x :: [Char])

