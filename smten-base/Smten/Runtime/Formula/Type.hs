
module Smten.Runtime.Formula.Type (
   Type(..),
 ) where

-- | The types of Formula
data Type = BoolT | IntegerT | BitT Integer
    deriving (Show)

