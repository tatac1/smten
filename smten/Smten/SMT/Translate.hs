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

{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE PatternGuards #-}

-- Translate a Smten expression to SMT.
module Smten.SMT.Translate (
    smtT, smtE,
    ) where

import qualified Smten.SMT.Syntax as SMT

import Data.Functor

import Smten.Name hiding (smtN)
import Smten.Bit
import Smten.Lit
import Smten.Sig
import Smten.Ppr
import Smten.Type
import Smten.Exp
import Smten.Dec

-- | Convert a smten name to an SMT name.
smtN :: Name -> String
smtN = unname

-- | Compile a smten type to a smt type
smtT :: Type -> SMT.Type
smtT t
  | t == boolT = SMT.BoolT
  | t == integerT = SMT.IntegerT
  | t == charT = SMT.IntegerT
  | Just w <- de_bitT t = SMT.BitVectorT w
  | otherwise = error $ "smtT: unsupported type: " ++ pretty t

-- | Compile a smten expression to a smt expression.
smtE :: Exp -> SMT.Expression
smtE e
 | Just v <- de_integerE e = SMT.integerE v
 | Just v <- de_bitE e = SMT.mkbvE (bv_width v) (bv_value v)
 | Just b <- de_boolE e = if b then SMT.trueE else SMT.falseE
 | VarE _ (Sig n _) <- e = SMT.varE (smtN n)
 | LetE _ [] x <- e = smtE x
 | LetE l ((Sig n _, v):xs) x <- e =
     let rest = smtE (LetE l xs x)
     in SMT.letE [(smtN n, smtE v)] rest
 | AppE _ a b <- e =
    case de_appsE e of 
       (ConE _ s, args) -> error "SMT.Translate: unexpected constructor application"
       (VarE _ (Sig n _), [a, b]) | n == name "Prelude.__prim_lt_Integer" -> binary SMT.ltE a b
       (VarE _ (Sig n _), [a, b]) | n == name "Prelude.__prim_leq_Integer" -> binary SMT.leqE a b
       (VarE _ (Sig n _), [a, b]) | n == name "Prelude.__prim_gt_Integer" -> binary SMT.gtE a b
       (VarE _ (Sig n _), [a, b]) | n == name "Prelude.__prim_geq_Integer" -> binary SMT.geqE a b
       (VarE _ (Sig n _), [a, b]) | n == name "Prelude.__prim_add_Integer" -> binary SMT.addE a b
       (VarE _ (Sig n _), [a, b]) | n == name "Prelude.__prim_sub_Integer" -> binary SMT.subE a b
       (VarE _ (Sig n _), [a, b]) | n == name "Prelude.__prim_mul_Integer" -> binary SMT.mulE a b
       (VarE _ (Sig n _), [a, b]) | n == name "Prelude.__prim_eq_Integer" -> binary SMT.eqE a b
       (VarE _ (Sig n _), [a, b]) | n == name "Smten.Bit.__prim_eq_Bit" -> binary SMT.eqE a b
       (VarE _ (Sig n _), [a, b]) | n == name "Smten.Bit.__prim_lt_Bit" -> binary SMT.bvltE a b
       (VarE _ (Sig n _), [a, b]) | n == name "Smten.Bit.__prim_leq_Bit" -> binary SMT.bvleqE a b
       (VarE _ (Sig n _), [a, b]) | n == name "Smten.Bit.__prim_gt_Bit" -> binary SMT.bvgtE a b
       (VarE _ (Sig n _), [a, b]) | n == name "Smten.Bit.__prim_geq_Bit" -> binary SMT.bvgeqE a b
       (VarE _ (Sig n _), [a, b]) | n == name "Smten.Bit.__prim_add_Bit" -> binary SMT.bvaddE a b
       (VarE _ (Sig n _), [a, b]) | n == name "Smten.Bit.__prim_sub_Bit" -> binary SMT.bvsubE a b
       (VarE _ (Sig n _), [a, b]) | n == name "Smten.Bit.__prim_or_Bit" -> binary SMT.bvorE a b
       (VarE _ (Sig n _), [a, b]) | n == name "Smten.Bit.__prim_and_Bit" -> binary SMT.bvandE a b
       (VarE _ (Sig n _), [a, b]) | n == name "Smten.Bit.__prim_concat_Bit" -> binary SMT.bvconcatE a b
       (VarE _ (Sig n _), [a, b]) | n == name "Smten.Bit.__prim_shl_Bit" -> binary SMT.bvshlE a b
       (VarE _ (Sig n _), [a, b]) | n == name "Smten.Bit.__prim_lshr_Bit" -> binary SMT.bvlshrE a b
       (VarE _ (Sig n _), [a]) | n == name "Smten.Bit.__prim_not_Bit" -> SMT.bvnotE $ smtE a
       (VarE _ (Sig n t), [a])
            | n == name "Smten.Bit.__prim_zeroExtend_Bit"
            , Just (bs, bt) <- de_arrowT t
            , Just sw <- de_bitT bs
            , Just tw <- de_bitT bt
            -> SMT.bvzeroExtendE (smtE a) (tw - sw)
       (VarE _ (Sig n t), [a])
            | n == name "Smten.Bit.__prim_signExtend_Bit"
            , Just (bs, bt) <- de_arrowT t
            , Just sw <- de_bitT bs
            , Just tw <- de_bitT bt
            -> SMT.bvsignExtendE (smtE a) (tw - sw)
       (VarE _ (Sig n t), [a])
            | n == name "Smten.Bit.__prim_truncate_Bit"
            , Just (_, bt) <- de_arrowT t
            , Just tw <- de_bitT bt
            -> SMT.bvextractE (tw - 1) 0 (smtE a)
       (VarE _ (Sig n _), [x, li])
            | n == name "Smten.Bit.__prim_extract_Bit"
            , Just i <- de_integerE li
            , Just tw <- de_bitT (typeof e)
            -> SMT.bvextractE (i + tw - 1) i (smtE x)
       _ -> SMT.AppE (smtE a) [smtE b]
smtE l@(LamE {}) = error $ "lambda expression in smt target generation: " ++ show l
smtE (CaseE _ x (Sig nm _) y n)
  | nm == trueN = SMT.ifE (smtE x) (smtE y) (smtE n)
  | nm == falseN = SMT.ifE (smtE x) (smtE n) (smtE y)
smtE e@(CaseE {})
  = error $ "unsupported case expression in smt target generation: " ++ show e


binary :: (SMT.Expression -> SMT.Expression -> SMT.Expression)
           -> Exp -> Exp -> SMT.Expression
binary f a b = f (smtE a) (smtE b)

