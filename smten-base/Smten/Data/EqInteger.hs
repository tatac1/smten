
{-# LANGUAGE NoImplicitPrelude #-}
{-# OPTIONS_GHC -O #-}
module Smten.Data.EqInteger () where

import Smten.Smten.Base
import Smten.GHC.Classes
import Smten.GHC.Integer.Type

instance Eq Integer where
    (==) = eqInteger

