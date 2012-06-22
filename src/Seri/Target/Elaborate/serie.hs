
import System.Environment

import Seri.Failable
import Seri.Lambda
import Seri.Target.Elaborate

main :: IO ()
main = do
    args <- getArgs
    let (output, path, mainexp, input) =
            case args of
               ["-o", fout, "-i", path, "-m", me, fin] ->
                    (writeFile fout, path, me, fin)
               ["-i", path, fin] -> (putStrLn, path, "main", fin)
               x -> error $ "bad args: " ++ show x

    seri <- load [path] input
    decs <- attemptIO $ typeinfer (flatten seri)
    attemptIO $ typecheck decs
    let e = mkenv decs (VarE (Sig mainexp UnknownT))
    elaborated <- elaborate elaborateR e
    output (pretty elaborated)
