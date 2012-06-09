
import System.Environment
import System.Exit
import System.Process

import Seri
import Seri.Lib.Prelude
import Seri.SMT.Yices

queryR = rules [yicesR, preludeR]

main :: IO ()
main = do
    args <- getArgs
    let (dbg, input) =
            case args of
               ["-d", dbgout, fin] -> (Just dbgout, readFile fin)
               ["-d", dbgout] -> (Just dbgout, getContents)
               [fin] -> (Nothing, readFile fin)
               [] -> (Nothing, getContents)
               x -> error $ "bad args: " ++ show x

    (ex, out, err) <- readProcessWithExitCode "which" ["yices"] ""
    yices <- case (ex, out) of
                (ExitSuccess, y) -> return $ head (words y)
                _ -> fail $ "Failed to find yices executable: " ++ err


    querytext <- input
    query <- parseDecs querytext
    let e = (mkenv query (VarE (Sig "main" (AppT (ConT "Query") (ConT "?"))) Declared))

    let opts = (RunOptions dbg yices)

    putStrLn $ "Using YICES: " ++ show yices
    putStrLn $ "Using Options: " ++ show opts

    result <- runYices queryR opts e
    putStrLn $ render (ppr result)
