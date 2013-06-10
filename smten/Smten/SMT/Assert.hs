
module Smten.SMT.Assert (Smten.SMT.Assert.assert) where

import Control.Monad.Reader
import System.Mem.StableName

import Data.Dynamic
import qualified Data.HashTable.IO as H

import Smten.Bit
import qualified Smten.Runtime.SmtenHS as S
import Smten.SMT.AST as AST
import Smten.SMT.FreeID

type BoolCache = H.BasicHashTable (StableName S.Bool) Dynamic
type IntegerCache = H.BasicHashTable (StableName S.Integer) Dynamic
type BitCache = H.BasicHashTable (StableName S.Bit) Dynamic

data AR ctx = AR {
  ar_ctx :: ctx,
  ar_bools :: BoolCache,
  ar_integers :: IntegerCache,
  ar_bits :: BitCache
}

type AM ctx = ReaderT (AR ctx) IO

assert :: AST ctx => ctx -> S.Bool -> IO ()
assert ctx p = {-# SCC "Assert" #-} do
    bc <- H.new
    ic <- H.new
    btc <- H.new
    e <- runReaderT (def_bool ctx p) (AR ctx bc ic btc)
    AST.assert ctx e

use_bool :: (AST ctx) => S.Bool -> AM ctx Dynamic
use_bool b = do
    nm <- liftIO $ makeStableName $! b
    bc <- asks ar_bools
    found <- liftIO $ H.lookup bc nm
    case found of
        Just v -> return v
        Nothing -> do
            ctx <- asks ar_ctx
            v <- def_bool ctx b
            liftIO $ H.insert bc nm v
            return v

use_int :: (AST ctx) => S.Integer -> AM ctx Dynamic
use_int i = do
    nm <- liftIO $ makeStableName $! i
    ic <- asks ar_integers
    found <- liftIO $ H.lookup ic nm
    case found of
        Just v -> return v
        Nothing -> do
            ctx <- asks ar_ctx
            v <- def_int ctx i
            liftIO $ H.insert ic nm v
            return v

use_bit :: (AST ctx) => S.Bit -> AM ctx Dynamic
use_bit i = do
    nm <- liftIO $ makeStableName $! i
    ic <- asks ar_bits
    found <- liftIO $ H.lookup ic nm
    case found of
        Just v -> return v
        Nothing -> do
            ctx <- asks ar_ctx
            v <- def_bit ctx i
            liftIO $ H.insert ic nm v
            return v

def_bool :: (AST ctx) => ctx -> S.Bool -> AM ctx Dynamic
def_bool ctx S.True = liftIO $ bool ctx True
def_bool ctx S.False = liftIO $ bool ctx False
def_bool ctx (S.BoolVar id) = liftIO $ var ctx (freenm id)
def_bool ctx (S.BoolMux p a b) = do
    p' <- use_bool p
    a' <- use_bool a
    b' <- use_bool b
    liftIO $ ite_bool ctx p' a' b'
def_bool ctx (S.Bool__EqInteger a b) = int_binary (eq_integer ctx) a b
def_bool ctx (S.Bool__LeqInteger a b) = int_binary (leq_integer ctx) a b
def_bool ctx (S.Bool__EqBit a b) = bit_binary (eq_bit ctx) a b
def_bool ctx (S.Bool__LeqBit a b) = bit_binary (leq_bit ctx) a b

def_int :: (AST ctx) => ctx -> S.Integer -> AM ctx Dynamic
def_int ctx (S.Integer i) = liftIO $ integer ctx i
def_int ctx (S.Integer_Add a b) = int_binary (add_integer ctx) a b
def_int ctx (S.Integer_Sub a b) = int_binary (sub_integer ctx) a b
def_int ctx (S.IntegerMux p a b) = do
    p' <- use_bool p
    a' <- use_int a
    b' <- use_int b
    liftIO $ ite_integer ctx p' a' b'
def_int ctx (S.IntegerVar id) = liftIO $ var ctx (freenm id)

int_binary :: (AST ctx) => (Dynamic -> Dynamic -> IO Dynamic) -> S.Integer -> S.Integer -> AM ctx Dynamic
int_binary f a b = do
    a' <- use_int a
    b' <- use_int b
    liftIO $ f a' b'

def_bit :: (AST ctx) => ctx -> S.Bit -> AM ctx Dynamic
def_bit ctx (S.Bit x) = liftIO $ bit ctx (bv_width x) (bv_value x)
def_bit ctx (S.Bit_Add a b) = bit_binary (add_bit ctx) a b
def_bit ctx (S.Bit_Sub a b) = bit_binary (sub_bit ctx) a b
def_bit ctx (S.Bit_Mul a b) = bit_binary (mul_bit ctx) a b
def_bit ctx (S.Bit_Or a b) = bit_binary (or_bit ctx) a b
def_bit ctx (S.BitMux p a b) = do
    p' <- use_bool p
    a' <- use_bit a
    b' <- use_bit b
    liftIO $ ite_bit ctx p' a' b'
def_bit ctx (S.BitVar id) = liftIO $ var ctx (freenm id)

bit_binary :: (AST ctx) => (Dynamic -> Dynamic -> IO Dynamic) -> S.Bit -> S.Bit -> AM ctx Dynamic
bit_binary f a b = do
    a' <- use_bit a
    b' <- use_bit b
    liftIO $ f a' b'

