
{-# LANGUAGE NoImplicitPrelude #-}
module Smten.Data.Ix where

import Smten.Prelude

class (Ord a) => Ix a where
    range :: (a, a) -> [a]
    index :: (a, a) -> a -> Int

    rangeSize :: (a, a) -> Int
    rangeSize b@(l, h) = index b h + 1

instance Ix Int where
    range (l, h) = [l..h]
    index (l, h) x = x - l

instance Ix Integer where
    range (l, h) = [l..h]
    index (l, h) x = fromInteger (x - l)

instance (Ix a, Ix b) => Ix (a, b) where
    range ((l1,l2),(u1,u2)) =
        [ (i1,i2) | i1 <- range (l1,u1), i2 <- range (l2,u2) ]

    index ((l1,l2),(u1,u2)) (i1,i2) =
        index (l1,u1) i1 * rangeSize (l2,u2) + index (l2,u2) i2

instance (Ix a, Ix b, Ix c) => Ix (a, b, c) where
    range ((l1,l2,l3), (u1, u2, u3)) =
        [ (i1,i2,i3) | i1 <- range (l1,u1),
                       i2 <- range (l2,u2),
                       i3 <- range (l3,u3)]

    index ((l1,l2,l3),(u1,u2,u3)) (i1,i2,i3) =
      index (l3,u3) i3 + rangeSize (l3,u3) * (
        index (l2,u2) i2 + rangeSize (l2,u2) * (
          index (l1,u1) i1)) 


