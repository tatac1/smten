
module Smten.SMT.Assert (Smten.SMT.Assert.assert) where

import GHC.Base
import Unsafe.Coerce

import Control.Monad.Reader
import System.Mem.StableName

import qualified Data.HashTable.IO as H

import Smten.Bit
import Smten.Numeric
import qualified Smten.Runtime.SmtenHS as S
import Smten.Runtime.SmtenHS (Cases(..))
import Smten.SMT.Solver.Static as ST
import Smten.SMT.FreeID

type Cache exp = H.BasicHashTable (StableName Any) exp

data AR ctx exp = AR {
  ar_ctx :: ctx,
  ar_cache :: Cache exp
}

type AM ctx exp = ReaderT (AR ctx exp) IO

class Supported a where
    define :: (Solver ctx exp) => ctx -> a -> AM ctx exp exp
    ite :: (Solver ctx exp) => Cases a -> ctx -> exp -> exp -> exp -> IO exp

assert :: (Solver ctx exp) => ctx -> S.Bool -> IO ()
assert ctx p = {-# SCC "Assert" #-} do
    c <- H.new
    e <- runReaderT (define ctx p) (AR ctx c)
    ST.assert ctx e

use :: (Solver ctx exp, Supported a) => a -> AM ctx exp exp
use x = do
    nm <- liftIO $ makeStableName $! (unsafeCoerce x)
    c <- asks ar_cache
    found <- liftIO $ H.lookup c nm
    case found of
        Just v -> return v
        Nothing -> do
            ctx <- asks ar_ctx
            v <- define ctx x
            liftIO $ H.insert c nm v
            return v

unary :: (Solver ctx exp, Supported a) => (exp -> IO exp) -> a -> AM ctx exp exp
unary f a = do
    a' <- use a
    liftIO $ f a'

binary :: (Solver ctx exp, Supported a, Supported b) => (exp -> exp -> IO exp) -> a -> b -> AM ctx exp exp
binary f a b = do
    a' <- use a
    b' <- use b
    liftIO $ f a' b'

decases :: (Solver ctx exp, Supported a) => ctx -> Cases a -> AM ctx exp exp
decases ctx (Concrete c) = use c
decases ctx (Switch p a b) = do
    p' <- use p
    a' <- decases ctx a
    b' <- decases ctx b
    liftIO $ ite a ctx p' a' b'


instance Supported S.Bool where
    define ctx S.True = liftIO $ bool ctx True
    define ctx S.False = liftIO $ bool ctx False
    define ctx (S.Bool_Var id) = liftIO $ var ctx (freenm id)
    define ctx (S.Bool_EqInteger a b) = binary (eq_integer ctx) a b
    define ctx (S.Bool_LeqInteger a b) = binary (leq_integer ctx) a b
    define ctx (S.Bool_EqBit a b) = binary (eq_bit ctx) a b
    define ctx (S.Bool_LeqBit a b) = binary (leq_bit ctx) a b
    define ctx (S.Bool_Ite p a b) = do
        p' <- use p
        a' <- use a
        b' <- use b
        liftIO $ ite_bool ctx p' a' b'
    define ctx (S.Bool_Prim _ c) = decases ctx c
    define ctx (S.Bool_Error msg) = liftIO $ do
        id <- fresh
        declare_bool ctx (freenm id)
        var ctx (freenm id)

    ite _ = ite_bool
       
instance Supported S.Integer where
    define ctx (S.Integer i) = liftIO $ integer ctx i
    define ctx (S.Integer_Add a b) = binary (add_integer ctx) a b
    define ctx (S.Integer_Sub a b) = binary (sub_integer ctx) a b
    define ctx (S.Integer_Ite p a b) = do
        p' <- use p
        a' <- use a
        b' <- use b
        liftIO $ ite_integer ctx p' a' b'
    define ctx (S.Integer_Var id) = liftIO $ var ctx (freenm id)
    define ctx (S.Integer_Prim _ c) = decases ctx c
    define ctx (S.Integer_Error msg) = liftIO $ do
        id <- fresh
        declare_integer ctx (freenm id)
        var ctx (freenm id)

    ite _ = ite_integer

instance Supported (S.Bit n) where
    define ctx (S.Bit x) = liftIO $ bit ctx (bv_width x) (bv_value x)
    define ctx (S.Bit_Add a b) = binary (add_bit ctx) a b
    define ctx (S.Bit_Sub a b) = binary (sub_bit ctx) a b
    define ctx (S.Bit_Mul a b) = binary (mul_bit ctx) a b
    define ctx (S.Bit_Or a b) = binary (or_bit ctx) a b
    define ctx (S.Bit_And a b) = binary (and_bit ctx) a b
    define ctx (S.Bit_Shl a b) = binary (shl_bit ctx) a b
    define ctx (S.Bit_Lshr a b) = binary (lshr_bit ctx) a b
    define ctx (S.Bit_Concat a b) = binary (concat_bit ctx) a b
    define ctx (S.Bit_Not a) = unary (not_bit ctx) a
    define ctx x@(S.Bit_Extract a (S.Integer i)) =
       let bt :: S.Bit a -> a
           bt _ = undefined
           hi = i + valueof (bt x) - 1
           lo = i
       in unary (extract_bit ctx hi lo) a
    define ctx x@(S.Bit_SignExtend a) =
       let bt :: S.Bit m -> m
           bt _ = undefined

           by = valueof (bt x) - valueof (bt a)
       in unary (sign_extend_bit ctx by) a
    define ctx (S.Bit_Ite p a b) = do
        p' <- use p
        a' <- use a
        b' <- use b
        liftIO $ ite_bit ctx p' a' b'
    define ctx (S.Bit_Var id) = liftIO $ var ctx (freenm id)
    define ctx (S.Bit_Prim _ c) = decases ctx c
    define ctx (S.Bit_Error msg) = error "TODO: handle Bit_Error in Assert"

    ite _ = ite_bit

