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

{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TypeSynonymInstances #-}

-- | An abstract syntax suitable for both yices 1 and yices 2.
-- The syntax is restricted to what both yices1 and yices2 support, which is
-- basically the same thing as what yices2 supports.
module Yices.Syntax (
    YicesVersion(..),
    Symbol, Command(..), Typedef(..), Type(..), Expression(..),
    VarDecl, Binding, ImmediateValue(..),
    trueE, falseE, notE, varE, integerE, selectE, eqE, andE, ifE, ltE, gtE,
    addE, subE, mulE,
    tupleE, tupleUpdateE,
    mkbvE, bvaddE, bvorE, bvandE, bvshiftLeft0E, bvshiftRight0E,
    bvzeroExtendE, bvextractE, bvshlE,
    pretty,
  ) where

import Data.Ratio
import Text.PrettyPrint.HughesPJ

data YicesVersion = Yices1 | Yices2 deriving(Show, Eq)

type Symbol = String

data Command = 
    DefineType Symbol (Maybe Typedef)           -- ^ > (define-type <symbol> [<typedef>])
  | Define Symbol Type (Maybe Expression)       -- ^ > (define <symbol> :: <type> [<expression>])
  | Assert Expression                           -- ^ > (assert <expression>)
  | Check                                       -- ^ > (check)
  | Push                                        -- ^ > (push)
  | Pop                                         -- ^ > (pop)
    deriving(Show, Eq)

data Typedef =
    NormalTD Type           -- ^ > <type>
  | ScalarTD [Symbol]       -- ^ > (scalar <symbol> ... <symbol>)
    deriving(Show, Eq)
    

data Type = 
    VarT Symbol             -- ^ > <symbol>
  | TupleT [Type]           -- ^ > (tuple <type> ... <type>)
  | ArrowT [Type]           -- ^ > (-> <type> ... <type> <type>)
  | BitVectorT Integer      -- ^ > (bitvector <rational>)
  | IntegerT                -- ^ > int
  | BoolT                   -- ^ > bool
  | RealT                   -- ^ > real
    deriving(Show, Eq)

data Expression =
    ImmediateE ImmediateValue           -- ^ > <immediate-value>
  | ForallE [VarDecl] Expression        -- ^ > (forall (<var_decl> ... <var_decl>) <expression>)
  | ExistsE [VarDecl] Expression        -- ^ > (exists (<var_decl> ... <var_decl>) <expression>)
  | LetE [Binding] Expression           -- ^ > (let (<binding> ... <binding>) <expression>)
  | UpdateE Expression [Expression] Expression  -- ^ > (update <expression> (<expression> ... <expression>) <expression>)
  | TupleUpdateE Expression Integer Expression  -- ^ > (tuple-update <tuple> i <term>)
  | FunctionE Expression [Expression]   -- ^ > (<function> <expression> ... <expression>)
    deriving(Show, Eq)

type VarDecl = (String, Type)           -- ^ > <symbol> :: <type>
type Binding = (String, Expression)     -- ^ > (<symbol> <expression>)

data ImmediateValue =
    TrueV               -- ^ > true
  | FalseV              -- ^ > false
  | RationalV Rational  -- ^ > <rational>
  | VarV Symbol         -- ^ > symbol
    deriving(Show, Eq)

-- | > true
trueE :: Expression
trueE = ImmediateE TrueV

-- | > false
falseE :: Expression
falseE = ImmediateE FalseV

-- | > not e
notE :: Expression -> Expression
notE e = FunctionE (varE "not") [e]

-- | > A <symbol> expression.
varE :: String -> Expression
varE n = ImmediateE (VarV n)

-- | An integer expression.
integerE :: Integer -> Expression
integerE i = ImmediateE (RationalV (fromInteger i))

-- | > (select <tuple> i)
selectE :: Expression -> Integer -> Expression
selectE e i = FunctionE (varE "select") [e, integerE i]

-- | > (= <expression> <expression>)
eqE :: Expression -> Expression -> Expression
eqE a b = FunctionE (varE "=") [a, b]

-- | > (mk-tuple <term_1>  ... <term_n>)
tupleE :: [Expression] -> Expression
tupleE [] = error "tupleE: empty list"
tupleE args = FunctionE (varE "mk-tuple") args

-- | > (tuple-update <tuple> i <term>)
tupleUpdateE :: Expression -> Integer -> Expression -> Expression
tupleUpdateE = TupleUpdateE

-- | > (and <term_1> ... <term_n>)
andE :: [Expression] -> Expression
andE [] = trueE
andE [x] = x
andE xs = FunctionE (varE "and") xs

-- | > (if <expression> <expression> <expression>)
ifE :: Expression -> Expression -> Expression -> Expression
ifE p a b = FunctionE (varE "if") [p, a, b]

-- | > (< <exprsesion> <expression>)
ltE :: Expression -> Expression -> Expression
ltE a b = FunctionE (varE "<") [a, b]

-- | > (> <exprsesion> <expression>)
gtE :: Expression -> Expression -> Expression
gtE a b = FunctionE (varE ">") [a, b]

-- | > (+ <exprsesion> <expression>)
addE :: Expression -> Expression -> Expression
addE a b = FunctionE (varE "+") [a, b]

-- | > (- <exprsesion> <expression>)
subE :: Expression -> Expression -> Expression
subE a b = FunctionE (varE "-") [a, b]

-- | > (* <exprsesion> <expression>)
mulE :: Expression -> Expression -> Expression
mulE a b = FunctionE (varE "*") [a, b]

-- | > (mk-bv w b)
mkbvE :: Integer -> Integer -> Expression
mkbvE w b = FunctionE (varE "mk-bv") [integerE w, integerE b]

-- | > (bv-add a b)
bvaddE :: Expression -> Expression -> Expression
bvaddE a b = FunctionE (varE "bv-add") [a, b]

-- | > (bv-or a b)
bvorE :: Expression -> Expression -> Expression
bvorE a b = FunctionE (varE "bv-or") [a, b]

-- | > (bv-and a b)
bvandE :: Expression -> Expression -> Expression
bvandE a b = FunctionE (varE "bv-and") [a, b]

-- | > (bv-shift-left0 a i)
bvshiftLeft0E :: Expression -> Integer -> Expression
bvshiftLeft0E a b = FunctionE (varE "bv-shift-left0") [a, integerE b]

-- | > (bv-shift-right0 a i)
bvshiftRight0E :: Expression -> Integer -> Expression
bvshiftRight0E a b = FunctionE (varE "bv-shift-right0") [a, integerE b]

-- | > (bv-shl a b)
bvshlE :: Expression -> Expression -> Expression
bvshlE a b = FunctionE (varE "bv-shl") [a, b]

-- | > (bv-zero-extend a w)
bvzeroExtendE :: Expression -> Integer -> Expression
bvzeroExtendE a b = FunctionE (varE "bv-zero-extend") [a, integerE b]

-- | > (bv-extract a i j)
bvextractE :: Expression -> Integer -> Integer -> Expression
bvextractE a i j = FunctionE (varE "bv-extract") [a, integerE i, integerE j]

-- | Convert an abstract syntactic construct to concrete yices syntax.
class Concrete a where
    concrete :: YicesVersion -> a -> [String]

indent :: [String] -> [String]
indent = map ((:) ' ')

instance Concrete Command where
    concrete v (DefineType s Nothing)
        = ["(define-type " ++ s ++ ")"]
    concrete v (DefineType s (Just td))
        = ["(define-type " ++ s]
          ++ indent (concrete v td)
          ++ [")"]
    concrete v (Define s t Nothing)
        = ["(define " ++ s ++ " ::"]
          ++ indent (concrete v t)
          ++ [")"]
    concrete v (Define s t (Just e))
        = ["(define " ++ s ++ " ::"]
          ++ indent (concrete v t)
          ++ indent (concrete v e)
          ++ [")"]
    concrete v (Assert e)
        = ["(assert"]
          ++ indent (concrete v e)
          ++ [")"]
    concrete v Check = ["(check)"]
    concrete v Push = ["(push)"]
    concrete v Pop = ["(pop)"]

instance Concrete [Command] where
    concrete v cmds = concat $ map (concrete v) cmds

instance Concrete Typedef where
    concrete v (ScalarTD ss) = ["(scalar " ++ concat (map ((:) ' ') ss) ++ ")"]
    concrete v (NormalTD t) = concrete v t

instance Concrete Type where
    concrete v (VarT s) = [s]
    concrete v (TupleT ts)
      = ["(tuple"]
        ++ indent (concat $ map (concrete v) ts)
        ++ [")"]
    concrete v (ArrowT ts)
      = ["(->"]
        ++ indent (concat $ map (concrete v) ts)
        ++ [")"]
    concrete v (BitVectorT i) = ["(bitvector " ++ show i ++ ")"]
    concrete v IntegerT = ["int"]
    concrete v BoolT = ["bool"]
    concrete v RealT = ["real"]

instance Concrete Expression where
    concrete v (ImmediateE iv) = concrete v iv
    concrete v (ForallE decls e)
        = ["(forall"]
          ++ indent (["("] ++ indent (concat $ map (concrete v) decls) ++ [")"])
          ++ indent (concrete v e)
          ++ [")"]
    concrete v (ExistsE decls e)
        = ["(exists"]
          ++ indent (["("] ++ indent (concat $ map (concrete v) decls) ++ [")"])
          ++ indent (concrete v e)
          ++ [")"]
    concrete v (LetE bindings e)
        = ["(let"]
          ++ indent (["("] ++ indent (concat $ map (concrete v) bindings) ++ [")"])
          ++ indent (concrete v e)
          ++ [")"]
    concrete v (UpdateE f es e)
        = ["(update"]
          ++ indent (concrete v f)
          ++ indent (["("] ++ indent (concat $ map (concrete v) es) ++ [")"])
          ++ indent (concrete v e)
          ++ [")"]
    concrete v (TupleUpdateE t i x)
        = [(if v == Yices1 then "(update" else "(tuple-update")]
          ++ indent (concrete v t)
          ++ indent [show i]
          ++ indent (concrete v x)
          ++ [")"]
    concrete v (FunctionE f args)
        = ["("]
          ++ indent (concrete v f)
          ++ indent (concat $ map (concrete v) args)
          ++ [")"]

instance Concrete VarDecl where
    concrete v (n, t) = [n ++ " ::"] ++ indent (concrete v t)

instance Concrete Binding where
    concrete v (n, e) = ["(" ++ n] ++ indent (concrete v e) ++ [")"]

instance Concrete ImmediateValue where
    concrete v TrueV = ["true"]
    concrete v FalseV = ["false"]
    concrete v (VarV s) = [s]
    concrete v (RationalV r)
        = [show (numerator r) ++
            if denominator r == 1
                then ""
                else "/" ++ show (denominator r)]

-- | Render abstract yices syntax to a concrete syntax string.
pretty :: Concrete a => YicesVersion -> a -> String
pretty v x = unlines (concrete v x)

