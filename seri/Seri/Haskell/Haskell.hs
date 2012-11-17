-------------------------------------------------------------------------------
-- Copyright (c) 2012      SRI International, Inc. 
-- All rights reserved.
--
-- This software was developed by SRI International and the University of
-- Cambridge Computer Laboratory under DARPA/AFRL contract (FA8750-10-C-0237)
-- ("CTSRD"), as part of the DARPA CRASH research programme.
--
-- Redistribution and use in source and binary forms, with or without
-- modification, are permitted provided that the following conditions
-- are met:
-- 1. Redistributions of source code must retain the above copyright
--    notice, this list of conditions and the following disclaimer.
-- 2. Redistributions in binary form must reproduce the above copyright
--    notice, this list of conditions and the following disclaimer in the
--    documentation and/or other materials provided with the distribution.
--
-- THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
-- ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
-- IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
-- ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
-- FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
-- DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
-- OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
-- HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
-- LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
-- OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
-- SUCH DAMAGE.
-------------------------------------------------------------------------------
--
-- Authors: 
--   Richard Uhler <ruhler@csail.mit.edu>
-- 
-------------------------------------------------------------------------------

{-# LANGUAGE PatternGuards #-}

module Seri.Haskell.Haskell (
    haskell, haskellH,
    ) where

import Debug.Trace

import Data.List(nub)
import Data.Maybe(fromJust)

import qualified Language.Haskell.TH.PprLib as H
import qualified Language.Haskell.TH as H

import Seri.Failable
import Seri.Name
import Seri.Sig
import Seri.Type
import Seri.Lit
import Seri.Exp
import Seri.Dec
import Seri.Ppr
import Seri.Haskell.Compiler

hsLit :: Lit -> H.Lit
hsLit (IntegerL i) = H.IntegerL i
hsLit (CharL c) = H.CharL c

hsExp :: HCompiler -> Exp -> Failable H.Exp

-- String literals:
-- TODO: the template haskell pretty printer doesn't print strings correctly
-- if they contain newlines, thus, we can't print those as string literals.
-- When they fix the template haskell pretty printer, that special case should
-- be removed here.
hsExp c e | Just str <- de_stringE e
          , '\n' `notElem` str
          = return $ H.LitE (H.StringL str)
hsExp c e | Just xs <- de_listE e = do
  xs' <- mapM (hsExp c) xs
  return $ H.ListE xs'

hsExp c (LitE l) = return (H.LitE (hsLit l))
hsExp c (ConE (Sig n _)) = return $ H.ConE (hsName n)
hsExp c (VarE (Sig n t)) | unknowntype t = return $ H.VarE (hsName n)
hsExp c (VarE (Sig n t)) = do
    -- Give explicit type signature to make sure there are no type ambiguities
    ht <- hsType c t
    return $ H.SigE (H.VarE (hsName n)) ht
hsExp c (AppE f x) = do
    f' <- hsExp c f
    x' <- hsExp c x
    return $ H.AppE f' x'

hsExp c (LamE (Sig n _) x) = do
    x' <- hsExp c x
    return $ H.LamE [H.VarP (hsName n)] x'

hsExp c (CaseE x (Sig kn kt) y n) =
  let nwant = length (de_arrowsT kt) - 1
      getvars :: Int -> Exp -> ([Name], Exp)
      getvars 0 x = ([], x)
      getvars n (LamE (Sig nm _) x) = 
        let (vs, b) = getvars (n-1) x
        in (nm:vs, b)
      getvars _ e = error $ "getvars expected LamE, found: " ++ pretty e

      (vars, yv) = getvars nwant y
  in do
    x' <- hsExp c x
    yv' <- hsExp c yv
    n' <- hsExp c n
    return $ H.CaseE x' [
        H.Match (H.ConP (hsName kn) (map (H.VarP . hsName) vars)) (H.NormalB yv') [],
        H.Match H.WildP (H.NormalB n') []]
    
    
hsType :: HCompiler -> Type -> Failable H.Type
hsType c (ConT n) | n == name "Char" = return $ H.ConT (H.mkName "Prelude.Char")
hsType c (ConT n) | n == name "Integer" = return $ H.ConT (H.mkName "Prelude.Integer")
hsType c (ConT n) | n == name "IO" = return $ H.ConT (H.mkName "Prelude.IO")
hsType c (ConT n) | n == name "->" = return H.ArrowT
hsType c (ConT n) = return $ H.ConT (hsName n)
hsType c (AppT a b) = do
    a' <- hsType c a
    b' <- hsType c b
    return $ H.AppT a' b'
hsType c (VarT n) = return $ H.VarT (hsName n)
hsType c (NumT (ConNT i)) = return $ hsnt i
hsType c (NumT (VarNT n)) = return $ H.VarT (H.mkName (pretty n))
hsType c (NumT (AppNT f a b)) = do
    a' <- hsType c (NumT a)
    b' <- hsType c (NumT b)
    let f' = case f of
                "+" -> H.ConT $ H.mkName "N__PLUS"
                "-" -> H.ConT $ H.mkName "N__MINUS"
                "*" -> H.ConT $ H.mkName "N__TIMES"
                _ -> error $ "hsType TODO: AppNT " ++ f
    return $ H.AppT (H.AppT f' a') b'
hsType c t = throw $ "coreH does not apply to type: " ++ pretty t

-- Return the numeric type corresponding to the given integer.
hsnt :: Integer -> H.Type
hsnt 0 = H.ConT (H.mkName "N__0")
hsnt n = H.AppT (H.ConT (H.mkName $ "N__2p" ++ show (n `mod` 2))) (hsnt $ n `div` 2)

hsTopType :: HCompiler -> Context -> Type -> Failable H.Type
hsTopType c ctx t = do
    let ntvs = [H.ClassP (H.mkName "N__") [H.VarT (H.mkName (pretty n))] | n <- nvarTs t]
    t' <- hsType c t
    ctx' <- mapM (hsClass c) ctx
    case ntvs ++ ctx' of
        [] -> return t'
        ctx'' -> return $ H.ForallT (map (H.PlainTV . H.mkName . pretty) (nvarTs t ++ varTs t)) ctx'' t'

hsClass :: HCompiler -> Class -> Failable H.Pred
hsClass c (Class nm ts) = do
    ts' <- mapM (hsType c) ts
    return $ H.ClassP (hsName nm) ts'
    
hsMethod :: HCompiler -> Method -> Failable H.Dec
hsMethod c (Method n e) = do
    let hsn = hsName n
    e' <- hsExp c e
    return $ H.ValD (H.VarP hsn) (H.NormalB e') []


hsCon :: HCompiler -> Con -> Failable H.Con
hsCon c (Con n tys) = do
    ts <- mapM (hsType c) tys
    return $ H.NormalC (hsName n) (map (\t -> (H.NotStrict, t)) ts)
    
hsSig :: HCompiler -> TopSig -> Failable H.Dec
hsSig c (TopSig n ctx t) = do
    t' <- hsTopType c ctx t
    return $ H.SigD (hsName n) t'

    
hsDec :: HCompiler -> Dec -> Failable [H.Dec]
hsDec c (ValD (TopSig n ctx t) e) = do
    t' <- hsTopType c ctx t
    e' <- hsExp c e
    let hsn = hsName n
    let sig = H.SigD hsn t'
    let val = H.FunD hsn [H.Clause [] (H.NormalB e') []]
    return [sig, val]

hsDec _ (DataD n _ _) | n `elem` [
  name "Char",
  name "Integer",
  name "()",
  name "(,)",
  name "(,,)",
  name "(,,,)",
  name "(,,,,)",
  name "(,,,,,)",
  name "(,,,,,,)",
  name "(,,,,,,,)",
  name "(,,,,,,,,)",
  name "[]",
  name "Bit",
  name "IO"] = return []

hsDec c (DataD n tyvars constrs) = do
    cs <- mapM (hsCon c) constrs
    return [H.DataD [] (hsName n) (map (H.PlainTV . hsName . tyVarName) tyvars) cs []]

hsDec c (ClassD n vars sigs) = do
    sigs' <- mapM (hsSig c) sigs
    return $ [H.ClassD [] (hsName n) (map (H.PlainTV . hsName . tyVarName) vars) [] sigs']

hsDec c (InstD ctx (Class n ts) ms) = do
    let ntvs = [H.ClassP (H.mkName "N__") [H.VarT (H.mkName (pretty n))] | n <- concat $ map nvarTs ts]
    ctx' <- mapM (hsClass c) ctx
    ms' <- mapM (hsMethod c) ms
    ts' <- mapM (hsType c) ts
    let t = foldl H.AppT (H.ConT (hsName n)) ts'
    return [H.InstanceD (ntvs ++ ctx') t ms'] 

hsDec _ (PrimD (TopSig n _ t)) | n == name "Prelude.error" = do
  let e = H.VarE (H.mkName "Prelude.error")
  let val = H.FunD (H.mkName "error") [H.Clause [] (H.NormalB e) []]
  return [val]

hsDec c (PrimD s@(TopSig n _ _))
 | n == name "Prelude.__prim_add_Integer" = prim c s (vare "Prelude.+")
 | n == name "Prelude.__prim_sub_Integer" = prim c s (vare "Prelude.-")
 | n == name "Prelude.__prim_mul_Integer" = prim c s (vare "Prelude.*")
 | n == name "Prelude.__prim_show_Integer" = prim c s (vare "Prelude.show")
 | n == name "Prelude.<" = bprim c s "Prelude.<"
 | n == name "Prelude.<=" = bprim c s "Prelude.<="
 | n == name "Prelude.>" = bprim c s "Prelude.>"
 | n == name "Prelude.&&" = prim c s (vare "&&#")
 | n == name "Prelude.||" = prim c s (vare "||#")
 | n == name "Prelude.not" = prim c s (vare "not_")
 | n == name "Prelude.__prim_eq_Integer" = bprim c s "Prelude.=="
 | n == name "Prelude.__prim_eq_Char" = bprim c s "Prelude.=="
 | n == name "Prelude.valueof" = return []
 | n == name "Prelude.numeric" = return []
 | n == name "Seri.Bit.__prim_fromInteger_Bit" = prim c s (vare "Prelude.fromInteger")
 | n == name "Seri.Bit.__prim_eq_Bit" = bprim c s "Prelude.=="
 | n == name "Seri.Bit.__prim_add_Bit" = prim c s (vare "Prelude.+")
 | n == name "Seri.Bit.__prim_sub_Bit" = prim c s (vare "Prelude.-")
 | n == name "Seri.Bit.__prim_mul_Bit" = prim c s (vare "Prelude.*")
 | n == name "Seri.Bit.__prim_concat_Bit" = prim c s (vare "Bit.concat")
 | n == name "Seri.Bit.__prim_show_Bit" = prim c s (vare "Prelude.show")
 | n == name "Seri.Bit.__prim_not_Bit" = prim c s (vare "Bit.not")
 | n == name "Seri.Bit.__prim_or_Bit" = prim c s (vare "Bit.or")
 | n == name "Seri.Bit.__prim_and_Bit" = prim c s (vare "Bit.and")
 | n == name "Seri.Bit.__prim_shl_Bit" = prim c s (vare "Bit.shl")
 | n == name "Seri.Bit.__prim_lshr_Bit" = prim c s (vare "Bit.lshr")
 | n == name "Seri.Bit.__prim_zeroExtend_Bit" = prim c s (vare "Bit.zeroExtend")
 | n == name "Seri.Bit.__prim_truncate_Bit" = prim c s (vare "Bit.truncate")
 | n == name "Seri.Bit.__prim_extract_Bit" = prim c s (vare "Bit.extract")
 | n == name "Prelude.return_io" = prim c s (vare "Prelude.return")
 | n == name "Prelude.bind_io" = prim c s (vare "Prelude.>>=")
 | n == name "Prelude.nobind_io" = prim c s (vare "Prelude.>>")
 | n == name "Prelude.fail_io" = prim c s (vare "Prelude.fail")
 | n == name "Prelude.putChar" = prim c s (vare "Prelude.putChar")

hsDec _ d = throw $ "coreH does not apply to dec: " ++ pretty d

coreH :: HCompiler
coreH = Compiler hsExp hsType hsDec

haskellH :: HCompiler
haskellH = coreH

-- haskell builtin decs
--  Compile the given declarations to haskell.
haskell :: HCompiler -> [Dec] -> Name -> H.Doc
haskell c env main =
  let hsHeader :: H.Doc
      hsHeader = H.text "{-# LANGUAGE ExplicitForAll #-}" H.$+$
                 H.text "{-# LANGUAGE MultiParamTypeClasses #-}" H.$+$
                 H.text "{-# LANGUAGE FlexibleInstances #-}" H.$+$
                 H.text "import qualified Prelude" H.$+$
                 H.text "import Seri.Haskell.Lib.Numeric" H.$+$
                 H.text "import qualified Seri.Haskell.Lib.Bit as Bit" H.$+$
                 H.text "import Seri.Haskell.Lib.Bit(Bit)"

      ds = compile_decs c env
  in hsHeader H.$+$ H.ppr ds H.$+$
        H.text "main :: Prelude.IO ()" H.$+$
        H.text "main = " H.<+> H.text (pretty main)

-- | Declare a primitive seri implemented with the given haskell expression.
prim :: HCompiler -> TopSig -> H.Exp -> Failable [H.Dec]
prim c s@(TopSig nm ctx t) b = do
  let hsn = hsName nm
  sig <- hsSig c s
  let val = H.FunD hsn [H.Clause [] (H.NormalB b) []]
  return [sig, val]

vare :: String -> H.Exp
vare n = H.VarE (H.mkName n)

-- | Declare a binary predicate primitive in haskell.
bprim :: HCompiler -> TopSig -> String -> Failable [H.Dec]
bprim c s@(TopSig nm _ t) b = do    
  let hsn = hsName nm
  sig <- hsSig c s
  let val = H.FunD hsn [H.Clause
          [H.VarP (H.mkName "a"), H.VarP (H.mkName "b")]
              (H.NormalB (
                  H.CondE (H.AppE (H.AppE (vare b) (vare "a")) (vare "b"))
                          (H.ConE (H.mkName "True"))
                          (H.ConE (H.mkName "False"))
              )) []]
  return [sig, val]

unknowntype :: Type -> Bool
unknowntype (ConT {}) = False
unknowntype (AppT a b) = unknowntype a || unknowntype b
unknowntype (VarT {}) = True
unknowntype (NumT {}) = True    -- TODO: this may not be unknown, right?
unknowntype UnknownT = True


