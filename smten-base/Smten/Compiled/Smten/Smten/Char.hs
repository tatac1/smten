
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE MagicHash #-}
{-# LANGUAGE NoImplicitPrelude #-}
module Smten.Compiled.Smten.Smten.Char (
    Char(..),
    toHSChar,
  ) where

import qualified Prelude as P
import qualified GHC.Types as P
import qualified GHC.Prim as P

import Smten.Runtime.Formula
import Smten.Runtime.SmtenHS
import Smten.Runtime.SymbolicOf

data Char =
    C# P.Char#
  | Char_Ite BoolF Char Char

instance SymbolicOf P.Char Char where
    tosym (P.C# x) = C# x

    symapp f x =
      case x of
        C# c -> f (P.C# c)
        Char_Ite p a b -> ite0 p (f $$ a) (f $$ b)

toHSChar :: Char -> P.Char
toHSChar (C# x) = P.C# x

instance SmtenHS0 Char where
    realize0 m x = 
      case x of
        C# {} -> x
        Char_Ite p a b -> iterealize p a b m
    ite0 = Char_Ite

