
{-# LANGUAGE TemplateHaskell #-}

module Seri.Quoter (s) where

import Control.Monad.State
import Data.Maybe

import Language.Haskell.TH
import Language.Haskell.TH.Quote
import Language.Haskell.Meta.Parse

import qualified Seri.IR as SIR
import qualified Seri.Typed as S

import Seri.THUtils
import Seri.Canonical
import Seri.Declarations
import Seri.Slice

data UserState = UserState {
    boundnames :: [Name]
}

bindname :: Name -> State UserState ()
bindname nm = modify (\us -> us { boundnames = (nm:(boundnames us)) })

unbindname :: Name -> State UserState ()
unbindname nm = do
    UserState (n:names) <- get
    if (n /= nm) 
        then fail $ "unbindname '" ++ show nm ++ "' doesn't match expected '" ++ show n ++ "'"
        else put $ UserState names

-- declaredV name
-- Return a reference to a free seri variable declared in the top level
-- environment.
--   name - the seri name.
declaredV :: Name -> State UserState Exp
declaredV nm = return $ apply 'S.dvarE [VarE (declname nm), VarE (declidname nm), string nm]

-- declaredC
-- Return a reference to a free seri constructor declared in the top level
-- environment.
--   name - the seri name.
declaredC :: Name -> State UserState Exp
declaredC nm = return $ apply 'S.conE [VarE (declname nm), string nm]

-- mkexp :: Exp (a) -> Exp (S.Typed Exp a)
--   Convert a haskell expression to its corresponding typed seri
--   representation.
--
--   This supports only those haskell expressions which can be represented in
--   the seri IR.
mkexp :: Exp -> State UserState Exp 

-- Special case for slices.
mkexp e | sliceof e /= Nothing = return $ fromJust (sliceof e)

mkexp (VarE nm) = do
    bound <- gets boundnames
    if (nm `elem` bound)
        then return $ VarE nm
        else declaredV nm

mkexp (ConE nm) = declaredC nm

mkexp l@(LitE (IntegerL i)) = return $ apply 'S.integerE [l]


mkexp (AppE a b) = do
    a' <- mkexp a
    b' <- mkexp b
    return $ apply 'S.appE [a', b']

mkexp (LamE [VarP nm] a) = do
    bindname nm
    a' <- mkexp a
    unbindname nm
    return $ apply 'S.lamE [string nm, LamE [VarP nm] a']


mkexp (CondE p a b) = do
    p' <- mkexp p
    a' <- mkexp a
    b' <- mkexp b
    return $ apply 'S.ifE [p', a', b']

mkexp (CaseE e matches) = do
    e' <- mkexp e
    ms <- mapM mkmatch matches
    return $ apply 'S.caseE [e', ListE ms]

mkexp x = error $ "TODO: mkexp " ++ show x

mkmatch :: Match -> State UserState Exp
mkmatch (Match p (NormalB e) [])
  = let lamify :: [Name] -> Exp -> Exp
        lamify [] e = e
        lamify (n:ns) e = lamify ns (apply 'S.lamM [string n, LamE [VarP $ mkvarpnm n, VarP n] e])

        vns = varps p
        p' = mkpat p 
    in do
        mapM_ bindname vns
        e' <- mkexp e
        mapM_ unbindname (reverse vns)
        return $ lamify vns (apply 'S.match [p', e'])

-- Convert a haskell pattern to a Seri pattern.
mkpat :: Pat -> Exp
mkpat (ConP n ps) =
    let mkpat' :: Exp -> [Pat] -> Exp
        mkpat' e [] = e
        mkpat' e (p:ps) = mkpat' (apply 'S.appP [e, mkpat p]) ps
    in mkpat' (apply 'S.conP [string n]) ps
mkpat (VarP n) = VarE $ mkvarpnm n
mkpat (LitP i@(IntegerL _)) = apply 'S.integerP [LitE i]
mkpat WildP = VarE 'S.wildP
mkpat x = error $ "todo: mkpat " ++ show x

mkvarpnm :: Name -> Name
mkvarpnm nm = mkName ("p_" ++ (nameBase nm))

-- Get the list of variable pattern names in the given pattern.
varps :: Pat -> [Name]
varps (VarP nm) = [nm]
varps (ConP _ ps) = concat (map varps ps)
varps WildP = []
varps (LitP _) = []
varps (TupP ps) = concat (map varps ps)
varps (InfixP a n b) = varps a ++ varps b
varps (ListP ps) = concat (map varps ps)
varps p = error $ "TODO: varps " ++ show p


mkdecls :: [Dec] -> [Dec]
mkdecls [] = []
mkdecls (d@(DataD {}) : ds) = [d] ++ (decltype' d) ++ mkdecls ds

mkdecls ((SigD nm ty):(ValD (VarP _) (NormalB e) []):ds) = 
  let e' = fst $ runState (mkexp e) $ UserState []
      d = declval' nm ty e'
  in d ++ (mkdecls ds)

mkdecls ((InstanceD c t ids):ds) =
  let mkid :: Dec -> Dec
      mkid (ValD p (NormalB b) []) =
        let b' = fst $ runState (mkexp b) $ UserState []
        in ValD p (NormalB b') []
      
      ids' = map mkid ids
  in declinst' True (InstanceD c t ids') ++ mkdecls ds

mkdecls d = error $ "TODO: mkdecls " ++ show d

s :: QuasiQuoter 
s = QuasiQuoter qexp qpat qtype qdec

-- The seri expression quoter returns a haskell value of type
--  Typed Env Exp a
qexp :: String -> Q Exp
qexp s = do
    case (parseExp s) of
            Right e -> do
                let expr = fst $ runState (mkexp . canonical $ e) (UserState [])
                ClassI _ insts  <- reify ''SeriDec
                return $ envize expr insts
            Left err -> fail err

-- envize
-- Given an expression and a list of SeriDec class instances, return an
-- Env expression with the corresponding seri declarations.
envize :: Exp -> [ClassInstance] -> Exp
envize e insts =
  let tys = map (head . ci_tys) insts
      decs = map (\(ConT n) -> apply 'dec [ConE $ mkName (nameBase n)]) tys
  in apply 'S.enved [e, ListE decs]


qpat :: String -> Q Pat
qpat = error $ "Seri pattern quasi-quote not supported"

qtype :: String -> Q Type
qtype = error $ "Seri type quasi-quote not supported"

qdec :: String -> Q [Dec]
qdec s = case (parseDecs s) of
            Right decls -> return $ map fixUnit (mkdecls . canonical $ decls)
            Left err -> fail err

