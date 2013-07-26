
{-# LANGUAGE DataKinds, KindSignatures #-}
{-# LANGUAGE MultiParamTypeClasses #-}
module Smten.Compiled.Smten.Data.Bit0 (
    Bit, bv_eq, bv_leq, bv_show, bv_fromInteger, bv_add, bv_sub,
    ) where

import qualified Prelude as P
import qualified Smten.Runtime.Bit as P
import Smten.Runtime.SmtenHS
import Smten.Runtime.SymbolicOf
import Smten.Runtime.Types
import Smten.Compiled.Smten.Smten.Base

instance SymbolicOf P.Bit (Bit n) where
    tosym = Bit

    symapp f x = 
      case x of
        Bit b -> f b
        Bit_Ite p a b -> ite0 p (f $$ a) (f $$ b)
        Bit_Err msg -> error0 msg
        Bit_Prim r x -> primitive0 (\m -> realize m (f $$ (r m))) (f $$ x)
        _ -> P.error "symapp on non-ite symbolic bit vector"

bv_eq :: Bit n -> Bit n -> Bool
bv_eq = eq_Bit

bv_leq :: Bit n -> Bit n -> Bool
bv_leq = leq_Bit

bv_show :: Bit n -> List__ Char
bv_show = symapp P.$ \av -> fromHSString (P.show (av :: P.Bit))

bv_fromInteger :: P.Integer -> Integer -> Bit n
bv_fromInteger w = symapp P.$ \v -> Bit (P.bv_make w v)

bv_add :: Bit n -> Bit n -> Bit n
bv_add = add_Bit

bv_sub :: Bit n -> Bit n -> Bit n
bv_sub = sub_Bit

