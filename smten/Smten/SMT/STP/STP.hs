
{-# LANGUAGE PatternGuards #-}

module Smten.SMT.STP.STP (stp) where

import qualified Data.HashTable.IO as H

import Foreign
import Foreign.C.String
import Foreign.C.Types

import Data.Functor((<$>))

import Data.Dynamic

import Smten.SMT.STP.FFI
import Smten.SMT.AST
import qualified Smten.SMT.Assert as A
import qualified Smten.SMT.Solver as S

boxi :: [(Ptr STP_Expr, Integer)] -> Dynamic
boxi = toDyn

unboxi :: Dynamic -> [(Ptr STP_Expr, Integer)]
unboxi = flip fromDyn (error "STP.unboxi")

boxf :: Ptr STP_Expr -> Dynamic
boxf = toDyn

unboxf :: Dynamic -> Ptr STP_Expr
unboxf = flip fromDyn (error "STP.unboxf")

type VarMap = H.BasicHashTable String (Ptr STP_Expr)

data STP = STP {
    stp_ctx :: Ptr STP_VC,
    stp_vars :: VarMap
}

stp :: IO S.Solver
stp = do
  ptr <- c_vc_createValidityChecker
  vars <- H.new
  let s = STP { stp_ctx = ptr, stp_vars = vars }
  return $ S.Solver {
       S.assert = A.assert s,
       S.declare_bool = stpdeclare_bool s,
       S.declare_integer = nointegers,
       S.declare_bit = stpdeclare_bit s,
       S.getBoolValue = getBoolValue s,
       S.getIntegerValue = nointegers,
       S.getBitVectorValue = getBitVectorValue s,
       S.check = check s
    }

stpdeclare_bool :: STP -> String -> IO ()
stpdeclare_bool s nm = do
    st <- withvc s c_vc_boolType
    v <- withvc s $ \vc -> (withCString nm $ \cnm -> c_vc_varExpr vc cnm st)
    H.insert (stp_vars s) nm v

stpdeclare_bit :: STP -> String -> Integer -> IO ()
stpdeclare_bit s nm w = do
    st <- withvc s $ \vc -> c_vc_bvType vc (fromInteger w)
    v <- withvc s $ \vc -> (withCString nm $ \cnm -> c_vc_varExpr vc cnm st)
    H.insert (stp_vars s) nm v
        
withvc :: STP -> (Ptr STP_VC -> IO a) -> IO a
withvc s f = f (stp_ctx s)

-- To check for satisfiability, we query if False is valid. If False is
-- valid, the assertions imply False, meaning they are unsatisfiable. If
-- False is not valid, then there's some assignment which satisfies all
-- the assertions.
check :: STP -> IO S.Result
check s = do
    false <- withvc s c_vc_falseExpr
    r <- withvc s $ \vc -> c_vc_query vc false
    case r of
        0 -> return S.Satisfiable     -- False is INVALID
        1 -> return S.Unsatisfiable   -- False is VALID
        _ -> error $ "STP.check: vc_query returned " ++ show r

nointegers :: a
nointegers = error $ "STP does not support integers"

instance AST STP where
  assert s e = withvc s $ \vc -> c_vc_assertFormula vc (unboxf e)

  bool s True = boxf <$> withvc s c_vc_trueExpr
  bool s False = boxf <$> withvc s c_vc_falseExpr

  integer s i = do
    tt <- bool s True
    return (boxi [(unboxf tt, i)])

  bit s w v = withvc s $ \vc -> do
     let w' = fromInteger w
         v' = fromInteger v
     boxf <$> c_vc_bvConstExprFromLL vc w' v'

  var s nm = do
    vars <- H.lookup (stp_vars s) nm
    case vars of
        Just v -> return (boxf v)
        Nothing -> error $ "STP: unknown var: " ++ nm

  ite_bool s p a b = withvc s $ \vc -> boxf <$> c_vc_iteExpr vc (unboxf p) (unboxf a) (unboxf b)
  ite_bit s p a b = withvc s $ \vc -> boxf <$> c_vc_iteExpr vc (unboxf p) (unboxf a) (unboxf b)

  ite_integer s p a b = withvc s $ \vc -> do
    let join :: Ptr STP_Expr -> (Ptr STP_Expr, Integer) -> IO (Ptr STP_Expr, Integer)
        join p (a, v) = do
          pa <- c_vc_andExpr vc p a
          return (pa, v)
    not_p <- c_vc_notExpr vc (unboxf p)
    a' <- mapM (join (unboxf p)) (unboxi a)
    b' <- mapM (join not_p) (unboxi b)
    return $ boxi (a' ++ b')

  eq_integer = ibprim (==)
  leq_integer = ibprim (<=)
  add_integer = iiprim (+)
  sub_integer = iiprim (-)

  eq_bit = bprim c_vc_eqExpr
  leq_bit = bprim c_vc_bvLeExpr
  add_bit = blprim c_vc_bvPlusExpr
  sub_bit = blprim c_vc_bvMinusExpr
  mul_bit = error "TODO: STP mul_bit"
  or_bit = bprim c_vc_orExpr

bprim :: (Ptr STP_VC -> Ptr STP_Expr -> Ptr STP_Expr -> IO (Ptr STP_Expr))
      -> STP -> Dynamic -> Dynamic -> IO Dynamic
bprim f s a b = withvc s $ \vc -> boxf <$> f vc (unboxf a) (unboxf b)

blprim :: (Ptr STP_VC -> CInt -> Ptr STP_Expr -> Ptr STP_Expr -> IO (Ptr STP_Expr))
       -> STP -> Dynamic -> Dynamic -> IO Dynamic
blprim f s a b = withvc s $ \vc -> boxf <$> do
    n <- c_vc_getBVLength vc (unboxf a)
    f vc n (unboxf a) (unboxf b)

ibprim :: (Integer -> Integer -> Bool) 
       -> STP -> Dynamic -> Dynamic -> IO Dynamic
ibprim f s a b = withvc s $ \vc -> do
  let join :: (Ptr STP_Expr, Integer) -> (Ptr STP_Expr, Integer) -> IO (Ptr STP_Expr)
      join (pa, va) (pb, vb) = do
        pab <- c_vc_andExpr vc pa pb
        v <- bool s (f va vb)
        c_vc_andExpr vc pab (unboxf v)

      orN :: [Ptr STP_Expr] -> IO (Ptr STP_Expr)
      orN [] = unboxf <$> bool s False
      orN [x] = return x
      orN (x:xs) = do
        xs' <- orN xs
        c_vc_orExpr vc x xs'
  vals <- sequence [join ax bx | ax <- unboxi a, bx <- unboxi b]
  boxf <$> orN vals

iiprim :: (Integer -> Integer -> Integer) 
       -> STP -> Dynamic -> Dynamic -> IO Dynamic
iiprim f s a b = withvc s $ \vc -> do
  let join :: (Ptr STP_Expr, Integer) -> (Ptr STP_Expr, Integer) -> IO (Ptr STP_Expr, Integer)
      join (pa, va) (pb, vb) = do
        pab <- c_vc_andExpr vc pa pb
        let vab = f va vb
        return (pab, vab)
  boxi <$> sequence [join ax bx | ax <- unboxi a, bx <- unboxi b]

getBoolValue :: STP -> String -> IO Bool
getBoolValue s nm = do
    v <- var s nm
    val <- withvc s $ \vc -> c_vc_getCounterExample vc (unboxf v)
    b <- c_vc_isBool val
    case b of
        0 -> return False
        1 -> return True
        x -> error $ "STP.getBoolValue got value " ++ show x ++ " for " ++ nm

getBitVectorValue :: STP -> String -> Integer -> IO Integer
getBitVectorValue s nm w = do
    v <- var s nm
    val <- withvc s $ \vc -> c_vc_getCounterExample vc (unboxf v)
    fromIntegral <$> c_getBVUnsignedLongLong val
