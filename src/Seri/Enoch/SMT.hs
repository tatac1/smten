
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TypeSynonymInstances #-}

module Seri.Enoch.SMT (
    Query, Answer(..), 
    free, assert, query, run, run',
    runQuery, Y.RunOptions(..),
 ) where

import Control.Monad.State.Strict

import Seri.Lambda hiding (free, query)
import Seri.Enoch.Enoch
import Seri.Enoch.Prelude

import qualified Seri.SMT.Yices2 as Y

data Answer a =
    Satisfiable a
  | Unsatisfiable
  | Unknown
    deriving (Eq, Show)

instance SeriableT1 Answer where
    serit1 x = ConT (name "Answer")

instance (SeriableE a) => SeriableE (Answer a) where
    pack (Satisfiable x) =
      let satE :: (SeriableT a) => TExp (a -> Answer a)
          satE = conE "Satisfiable"
      in apply satE (pack x)
    pack Unsatisfiable =
      let unsatE :: (SeriableT a) => TExp (Answer a)
          unsatE = conE "Unsatisfiable"
      in unsatE
    pack Unknown =
      let unknownE :: (SeriableT a) => TExp (Answer a)
          unknownE = conE "Unknown"
      in unknownE

    unpack (TExp (AppE (ConE (Sig n _)) x)) | n Prelude.== name "Satisfiable" = do
        a <- unpack (TExp x)
        return $ Satisfiable a
    unpack (TExp (ConE (Sig n _))) | n Prelude.== name "Unsatisfiable" = return Unsatisfiable
    unpack (TExp (ConE (Sig n _))) | n Prelude.== name "Unknown" = return Unknown
    unpack _ = Nothing

                

type Query = StateT Y.SMTQuerier IO

instance SeriableT1 Query where
    serit1 _ = ConT (name "Query")

free :: (SeriableT a) => Query (TExp a)
free = 
    let freeE :: (SeriableT a) => TExp (Query a)
        freeE = varE "Seri.SMT.SMT.free"
    in run freeE

assert :: TExp Bool -> Query ()
assert p =
  let assertE :: TExp (Bool -> Query ())
      assertE = varE "Seri.SMT.SMT.assert"
  in run' (apply assertE p)

query :: (SeriableE a) => TExp a -> Query (Answer a)
query x = 
  let queryE :: (SeriableT a) => TExp (a -> Query (Answer a))
      queryE = varE "Seri.SMT.SMT.query"
  in run' (apply queryE x)

run :: TExp (Query a) -> Query (TExp a)
run (TExp x) = do
     s <- get
     (r, s') <- liftIO $ Y.runQuery s x
     put s'
     return (TExp r)

run' :: (SeriableE a) => TExp (Query a) -> Query a
run' x = fmap unpack' $ run x

runQuery :: Y.RunOptions -> Env -> Query a -> IO a
runQuery opts env q = do
    querier <- Y.mkQuerier opts env
    evalStateT q querier
    