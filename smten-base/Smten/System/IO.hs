
{-# LANGUAGE NoImplicitPrelude, RebindableSyntax #-}

module Smten.System.IO (
    IO, FilePath,
    putChar, putStr, putStrLn, readFile, getContents,
 ) where

import qualified Prelude as P

import Smten.Smten.Base
import Smten.Data.Functor
import Smten.Control.Monad
import Smten.System.IO0

type FilePath = String

instance Functor IO where
    fmap f x = do
       v <- x
       return (f v)

instance Monad IO where
    return = return_io
    (>>=) = bind_io
    
putStr :: String -> IO ()
putStr s = mapM_ putChar s

putStrLn :: String -> IO ()
putStrLn s = do putStr s
                putStr "\n"

