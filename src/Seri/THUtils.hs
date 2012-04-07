
module Seri.THUtils (
    apply, arrowts, string, appts,
    ) where 

import Language.Haskell.TH

apply :: Name -> [Exp] -> Exp
apply n exps = foldl AppE (VarE n) exps

-- arrowts 
--  Turn a list of types [a, b, c, ...]
--  Into a type (a -> b -> c -> ...)
arrowts :: [Type] -> Type
arrowts [t] = t
arrowts (ta:tb:ts) = arrowts ((AppT (AppT ArrowT ta) tb) : ts)

-- appts
--  Turn a list of types [a, b, c, ...]
--  Into a type (a b c ...)
appts :: [Type] -> Type
appts ts = foldl1 AppT ts

string :: Name -> Exp
string n = LitE (StringL (nameBase n))

