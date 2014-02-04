
module Smten.Runtime.Model (
    Any(..),
    Model, model, m_vars, lookupBool, lookupInteger, lookupBit,
  ) where

import Smten.Runtime.Bit
import Smten.Runtime.FreeID

data Any = BoolA Bool | IntegerA Integer | BitA Bit

newtype Model = Model {
    m_vars :: [(FreeID, Any)]
}

instance Show Model where
    show = show . map fst . m_vars

model :: [(FreeID, Any)] -> IO Model
model vars = return (Model vars)

-- | Look up the boolean value for the given free variable in the model.
-- The given variable is assumed to have boolean type.
lookupBool :: Model -> FreeID -> Bool
lookupBool m nm =
  case lookup nm (m_vars m) of
    Just (BoolA x) -> x
    Just _ -> error "lookupBool: type mismatch"
    Nothing -> False    -- any value will do for the default.

-- | Look up the integer value for the given free variable in the model.
-- The given variable is assumed to have integer type.
lookupInteger :: Model -> FreeID -> Integer
lookupInteger m nm =
  case lookup nm (m_vars m) of
    Just (IntegerA x) -> x
    Just _ -> error "lookupInteger: type mismatch"
    Nothing -> 0        -- any value will do for the default.

-- | Look up the bit vector value for the given free variable in the model.
-- The given variable is assumed to have bit type for the given width.
lookupBit :: Model -> Integer -> FreeID -> Bit
lookupBit m w nm =
  case lookup nm (m_vars m) of
    Just (BitA x) -> x
    Just _ -> error "lookupBit: type mismatch"
    Nothing -> bv_make w 0 -- any value will do for the default
