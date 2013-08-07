
{-# LANGUAGE NoImplicitPrelude #-}
module Smten.Data.Show0 (
   int_showsPrec, char_showsPrec, char_showList, integer_showsPrec
    ) where

import qualified Prelude as P
import Smten.Smten.Base
import Smten.Plugin.Annotations

{-# ANN module PrimitiveModule #-}

{-# NOINLINE int_showsPrec #-}
int_showsPrec :: Int -> Int -> String -> String
int_showsPrec = P.showsPrec

{-# NOINLINE integer_showsPrec #-}
integer_showsPrec :: Int -> Integer -> String -> String
integer_showsPrec = P.showsPrec

{-# NOINLINE char_showsPrec #-}
char_showsPrec :: Int -> Char -> String -> String
char_showsPrec = P.showsPrec

{-# NOINLINE char_showList #-}
char_showList :: [Char] -> String -> String
char_showList = P.showList

