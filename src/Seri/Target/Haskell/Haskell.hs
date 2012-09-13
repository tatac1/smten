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

module Seri.Target.Haskell.Haskell (
    haskell, haskellH,
    ) where

import Data.List(nub)
import Data.Maybe(fromJust)

import qualified Language.Haskell.TH.PprLib as H
import qualified Language.Haskell.TH as H

import Seri.Failable
import Seri.Lambda
import Seri.Target.Haskell.Compiler

hsLit :: Lit -> H.Lit
hsLit (IntegerL i) = H.IntegerL i
hsLit (CharL c) = H.CharL c

hsExp :: HCompiler -> Exp -> Failable H.Exp
hsExp c (LitE l) = return (H.LitE (hsLit l))
hsExp c (CaseE e ms) = do
    e' <- compile_exp c c e
    ms' <- mapM (hsMatch c) ms
    return $ H.CaseE e' ms'
hsExp c (AppE f x) = do
    f' <- compile_exp c c f
    x' <- compile_exp c c x
    return $ H.AppE f' x'
hsExp c (LamE (Sig n _) x) = do
    x' <- compile_exp c c x
    return $ H.LamE [H.VarP (hsName n)] x'
hsExp c (ConE (Sig n _)) = return $ H.ConE (hsName n)
hsExp c (VarE (Sig n _)) = return $ H.VarE (hsName n)

hsMatch :: HCompiler -> Match -> Failable H.Match
hsMatch c (Match p e) = do
    let p' = hsPat p
    e' <- compile_exp c c e
    return $ H.Match p' (H.NormalB $ e') []
    
hsPat :: Pat -> H.Pat
hsPat (ConP _ n ps) = H.ConP (hsName n) (map hsPat ps)
hsPat (VarP (Sig n _)) = H.VarP (hsName n)
hsPat (LitP l) = H.LitP (hsLit l)
hsPat (WildP _) = H.WildP

hsType :: HCompiler -> Type -> Failable H.Type
hsType c (ConT n) | n == name "->" = return H.ArrowT
hsType c (ConT n) = return $ H.ConT (hsName n)
hsType c (AppT a b) = do
    a' <- compile_type c c a
    b' <- compile_type c c b
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
hsType c t = fail $ "coreH does not apply to type: " ++ pretty t

-- Return the numeric type corresponding to the given integer.
hsnt :: Integer -> H.Type
hsnt 0 = H.ConT (H.mkName "N__0")
hsnt n = H.AppT (H.ConT (H.mkName $ "N__2p" ++ show (n `mod` 2))) (hsnt $ n `div` 2)

hsTopType :: HCompiler -> Context -> Type -> Failable H.Type
hsTopType c ctx t = do
    let ntvs = [H.ClassP (H.mkName "N__") [H.VarT (H.mkName (pretty n))] | n <- nvarTs t]
    t' <- compile_type c c t
    ctx' <- mapM (hsClass c) ctx
    case ntvs ++ ctx' of
        [] -> return t'
        ctx'' -> return $ H.ForallT (map (H.PlainTV . H.mkName . pretty) (nvarTs t ++ varTs t)) ctx'' t'

hsClass :: HCompiler -> Class -> Failable H.Pred
hsClass c (Class nm ts) = do
    ts' <- mapM (compile_type c c) ts
    return $ H.ClassP (hsName nm) ts'
    
