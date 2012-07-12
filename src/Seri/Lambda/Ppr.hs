
{-# LANGUAGE FlexibleInstances #-}

-- | Pretty printer for core seri language.
module Seri.Lambda.Ppr (
    Ppr(..), pretty,
    module Text.PrettyPrint.HughesPJ
    ) where

import Debug.Trace

import Data.List(group, nub)

import Text.PrettyPrint.HughesPJ

import Seri.Lambda.IR
import Seri.Lambda.Sugar

class Ppr a where
    ppr :: a -> Doc

tabwidth :: Int
tabwidth = 2

isAtomT :: Type -> Bool
isAtomT (AppT (ConT "[]") _) = True
isAtomT (AppT (AppT (ConT "(,)") a) b) = True
isAtomT (AppT (AppT (AppT (ConT "(,,)") a) b) c) = True
isAtomT (ConT {}) = True
isAtomT (VarT {}) = True
isAtomT (AppT {}) = False
isAtomT (UnknownT {}) = True

isArrowsT :: Type -> Bool
isArrowsT (AppT (AppT (ConT "->") _) _) = True
isArrowsT _ = False

instance Ppr Type where
    -- Special case for list
    ppr (AppT (ConT "[]") t) = text "[" <> ppr t <> text "]"
    
    -- Special case for tuples
    ppr (AppT (AppT (ConT "(,)") a) b)
        = parens . sep $ punctuate comma (map ppr [a, b])
    ppr (AppT (AppT (AppT (ConT "(,,)") a) b) c)
        = parens . sep $ punctuate comma (map ppr [a, b, c])
    ppr (AppT (AppT (AppT (AppT (ConT "(,,,)") a) b) c) d)
        = parens . sep $ punctuate comma (map ppr [a, b, c, d])

    -- Special case for ->
    ppr (AppT (AppT (ConT "->") a) b) | isArrowsT a
        = parens (ppr a) <+> text "->" <+> ppr b
    ppr (AppT (AppT (ConT "->") a) b)
        = ppr a <+> text "->" <+> ppr b
    ppr (ConT "->") = text "(->)"

    -- Normal cases
    ppr (ConT n) = text n
    ppr (VarT n) = text n
    ppr (AppT a b) | isAtomT b = ppr a <+> ppr b
    ppr (AppT a b) = ppr a <+> (parens $ ppr b)
    ppr UnknownT = text "?"


isAtomE :: Exp -> Bool
isAtomE (LitE {}) = True
isAtomE (CaseE {}) = False
isAtomE (AppE {}) = False
isAtomE (LamE {}) = False
isAtomE (ConE {}) = True
isAtomE (VarE {}) = True

isOp :: String -> Bool
isOp (c:_) = c `elem` ":!#$%&*+./<=>?@\\^|-~"

pprname :: String -> Doc
pprname n | isOp n = parens (text n)
pprname n = text n

pprsig :: Doc -> Sig -> Doc
pprsig s (Sig n UnknownT) = pprname n
pprsig s (Sig n t) = parens (s <> pprname n <+> text "::" <+> (ppr t))

sep2 :: Doc -> Doc -> Doc
sep2 a b = a $$ nest tabwidth b

cando :: Exp -> Bool
cando (AppE (AppE (VarE (Sig ">>" _)) _) _) = True
cando (AppE (AppE (VarE (Sig ">>=" _)) _) (LamE _ _)) = True
cando _ = False

sugardo :: Exp -> [Stmt]
sugardo (AppE (AppE (VarE (Sig ">>" _)) m) r)
    = NoBindS m : sugardo r
sugardo (AppE (AppE (VarE (Sig ">>=" _)) m) (LamE s r))
    = BindS s m : sugardo r
sugardo e = [NoBindS e]

isStringLiteral :: Exp -> Bool
isStringLiteral (ConE (Sig "[]" (AppT (ConT "[]") (ConT "Char")))) = True
isStringLiteral (AppE (AppE (ConE (Sig ":" _)) (LitE (CharL _))) e) = isStringLiteral e
isStringLiteral _ = False

stringLiteral :: Exp -> String
stringLiteral (ConE (Sig "[]" (AppT (ConT "[]") (ConT "Char")))) = ""
stringLiteral (AppE (AppE (ConE (Sig ":" _)) (LitE (CharL c))) e)
  = c : stringLiteral e
stringLiteral e = error $ "not a string literal: " ++ show e

instance Ppr Lit where
    ppr (IntegerL i) = integer i
    ppr (CharL c) = text (show c)

instance Ppr Exp where
    -- Special case for if expressions
    ppr (CaseE e [Match (ConP (ConT "Bool") "True" []) a,
                  Match (ConP (ConT "Bool") "False" []) b])
        = text "if" <+> ppr e $$ nest tabwidth (
                text "then" <+> ppr a $$
                text "else" <+> ppr b)

    -- Special case for do statements
    ppr e | cando e
        = text "do" <+> text "{"
                $+$ nest tabwidth (vcat (map ppr (sugardo e))) $+$ text "}"

    -- Special case for tuples
    ppr (AppE (AppE (ConE (Sig "(,)" _)) a) b) =
        parens . sep $ punctuate comma (map ppr [a, b])
    ppr (AppE (AppE (AppE (ConE (Sig "(,,)" _)) a) b) c) =
        parens . sep $ punctuate comma (map ppr [a, b, c])
    ppr (AppE (AppE (AppE (AppE (ConE (Sig "(,,,)" _)) a) b) c) d) =
        parens . sep $ punctuate comma (map ppr [a, b, c, d])

    -- Special case for string literals
    ppr e | isStringLiteral e = text (show (stringLiteral e))

    -- Normal cases
    ppr (LitE l) = ppr l
    ppr (CaseE e ms) = text "case" <+> ppr e <+> text "of" <+> text "{"
                        $+$ nest tabwidth (vcat (map ppr ms)) $+$ text "}"
    ppr (AppE a b) | isAtomE b = ppr a <+> ppr b
    ppr (AppE a b) = ppr a <+> (parens $ ppr b)
    ppr (LamE s b) = parens $ (text "\\" <> pprsig empty s <+> text "->") `sep2` ppr b
    ppr (ConE s) = pprsig empty s
    ppr (VarE s) = pprsig empty s

instance Ppr Stmt where
    ppr (NoBindS e) = ppr e <> semi
    ppr (BindS s e) = pprsig empty s <+> text "<-" <+> ppr e <> semi

instance Ppr Match where
    ppr (Match p e) = (ppr p <+> text "->") `sep2` ppr e <> semi

isAtomP :: Pat -> Bool
isAtomP (ConP _ _ []) = True
isAtomP (ConP {}) = False
isAtomP (VarP {}) = True
isAtomP (IntegerP {}) = True
isAtomP (WildP {}) = True

isTuple :: String -> Bool
isTuple n = ["(", ",", ")"] == nub (group n)

instance Ppr Pat where
    -- special case for tuples
    ppr (ConP _ n ps) | isTuple n = 
        parens . sep $ punctuate comma (map ppr ps)
        
    -- normal cases
    ppr (ConP t n ps) =
        let subp p | isAtomP p = ppr p
            subp p = parens (ppr p)
        in pprsig empty (Sig n t) <+> hsep (map subp ps)
    ppr (VarP s) = pprsig empty s
    ppr (IntegerP i) = integer i
    ppr (WildP t) = pprsig empty (Sig "_" t)

conlist :: [Con] -> Doc
conlist [] = empty
conlist (x:xs) = text " " <+> ppr x
                    $+$ vcat (map (\c -> text "|" <+> ppr c) xs)

instance Ppr Dec where
    ppr (ValD s@(TopSig n _ _) e)
        = ppr s <> semi $$ pprname n <+> text "=" <+> ppr e
    ppr (DataD n vs cs)
        = text "data" <+> text n <+> hsep (map text vs) <+> text "=" $$
            (nest tabwidth (conlist cs))
    ppr (ClassD n vs ss)
        = text "class" <+> text n <+> hsep (map text vs)
                <+> text "where" <+> text "{"
                $+$ nest tabwidth (vcat (punctuate semi (map ppr ss))) $+$ text "}"
    ppr (InstD ctx cls ms)
        = text "instance"
                <+> ppr ctx
                <+> ppr cls
                <+> text "where" <+> text "{"
                $+$ nest tabwidth (vcat (map ppr ms)) $+$ text "}"
    ppr (PrimD s) = ppr s

instance Ppr Sig where
    ppr (Sig n t) = pprname n <+> text "::" <+> ppr t <> semi

instance Ppr TopSig where
    ppr (TopSig n ctx t)
      = pprname n <+> text "::" <+> ppr ctx <+> ppr t

instance Ppr Context where
    ppr [] = empty
    ppr xs = parens (sep (map ppr xs)) <+> text "=>"
    
instance Ppr Con where
    ppr (Con n ts) = text n <+> hsep (map ppr ts)

instance Ppr Method where
    ppr (Method n e) = pprname n <+> text "=" <+> ppr e <> semi

instance Ppr [Dec] where
    ppr ds = vcat (punctuate semi (map (\d -> ppr d $+$ text "") ds))

instance Ppr Class where
    ppr (Class n ts) = ppr (foldl AppT (ConT n) ts)

instance Ppr Import where
    ppr (Import n) = text "import" <+> text n <> semi

instance Ppr Module where
    ppr (Module n imps decs)
        = text "module" <+> text n <+> text "where" <+> text "{"
            $+$ nest tabwidth (vcat (map ppr imps) $+$ ppr decs) $+$ text "}"

-- | Print an object very prettily.
pretty :: (Ppr a) => a -> String
pretty = render . ppr

