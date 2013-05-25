
{-# LANGUAGE PatternGuards #-}

module Smten.HaskellF.Compile.Module (
    hsModule
    ) where

import Data.Functor((<$>))
import Data.List(nub)
import Data.Maybe(catMaybes)
import qualified Language.Haskell.TH.PprLib as H
import qualified Language.Haskell.TH.Ppr as H
import qualified Language.Haskell.TH.Syntax as H

import Smten.Failable
import Smten.Name
import Smten.Dec
import Smten.Module
import Smten.HaskellF.Compile.HF
import Smten.HaskellF.Compile.Name
import Smten.HaskellF.Compile.Dec

-- Produce common header for all modules.
-- Includes language pragmas and HaskellF imports.
hsHeader :: Name -> H.Doc
hsHeader modname = 
  H.text "{-# LANGUAGE ExplicitForAll #-}" H.$+$
  H.text "{-# LANGUAGE MultiParamTypeClasses #-}" H.$+$
  H.text "{-# LANGUAGE FlexibleInstances #-}" H.$+$
  H.text "{-# LANGUAGE FlexibleContexts #-}" H.$+$
  H.text "{-# LANGUAGE UndecidableInstances #-}" H.$+$
  H.text "{-# LANGUAGE ScopedTypeVariables #-}" H.$+$
  H.text "{-# LANGUAGE InstanceSigs #-}" H.$+$
  H.text "{-# LANGUAGE KindSignatures #-}" H.$+$
  H.text ("module " ++ unname modname
            ++ "(module " ++ unname modname ++ ") where") H.$+$
  H.text "import qualified Prelude" H.$+$
  H.text "import qualified Smten.Name" H.$+$
  H.text "import qualified Smten.Type" H.$+$
  H.text "import qualified Smten.ExpH" H.$+$
  H.text "import qualified Smten.HaskellF.HaskellF" H.$+$
  H.text "import qualified Smten.HaskellF.Numeric"

hsImport :: Import -> H.Doc
hsImport (Import fr _ _ _) = H.text $ "import qualified " ++ unname (hfpre fr)

hsImports :: [Import] -> H.Doc
hsImports = H.vcat . map hsImport


primImports :: [Dec] -> H.Doc
primImports ds =
 let pi :: Dec -> Maybe String
     pi (PrimD _ s _) = Just (unname (qualification (name s)))
     pi _ = Nothing

     impstrs = nub $ catMaybes (map pi ds)

     todoc :: String -> H.Doc
     todoc s = H.text "import qualified" H.<+> H.text s
 in H.vcat (map todoc impstrs)


hsDecls :: Env -> [Dec] -> Failable [H.Dec]
hsDecls env ds = runHF env (concat <$> mapM hsDec ds)

hsModule :: Env -> Module -> Failable H.Doc
hsModule env mod = do
  let header = hsHeader (hfpre $ mod_name mod)
      mn = mod_name mod
      main = case attemptM $ lookupValD env (qualified mn (name "main")) of
               Just _ -> H.text "main__ = Smten.HaskellF.HaskellF.mainHF main"
               Nothing -> H.empty
      imports = hsImports (mod_imports mod)
      primports = primImports (mod_decs mod)
  hdecls <- hsDecls env (mod_decs mod)
  return (header H.$+$ primports H.$+$ imports H.$+$ H.ppr hdecls H.$+$ main)

