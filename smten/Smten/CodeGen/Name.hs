
{-# LANGUAGE PatternGuards #-}

module Smten.CodeGen.Name (
    modprefix, 
    nameCG, qnameCG, tynameCG, qtynameCG,
    casenmCG, qcasenmCG,
    qhstynameCG, qhsnameCG,
    primnmCG, qprimnmCG,
    errnmCG, qerrnmCG,
    itenmCG, qitenmCG,
    iteflnmCG, qiteflnmCG,
    iteerrnmCG, qiteerrnmCG,
    nullitenmCG, qnullitenmCG, liftitenmCG, qliftitenmCG,
    ) where

import qualified Language.Haskell.TH.Syntax as H
import Data.Char (isAlphaNum)

import Smten.Name

-- doname ty f qlf nm
-- Transform a Smten name to a haskell name.
--  ty - True if this is a type constructor name.
--  f - transformation to perform on the base of the name.
--  qlf - True to generate a qualified version of the name.
--        False to generate an unqualified version of the name.
--  nm - The name to transform.
doname :: Bool -> (String -> String) -> Bool -> Name -> H.Name
doname ty f qlf nm = 
  let nm' = if ty then tytrans nm else trans nm
      base = f (unname (unqualified nm'))
      qlfn = unname $ qualification nm'
      qlfn' = if null qlfn
                    then ""
                    else modprefixs qlfn ++ "."
      qlfn'' = if qlf then qlfn' else ""
      full = qlfn'' ++ base
      sym = if issymbol base then "(" ++ full ++ ")" else full

      rebool | sym == "Smten.Lib.Prelude.True" = "Smten.True" 
             | sym == "Smten.Lib.Prelude.False" = "Smten.False" 
             | sym == "Smten.Lib.Prelude.__caseTrue" = "Smten.__caseTrue" 
             | sym == "Smten.Lib.Prelude.__caseFalse" = "Smten.__caseFalse" 
             | otherwise = sym
  in H.mkName rebool

trans :: Name -> Name
trans n
 | n == unitN = name "Prelude.Unit__"
 | n == nilN = name "Prelude.Nil__"
 | n == consN = name "Prelude.Cons__"
 | Just i <- de_tupleN n = name $ "Prelude.Tuple" ++ show i ++ "__"
 | otherwise = n

tytrans :: Name -> Name
tytrans n
 | n == unitN = name "Prelude.Unit__"
 | n == listN = name "Prelude.List__"
 | Just i <- de_tupleN n = name $ "Prelude.Tuple" ++ show i ++ "__"
 | otherwise = n
            

modprefix :: Name -> String
modprefix = modprefixs . unname

modprefixs :: String -> String
modprefixs n = "Smten.Lib." ++ n

issymbol :: String -> Bool
issymbol ('(':_) = False
issymbol "[]" = False
issymbol (h:_) = not $ isAlphaNum h || h == '_'

-- | Generate code for an unqualified variable or data constructor name.
nameCG :: Name -> H.Name
nameCG = doname False id False

-- qualified variable or data constructor name.
qnameCG :: Name -> H.Name
qnameCG = doname False id True

-- | Generate code for an unqualified type constructor name.
tynameCG :: Name -> H.Name
tynameCG = doname True id False

-- | qualified type constructor name.
qtynameCG :: Name -> H.Name
qtynameCG = doname True id True

casenmCG :: Name -> H.Name
casenmCG = doname False ("__case" ++) False

qcasenmCG :: Name -> H.Name
qcasenmCG = doname False ("__case" ++) True

-- qualified haskell type constructor name
qhstynameCG :: String -> Name -> H.Name
qhstynameCG s n
 | n == listN = H.mkName "[]"
 | n == unitN = H.mkName "()"
 | Just i <- de_tupleN n = H.mkName $ unname (unqualified n)
 | otherwise = H.mkName $ s ++ "." ++ (unname (unqualified n))

-- qualified haskell variable or data constructor name
qhsnameCG :: String -> Name -> H.Name
qhsnameCG s n 
 | n == nilN = H.mkName "[]"
 | n == consN = H.mkName "(:)"
 | n == unitN = H.mkName "()"
 | Just i <- de_tupleN n = H.mkName $ unname (unqualified n)
 | otherwise = H.mkName $ s ++ "." ++ (unname (unqualified n))

-- | Generate code for the prim constructor of a given data type.
primnmCG :: Name -> H.Name
primnmCG = doname True (++ "_Prim") False

-- | qualified type constructor name.
qprimnmCG :: Name -> H.Name
qprimnmCG = doname True (++ "_Prim") True

-- | Generate code for the err constructor of a given data type.
errnmCG :: Name -> H.Name
errnmCG = doname True (++ "_Error") False

-- | qualified type constructor name.
qerrnmCG :: Name -> H.Name
qerrnmCG = doname True (++ "_Error") True

-- | Generate code for the ite constructor of a given data type.
itenmCG :: Name -> H.Name
itenmCG = doname True (++ "_Ite") False

-- | qualified type constructor name.
qitenmCG :: Name -> H.Name
qitenmCG = doname True (++ "_Ite") True

iteflnmCG :: Name -> H.Name
iteflnmCG = doname False ("__ite" ++) False

qiteflnmCG :: Name -> H.Name
qiteflnmCG = doname False ("__ite" ++) True

iteerrnmCG ::  Name -> H.Name
iteerrnmCG = doname True ("__iteErr" ++) False

qiteerrnmCG :: Name -> H.Name
qiteerrnmCG = doname True ("__iteErr" ++) True

nullitenmCG :: Name -> H.Name
nullitenmCG = doname True ("__NullIte" ++) False

qnullitenmCG :: Name -> H.Name
qnullitenmCG = doname True ("__NullIte" ++) True

liftitenmCG :: Name -> H.Name
liftitenmCG = doname True ("__LiftIte" ++) False

qliftitenmCG :: Name -> H.Name
qliftitenmCG = doname True ("__LiftIte" ++) True
