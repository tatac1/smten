
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeSynonymInstances #-}

module Smten.Compiled.Smten.Symbolic.Solver.Debug (debug) where

import System.IO

import qualified Smten.Runtime.Assert as A
import Smten.Runtime.Bit
import Smten.Runtime.Debug
import Smten.Runtime.FreeID
import Smten.Runtime.Model
import Smten.Runtime.SolverAST
import Smten.Runtime.Solver
import qualified Smten.Compiled.Smten.Smten.Base as S

data DebugLL = DebugLL {
    dbg_handle :: Handle
}

dbgPutStrLn :: DebugLL -> String -> IO ()
dbgPutStrLn dbg s = hPutStrLn (dbg_handle dbg) s

dbgModelVar :: DebugLL -> (FreeID, Any) -> IO ()
dbgModelVar dbg (n, BoolA x) = dbgPutStrLn dbg $ freenm n ++ " = " ++ show x
dbgModelVar dbg (n, IntegerA x) = dbgPutStrLn dbg $ freenm n ++ " = " ++ show x
dbgModelVar dbg (n, BitA x) = dbgPutStrLn dbg $ freenm n ++ " = " ++ show x

dbgModel :: DebugLL -> Model -> IO ()
dbgModel dbg m = mapM_ (dbgModelVar dbg) (m_vars m)


-- mark a debug object for sharing.
sh :: Debug -> Debug
sh x = dbgShare id x

op :: String -> DebugLL -> Debug -> Debug -> IO Debug
op o _ a b = return $ dbgOp o (sh a) (sh b)

instance SolverAST DebugLL Debug where
    declare dbg ty nm = do
        dbgPutStrLn dbg $ "declare " ++ nm ++ " :: " ++ show ty

    getBoolValue = error $ "Debug.getBoolValue: not implemented"
    getIntegerValue = error $ "Debug.getIntegerValue: not implemented"
    getBitVectorValue = error $ "Debug.getBitVectorValue: not implemented"
    check = error $ "Debug.check not implemented"

    assert dbg e = do
        dbgPutStrLn dbg "assert:"
        dbgstr <- dbgRender e
        dbgPutStrLn dbg $ dbgstr

    bool dbg b = return $ dbgLit b
    integer dbg i = return $ dbgLit i
    bit dbg w v = return $ dbgLit (bv_make w v)
    var dbg n = return $ dbgVar n

    and_bool = op "&&"
    or_bool = op "||"
    not_bool dbg x = return $ dbgApp (dbgText "!") (sh x)
    ite_bool dbg p a b = return $ dbgCase "True" (sh p) (sh a) (sh b)
    ite_integer dbg p a b = return $ dbgCase "True" (sh p) (sh a) (sh b)
    ite_bit dbg p a b = return $ dbgCase "True" (sh p) (sh a) (sh b)

    eq_integer = op "=="
    leq_integer = op "<="
    add_integer = op "+"
    sub_integer = op "-"

    eq_bit = op "=="
    leq_bit = op "<="
    add_bit = op "+"
    sub_bit = op "-"
    mul_bit = op "*"
    or_bit = op "|"
    and_bit = op "&"
    concat_bit = op "++"
    shl_bit d _ = op "<<" d
    lshr_bit d _ = op ">>" d
    not_bit dbg x = return $ dbgApp (dbgText "~") (sh x)
    sign_extend_bit dbg fr to x = return $ dbgText "?SignExtend"
    extract_bit dbg hi lo x = return $
      dbgApp (sh x) (dbgText $ "[" ++ show hi ++ ":" ++ show lo ++ "]")

debug :: S.List__ S.Char -> Solver -> IO Solver
debug fsmten s = do
  let f = S.toHSString fsmten
  fout <- openFile f WriteMode
  hSetBuffering fout NoBuffering
  let dbg = DebugLL fout
  return . Solver $ \formula -> do
     dbgPutStrLn dbg $ ""
     A.assert dbg formula
     dbgPutStrLn dbg $ "check... "
     res <- solve s formula
     case res of
       Just m -> do
           dbgPutStrLn dbg "Sat"
           dbgModel dbg m
           dbgPutStrLn dbg $ ""
           return (Just m)
       Nothing -> do
           dbgPutStrLn dbg "Unsat"
           dbgPutStrLn dbg $ ""
           return Nothing

