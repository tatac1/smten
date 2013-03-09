
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE PatternGuards #-}

module Smten.SMT.Symbolic (
    Used(..), Context, Contexts,
    Symbolic, runSymbolic,
    prim_free, assert, used,
    predicated,
    de_symbolicEH,
    ) where

import Control.Monad.State

import Data.Typeable
import Data.Unique

import Smten.Sig
import Smten.Name
import Smten.Type
import Smten.Lit
import Smten.Ppr
import Smten.ExpH

type Context = Unique
type Contexts = [Unique]

data Used a = Used Context a
    deriving (Typeable)

instance Functor Used where
    fmap f (Used ctx a) = Used ctx (f a)

data SS = SS {
    -- | Stack of currently active contexts
    ss_ctx :: Contexts,

    -- | Next free id to use for a free variables.
    ss_nfree :: Integer,

    -- | List of free variables created so far (in reverse order)
    ss_free :: [Sig],

    -- | assertions made (in reverse order).
    ss_asserts :: [ExpH]
}

newtype Symbolic a = Symbolic {
    symbolic_state :: State SS a
} deriving (Functor, Monad, Typeable)

deriving instance MonadState SS Symbolic

-- | Assert the given predicate.
assert :: ExpH -> Symbolic ()
assert p = modify $ \ss -> ss { ss_asserts = p : ss_asserts ss }

-- | Read the value of a Used.
used :: Used a -> Symbolic a
used (Used ctx v) = do
    ctxs <- gets ss_ctx
    if (ctx `elem` ctxs)
       then return $ v
       else error "used of ref in invalid context"

-- | Allocate a primitive free variable of the given type.
-- The underlying SMT solver must support this type for this to work.
prim_free :: Type -> Symbolic ExpH
prim_free t = do
    fid <- gets ss_nfree
    let f = Sig (name $ "free~" ++ show fid) t
    modify $ \ss -> ss { ss_nfree = fid+1, ss_free = f : ss_free ss }
    return (varEH f)

-- | Predicate the symbolic computation on the given smten Bool.
-- All assertions will only apply when the predicate is satisfied, otherwise
-- the assertions become vacuous.
predicated :: ExpH -> Symbolic a -> Symbolic a
predicated p s = do
    ss <- get
    let (v, ss') = runState (symbolic_state s) (ss { ss_asserts = [] })
        ssa' = [impliesEH p q | q <- ss_asserts ss']
    put (ss' { ss_asserts = ssa' ++ ss_asserts ss })
    return v

-- | Run a Symbolic computation.
-- Inputs:
--   ctx - the stack of currently active contexts
--   nfree - id to use for next free variable
--   s - the symbolic thing to run
-- Outputs: (nfree', free, asserts, val)
--   nfree' - the new id to use for next free variables
--   free - the primitive free variables created (in order of creation)
--   asserts - the assertions made (of type Bool) (in order of assertion)
--   val - the result of the computation.
runSymbolic :: Contexts -> Integer -> Symbolic a -> (Integer, [Sig], [ExpH], a)
runSymbolic ctx nfree s = 
    let (v, ss) = runState (symbolic_state s) (SS ctx nfree [] [])
    in (ss_nfree ss, reverse (ss_free ss), reverse (ss_asserts ss), v)

-- Convert an ExpH of smten type (Symbolic a) to it's corresponding haskell
-- Symbolic.
--
-- This handles execution of symbolic Symbolics, such as:
--  if p
--      then s1
--      else s2
de_symbolicEH :: ExpH -> Maybe (Symbolic ExpH)
de_symbolicEH e
 | Just l <- de_litEH e, s <- de_dynamicL l = s
 | CaseEH _ x k y n <- e =
    let yv = if 0 == length (de_arrowsT (typeof k)) - 1
                then y
                else -- TODO: in this case we need to extract the arguments from
                     -- the case match, which I just don't feel like doing yet.
                     error $ "TODO: de_symbolicEH of complex case expressions in: " ++ pretty e
        py = tcaseEH e (const trueEH) (const falseEH)
        pn = tcaseEH e (const falseEH) (const trueEH)
    in do
        ys <- de_symbolicEH yv
        ns <- de_symbolicEH n
        return $ do
            yr <- predicated py ys
            nr <- predicated pn ns
            return $ tcaseEH e (const yr) (const nr)
 | otherwise = Nothing
