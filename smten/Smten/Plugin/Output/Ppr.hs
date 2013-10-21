
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TypeSynonymInstances #-}

module Smten.Plugin.Output.Ppr (
    Smten.Plugin.Output.Ppr.renderToFile
    ) where

import Data.Text.Lazy (pack)
import System.IO

import Smten.Plugin.Output.Syntax
import Text.PrettyPrint.Leijen.Text

class Ppr a where   
   ppr :: a -> Doc

renderToFile :: (Ppr a) => FilePath -> a -> IO ()
renderToFile fp x = withFile fp WriteMode $ \h -> do
   displayIO h (renderCompact (ppr x))

instance Ppr String where
    ppr = text . pack

instance Ppr Module where
  ppr m = vsep [
    vsep (map ppr (mod_pragmas m)),
    ppr "module" <+> ppr (mod_name m) <+> ppr "(",
    nest 4 $ vsep [ppr x <> comma | x <- mod_exports m],
    nest 2 $ ppr ") where {",
    vsep [ppr ("import qualified " ++ x) <+> semi | x <- mod_imports m],
    vsep (map ppr $ mod_decs m),
    ppr "}"]

instance Ppr Pragma where
  ppr (LanguagePragma p) = ppr ("{-# LANGUAGE " ++ p ++ " #-}")
  ppr HaddockHide = ppr "{-# OPTIONS_HADDOCK hide #-}"
  ppr (GhcOption x) = ppr $ "{-# OPTIONS_GHC " ++ x ++ " #-}"

pprctx :: [Class] -> Doc 
pprctx ctx = if null ctx
                then empty
                else tupled (map ppr ctx) <+> ppr "=>"

instance Ppr Export where
  ppr (VarExport x) = ppr x
  ppr (TyConExport x) = ppr x <> parens (ppr "..")

instance Ppr Dec where
    ppr (DataD x) = ppr x
    ppr (ValD x) = ppr x
    ppr (InstD ctx ty ms)
      = vsep [
          ppr "instance" <+> pprctx ctx <+> ppr ty <+> ppr "where {",
          nest 2 (ppr ms),
          ppr "}" <+> semi]
    ppr (NewTypeD nm vs c) =
       ppr "newtype" <+> ppr nm <+> hsep (map ppr vs) <+> ppr "=" <+> ppr c <+> semi
        
    
instance Ppr Data where
    ppr (Data nm vs cs) =
       ppr "data" <+> ppr nm <+> hsep (map ppr vs) <+> ppr "=" <+>
       sep (punctuate (ppr "|") (map ppr cs)) <+> semi 

instance Ppr Val where
    ppr (Val nm (Just ty) e) = vsep [
      ppr nm <+> ppr "::" <+> ppr ty <+> semi,
      ppr nm <+> ppr "=" <+> ppr e <+> semi]
    ppr (Val nm Nothing e) =
      ppr nm <+> ppr "=" <+> ppr e <+> semi

instance Ppr Method where
    ppr (Method nm e) = ppr nm <+> ppr "=" <+> ppr e <+> semi

instance Ppr [Method] where
    ppr ms = vsep (map ppr ms)
    
instance Ppr RecField where
    ppr (RecField nm ty) = ppr nm <+> ppr "::" <+> ppr ty

instance Ppr Con where
    ppr (Con nm tys) = ppr nm <+> hsep (map ppr tys)
    ppr (RecC nm fs) = ppr nm <+> braces (vsep $ punctuate comma (map ppr fs))

instance Ppr Type where
    ppr (ConAppT nm tys)
      = parens (hsep (ppr nm : map ppr tys))
    ppr (ForallT vs ctx ty)
      = parens $ ppr "forall" <+> hsep (map ppr vs) <+> ppr "." <+> pprctx ctx <+> ppr ty

    ppr (VarT n) = ppr n
    ppr (AppT a b) = parens $ ppr a <+> ppr b
    ppr (NumT x) = integer x

instance Ppr Exp where
    ppr (VarE nm) = ppr nm
    ppr (LitE l) = ppr l
    ppr (AppE a b) = parens (ppr a <+> ppr b)
    ppr (LetE xs b) = parens (vsep [
                         ppr "let" <+> ppr "{",
                         nest 2 (vsep $ map ppr xs),
                         ppr "} in" <+> ppr b])
    ppr (LamE n e) = parens (hsep [ppr "\\" <+> ppr n <+> ppr "->",
                                  nest 2 $ ppr e])
    ppr (CaseE x ms) = parens (vsep [
                         ppr "case" <+> ppr x <+> ppr "of {",
                         nest 2 (ppr ms),
                         ppr "}"])
    ppr (ListE xs) = list (map ppr xs)
    ppr (RecE x ms) = parens (vsep [
                          ppr x <+> ppr "{",
                          nest 2 (vsep $ punctuate comma (map ppr ms)),
                          ppr "}"])
    ppr (SigE x t) = parens (ppr x <+> ppr "::" <+> ppr t)
    ppr (SccE nm x) = parens (ppr ("{-# SCC \"" ++ nm ++ "\" #-}") <+> ppr x)

instance Ppr Field where
    ppr (Field n v) = ppr n <+> ppr "=" <+> ppr v

instance Ppr [Alt] where
    ppr = vsep . map ppr

instance Ppr Alt where
    ppr (Alt p e) = hsep [ppr p, ppr "->", ppr e, semi]

instance Ppr Pat where
    ppr (LitP l) = ppr l
    ppr (ConP nm xs) = parens (ppr nm <+> hsep (map ppr xs))
    ppr (RecP nm) = ppr nm <+> braces empty
    ppr (VarP nm) = ppr nm
    ppr (AsP nm p) = ppr nm <> ppr "@" <> ppr p

instance Ppr Literal where
    ppr (StringL str) = ppr (show str) <> ppr "#"
    ppr (CharL c) = ppr (show c) <> ppr "#"
    ppr (IntL i) = ppr (show i) <> ppr "#"
    ppr (WordL i) = ppr (show i) <> ppr "##"
    ppr (IntegerL i) = integer i

