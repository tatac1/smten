
{-# LANGUAGE NoImplicitPrelude, RebindableSyntax #-}
module Smten.Tests.SMT.Test (symtesteq, symtest) where

import Smten.Prelude
import Smten.Symbolic
import Smten.Tests.Test

symtesteq :: (Eq a) => String -> Maybe a -> [Solver] -> Symbolic a -> IO ()
symtesteq nm wnt slv q = symtest nm ((==) wnt) slv q

symtest :: String -> (Maybe a -> Bool) -> [Solver] -> Symbolic a -> IO ()
symtest nm tst slv q = mapM_ (symtest1 nm tst q) slv

symtest1 :: String -> (Maybe a -> Bool) -> Symbolic a -> Solver -> IO ()
symtest1 nm tst q slv = do
    putStrLn $ nm ++ "..."
    got <- run_symbolic slv q
    test nm (tst got)