hsMethod :: HCompiler -> Method -> Failable H.Dec
hsMethod c (Method n e) = do
    let hsn = hsName n
    e' <- compile_exp c c e
    return $ H.ValD (H.VarP hsn) (H.NormalB e') []


hsCon :: HCompiler -> Con -> Failable H.Con
hsCon c (Con n tys) = do
    ts <- mapM (compile_type c c) tys
    return $ H.NormalC (hsName n) (map (\t -> (H.NotStrict, t)) ts)
    
hsSig :: HCompiler -> TopSig -> Failable H.Dec
hsSig c (TopSig n ctx t) = do
    t' <- hsTopType c ctx t
    return $ H.SigD (hsName n) t'

    
hsDec :: HCompiler -> Dec -> Failable [H.Dec]
hsDec c (ValD (TopSig n ctx t) e) = do
    t' <- hsTopType c ctx t
    e' <- compile_exp c c e
    let hsn = hsName n
    let sig = H.SigD hsn t'
    let val = H.FunD hsn [H.Clause [] (H.NormalB e') []]
    return [sig, val]

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
    ts' <- mapM (compile_type c c) ts
    let t = foldl H.AppT (H.ConT (hsName n)) ts'
    return [H.InstanceD (ntvs ++ ctx') t ms'] 

hsDec _ d = fail $ "coreH does not apply to dec: " ++ pretty d

coreH :: HCompiler
coreH = Compiler hsExp hsType hsDec

haskellH :: HCompiler
haskellH = compilers [preludeH, coreH]

-- haskell builtin decs
--  Compile the given declarations to haskell.
haskell :: HCompiler -> [Dec] -> Name -> H.Doc
haskell c env main =
  let hsHeader :: H.Doc
      hsHeader = H.text "{-# LANGUAGE ExplicitForAll #-}" H.$+$
                 H.text "{-# LANGUAGE MultiParamTypeClasses #-}" H.$+$
                 H.text "{-# LANGUAGE FlexibleInstances #-}" H.$+$
                 H.text "import qualified Prelude" H.$+$
                 H.text "import Seri.Target.Haskell.Lib.Numeric" H.$+$
                 H.text "import qualified Seri.Target.Haskell.Lib.Bit as Bit" H.$+$
                 H.text "import Seri.Target.Haskell.Lib.Bit(Bit)"

      ds = compile_decs c env
  in hsHeader H.$+$ H.ppr ds H.$+$
        H.text "main :: Prelude.IO ()" H.$+$
        H.text "main = Prelude.putStrLn (case "
        H.<+> H.text (pretty main) H.<+> H.text " of { True -> \"True\"; False -> \"False\"})"


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


preludeH :: HCompiler
preludeH =
  let me _ e = fail $ "preludeH does not apply to exp: " ++ pretty e

      mt _ (ConT n) | n == name "Char" = return $ H.ConT (H.mkName "Prelude.Char")
      mt _ (ConT n) | n == name "Integer" = return $ H.ConT (H.mkName "Prelude.Integer")
      mt _ t = fail $ "preludeH does not apply to type: " ++ pretty t

      md _ (PrimD (TopSig n _ t)) | n == name "Seri.Lib.Prelude.error" = do
        let e = H.VarE (H.mkName "Prelude.error")
        let val = H.FunD (H.mkName "error") [H.Clause [] (H.NormalB e) []]
        return [val]
      md _ (DataD n _ _) | n `elem` [
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
        name "[]"] = return []
      md c (PrimD s@(TopSig n _ _)) | n == name "Seri.Lib.Prelude.__prim_add_Integer" = prim c s (vare "Prelude.+")
      md c (PrimD s@(TopSig n _ _)) | n == name "Seri.Lib.Prelude.__prim_sub_Integer" = prim c s (vare "Prelude.-")
      md c (PrimD s@(TopSig n _ _)) | n == name "Seri.Lib.Prelude.__prim_mul_Integer" = prim c s (vare "Prelude.*")
      md c (PrimD s@(TopSig n _ _)) | n == name "Seri.Lib.Prelude.<" = bprim c s "Prelude.<"
      md c (PrimD s@(TopSig n _ _)) | n == name "Seri.Lib.Prelude.<=" = bprim c s "Prelude.<="
      md c (PrimD s@(TopSig n _ _)) | n == name "Seri.Lib.Prelude.>" = bprim c s "Prelude.>"
      md c (PrimD s@(TopSig n _ _)) | n == name "Seri.Lib.Prelude.&&" = prim c s (vare "&&#")
      md c (PrimD s@(TopSig n _ _)) | n == name "Seri.Lib.Prelude.||" = prim c s (vare "||#")
      md c (PrimD s@(TopSig n _ _)) | n == name "Seri.Lib.Prelude.not" = prim c s (vare "not_")
      md c (PrimD s@(TopSig n _ _)) | n == name "Seri.Lib.Prelude.__prim_eq_Integer" = bprim c s "Prelude.=="
      md c (PrimD s@(TopSig n _ _)) | n == name "Seri.Lib.Prelude.__prim_eq_Char" = bprim c s "Prelude.=="
      md c (PrimD s@(TopSig n _ _)) | n == name "Seri.Lib.Prelude.valueof" = return []
      md c (PrimD s@(TopSig n _ _)) | n == name "Seri.Lib.Prelude.numeric" = return []

      md c (DataD n _ _) | n == name "Bit" = return []
      md c (PrimD s@(TopSig n _ _)) | n == name "Seri.Lib.Bit.__prim_fromInteger_Bit" = prim c s (vare "Prelude.fromInteger")
      md c (PrimD s@(TopSig n _ _)) | n == name "Seri.Lib.Bit.__prim_eq_Bit" = bprim c s "Prelude.=="
      md c (PrimD s@(TopSig n _ _)) | n == name "Seri.Lib.Bit.__prim_add_Bit" = prim c s (vare "Prelude.+")
      md c (PrimD s@(TopSig n _ _)) | n == name "Seri.Lib.Bit.__prim_sub_Bit" = prim c s (vare "Prelude.-")
      md c (PrimD s@(TopSig n _ _)) | n == name "Seri.Lib.Bit.__prim_mul_Bit" = prim c s (vare "Prelude.*")
      md c (PrimD s@(TopSig n _ _)) | n == name "Seri.Lib.Bit.__prim_or_Bit" = prim c s (vare "Bit.or")
      md c (PrimD s@(TopSig n _ _)) | n == name "Seri.Lib.Bit.__prim_and_Bit" = prim c s (vare "Bit.and")
      md c (PrimD s@(TopSig n _ _)) | n == name "Seri.Lib.Bit.__prim_lsh_Bit" = prim c s (vare "Bit.lsh")
      md c (PrimD s@(TopSig n _ _)) | n == name "Seri.Lib.Bit.__prim_rshl_Bit" = prim c s (vare "Bit.rshl")
      md c (PrimD s@(TopSig n _ _)) | n == name "Seri.Lib.Bit.__prim_zeroExtend_Bit" = prim c s (vare "Bit.zeroExtend")
      md c (PrimD s@(TopSig n _ _)) | n == name "Seri.Lib.Bit.__prim_truncate_Bit" = prim c s (vare "Bit.truncate")

      md _ d = fail $ "preludeH does not apply to dec: " ++ pretty d
  in Compiler me mt md

