
module Seri.Lambda.TypeCheck (typecheck) where

import Data.Generics
import Data.List(nub)

import Seri.Failable
import Seri.Lambda.Env
import Seri.Lambda.IR
import Seri.Lambda.Ppr
import Seri.Lambda.Types


type TypeEnv = [(String, Type)]

-- Type check a flattened seri program.
-- fails if there is an error.
typecheck :: [Dec] -> Failable ()
typecheck ds = 
  let checkdec :: Dec -> Failable ()
      checkdec d@(ValD (TopSig n c t) e) =
        onfail (\s -> fail $ s ++ "\n in declaration " ++ pretty d) $ do
          checkexp [] e
          if (typeof e /= t)
            then fail $ "checkdec: expecting type " ++ pretty t ++ " in expression "
                        ++ pretty e ++ " but found type " ++ pretty (typeof e)
            else return ()
          instcheck ds c e

      -- TODO: shouldn't we check the type signatures don't have any partially
      -- applied types?
      checkdec (DataD {}) = return ()
      checkdec (ClassD {}) = return ()

      checkdec d@(InstD cls ms) =
        let checkmeth :: Method -> Failable () 
            checkmeth m@(Method n b) =
              onfail (\s -> fail $ s ++ "\n in method " ++ n) $ do
                checkexp [] b
                texpected <- lookupMethodType (mkenv ds n) cls
                if typeof b /= texpected
                    then fail $ "checkmeth: expected type " ++ pretty texpected
                            ++ " but found type " ++ pretty (typeof b)
                            ++ " in Method " ++ pretty m
                    else return ()
                -- TODO: use the context from the signature
                instcheck ds [] b
        in onfail (\s -> fail $ s ++ "\n in declaration " ++ pretty d) $ do
             mapM_ checkmeth ms
      checkdec d@(PrimD {}) = return ()

      checkpat :: Pat -> Failable [(Name, Type)]
      checkpat p@(ConP pt n ps) = do
         let ct = arrowsT ((map typeof ps) ++ [pt])
         texpected <- lookupDataConType (mkenv ds n)
         if isSubType texpected ct
            then return ()
            else fail $ "checkpat: expecting type " ++ pretty texpected ++ ", but found type " ++ pretty ct
         binds <- mapM checkpat ps
         let concated = concat binds
         if length concated /= length (nub (map fst concated))
            then fail $ "VarP appears multiple times in " ++ pretty p
            else return ()
         let twants = init (unarrowsT ct)
         let assertpat w p =
                if w == typeof p
                    then return () 
                    else fail $ "checkpat: expected type " ++ pretty w ++ " but found type " ++ pretty (typeof p) ++ " in pattern " ++ pretty p
         sequence [assertpat w p | (w, p) <- zip twants ps]
         return concated
      checkpat (VarP (Sig n t)) = return [(n, t)]
      checkpat (IntegerP i) = return []
      checkpat (WildP t) = return []
            

      checkmatch :: TypeEnv -> Match -> Failable ()
      checkmatch tenv (Match p b) = do
        bindings <- checkpat p
        checkexp (bindings ++ tenv) b

      -- checkexp tenv e
      -- Type check an expression.
      --    tenv - a mapping from bound variable name to type
      --    e - the expression to typecheck
      --  fails if expression does not type check.
      checkexp :: TypeEnv -> Exp -> Failable ()
      checkexp _ (IntegerE {}) = return ()
      checkexp tenv (CaseE e ms) = do
         checkexp tenv e 
         mapM_ (checkmatch tenv) ms
         let badpattypes = filter (\p -> typeof e /= typeof p) [p | Match p _ <- ms]
         if null badpattypes
            then return ()
            else fail $ "Expected type " ++ pretty (typeof e)
                        ++ " in pattern " ++ pretty (head (badpattypes))
                        ++ " but found type " ++ pretty (typeof (head (badpattypes)))
         let badmtypes = filter (\e -> typeof e /= typeof (head ms)) [e | Match _ e <- ms]
         if null badmtypes
            then return ()
            else fail $ "Expected type " ++ pretty (typeof e)
                        ++ " in match expression " ++ pretty (head (badmtypes))
                        ++ " but found type " ++ pretty (typeof (head (badmtypes)))
      checkexp tenv (AppE f x) = do    
         checkexp tenv f
         checkexp tenv x
         case typeof f of
            (AppT (AppT (ConT "->") a) _) ->
                if a == typeof x
                    then return ()
                    else fail $ "checkexp app: expected type " ++ pretty a ++
                        " but got type " ++ pretty (typeof x) ++
                        " in expression " ++ pretty x
            t -> fail $ "expected function type, but got type " ++ pretty t ++ " in expression " ++ pretty f
      checkexp tenv (LamE (Sig n t) e) = checkexp ((n, t):tenv) e
      checkexp _ c@(ConE s@(Sig n ct)) = do
         texpected <- lookupDataConType (mkenv ds n)
         if isSubType texpected ct
            then return ()
            else fail $ "checkexp: expecting type " ++ pretty texpected ++ ", but found type " ++ pretty ct ++ " in data constructor " ++ n
      checkexp tenv (VarE (Sig n t)) =
         case lookup n tenv of
             Just t' | t == t' -> return ()
             Just t' -> fail $ "expected variable of type " ++ pretty t'
                        ++ " but " ++ n ++ " has type " ++ pretty t
             Nothing -> do
                 texpected <- lookupVarType (mkenv ds n)
                 if isSubType texpected t
                     then return ()
                     else fail $ "expected variable of type " ++ pretty texpected
                                ++ " but " ++ n ++ " has type " ++ pretty t

  in mapM_ checkdec ds

-- | Verify all the needed class instances are either in the context or
-- declared for the given expression.
instcheck :: [Dec] -> Context -> Exp -> Failable ()
instcheck ds c e = 
    let base :: Exp -> Failable Exp
        base e@(VarE s) =
            case attemptM $ lookupVarInfo (mkenv ds s) of
                Just (Instance cls) | cls `elem` c -> return e
                Just (Instance cls) -> do
                    lookupInstD (mkenv ds cls)
                    return e
                _ -> return e
        base e = return e
    in do
        everywhereM (mkM base) e
        return ()
