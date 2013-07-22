
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TypeSynonymInstances #-}

module Smten.Plugin.Output.Ppr (
    Smten.Plugin.Output.Ppr.render
    ) where

import Smten.Plugin.Output.Syntax
import Text.PrettyPrint.HughesPJ

class Ppr a where   
   ppr :: a -> Doc

render :: (Ppr a) => a -> String
render x = renderStyle (style { lineLength = maxBound }) (ppr x)

instance Ppr String where
    ppr = text

instance Ppr Module where
  ppr m = 
    vcat [text ("{-# LANGUAGE " ++ p ++ " #-}") | p <- mod_langs m] $+$
    text "module" <+> text (mod_name m) <+> text "where {" $+$
    vcat [text ("import qualified " ++ x) <+> semi | x <- mod_imports m] $+$
    vcat (map ppr $ mod_decs m) $+$
    text "}"

instance Ppr Dec where
    ppr (DataD x) = ppr x
    ppr (ValD x) = ppr x
    
instance Ppr Data where
    ppr (Data nm vs cs) =
       text "data" <+> ppr nm <+> sep (map ppr vs) <+> text "=" <+>
       vcat (punctuate (text "|") (map ppr cs)) <+> semi 

instance Ppr Val where
    ppr (Val nm ty e) =
      ppr nm <+> text "::" <+> ppr ty <+> semi $+$
      ppr nm <+> text "=" <+> ppr e <+> semi

instance Ppr RecField where
    ppr (RecField nm ty) = ppr nm <+> text "::" <+> ppr ty

instance Ppr Con where
    ppr (Con nm tys) = ppr nm <+> sep (map ppr tys)
    ppr (RecC nm fs) = ppr nm <+> braces (vcat $ punctuate comma (map ppr fs))

instance Ppr Type where
    ppr (ConAppT nm tys)
      = parens (sep (ppr nm : map ppr tys))
    ppr (ForallT vs ctx ty) =
      let pprctx = if null ctx
                      then empty
                      else parens (sep (punctuate comma (map ppr ctx))) <+> text "=>"
      in parens $ text "forall" <+> sep (map ppr vs) <+> text "." <+> pprctx <+> ppr ty

    ppr (VarT n) = text n
    ppr (AppT a b) = parens $ ppr a <+> ppr b

instance Ppr Exp where
    ppr (VarE nm) = ppr nm
    ppr (LitE l) = ppr l
    ppr (AppE a b) = parens (ppr a <+> ppr b)
    ppr (LetE xs b) = parens (text "let" <+> braces (vcat $ map ppr xs) <+> text "in" <+> ppr b)
    ppr (LamE n e) = parens (text "\\" <+> ppr n <+> text "->" <+> ppr e)
    ppr (CaseE x ms)
      = parens (text "case" <+> ppr x <+> text "of" <+> braces (ppr ms))

instance Ppr [Alt] where
    ppr = vcat . map ppr

instance Ppr Alt where
    ppr (Alt p e) = ppr p <+> text "->" <+> ppr e <+> semi

instance Ppr Pat where
    ppr (LitP l) = ppr l
    ppr (ConP nm xs) = parens (ppr nm <+> sep (map ppr xs))
    ppr (VarP nm) = ppr nm
    ppr (AsP nm p) = ppr nm <> text "@" <> ppr p

instance Ppr Literal where
    ppr (StringL str) = text (show str) <> text "#"
    ppr (CharL c) = text (show c) <> text "#"
    ppr (IntL i) = text (show i) <> text "#"
    ppr (WordL i) = text (show i) <> text "##"
    ppr (IntegerL i) = integer i

