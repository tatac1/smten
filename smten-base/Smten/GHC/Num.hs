
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE RebindableSyntax #-}
module Smten.GHC.Num (
    Num(..)
     ) where

import Smten.Smten.Base
import Smten.Data.Num0
import Smten.GHC.Integer.Type

infixl 7 *
infixl 6 +, -

class Num a where
    (+), (-), (*) :: a -> a -> a
    negate :: a -> a
    abs :: a -> a
    signum :: a -> a
    fromInteger :: Integer -> a

    {-# INLINE (-) #-}
    {-# INLINE negate #-}
    x - y = x + negate y
    negate x = 0 - x

instance Num Int where
    (+) = int_add
    (-) = int_sub
    (*) = int_mul
    abs = int_abs
    signum = int_signum
    fromInteger = int_fromInteger

instance Num Integer where
    (+) = integer_add
    (-) = integer_sub
    (*) = integer_mul
    fromInteger x = x

    abs = integer_abs
    signum = integer_signum
    
