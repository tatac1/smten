
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeSynonymInstances #-}

module Smten.Runtime.Symbolic (
    Symbolic, return_symbolic, bind_symbolic, run_symbolic,
    fail_symbolic,
    IO, Maybe, Solver,
    ) where

import Control.Monad.State
import Data.Functor((<$>))

import Smten.Symbolic
import qualified Smten.SMT.Solver as SMT
import Smten.Runtime.Haskelly
import Smten.Runtime.SmtenHS
import qualified Smten.Runtime.Prelude as R
import Smten.SMT.FreeID
import Smten.SMT.Yices.Yices2
import Smten.SMT.DebugLL

data SS = SS {
    ss_pred :: R.Bool,
    ss_free :: [FreeID],
    ss_formula :: R.Bool
}

type Symbolic = State SS

instance (Haskelly ha sa) => Haskelly (Symbolic ha) (Symbolic sa) where
    frhs x = frhs <$> x
    tohs x = return (tohs' <$> x)

instance SmtenHS1 Symbolic where

return_symbolic :: a -> Symbolic a
return_symbolic = return

bind_symbolic :: Symbolic a -> (a -> Symbolic b) -> Symbolic b
bind_symbolic = (>>=)

fail_symbolic :: Symbolic a
fail_symbolic = do
    modify $ \ss -> ss { ss_formula = ss_formula ss `andB` notB (ss_pred ss) }
    return (error "fail_symbolic")

mksolver :: Solver -> IO (SMT.Solver)
mksolver Yices2 = yices2
mksolver (DebugLL dbg s) = do
    s' <- mksolver s
    debugll dbg s'
mksolver d = error $ "TODO: mksolver: " ++ show d

run_symbolic :: (SmtenHS0 a) => Solver -> Symbolic a -> IO (Maybe a)
run_symbolic s q = do
  solver <- mksolver s
  let (x, ss) = runState q (SS R.True [] R.True)
  SMT.assert solver (ss_formula ss)
  res <- SMT.check solver
  case res of
    SMT.Satisfiable -> do
       let vars = ss_free ss
       vals <- mapM (getBoolValue solver) vars
       return (Just (realize0 (zip vars vals) x))
    SMT.Unsatisfiable -> return Nothing

getBoolValue = error "todo: getBoolValue"
 
andB :: R.Bool -> R.Bool -> R.Bool
andB p q = R.__caseTrue p q R.False

notB :: R.Bool -> R.Bool
notB p = R.__caseTrue p R.False R.True
