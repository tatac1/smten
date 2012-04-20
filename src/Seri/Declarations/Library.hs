
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TemplateHaskell #-}

module Seri.Declarations.Library (
    SeriDec(..),
    declval', declcon', decltycon', decltype', declinst', declclass', declvartinst',
    ) where

import Language.Haskell.TH

import Seri.THUtils
import qualified Seri.IR as SIR
import qualified Seri.Typed as S
import Seri.Declarations.Names
import Seri.Declarations.Utils
import Seri.Declarations.SeriDec

-- declval' name ty exp
-- Make a seri value declaration
--   name - name of the seri value being defined.
--   ty - the polymorphic haskell type of the expression.
--   exp - the value
--
-- For (contrived) example, given:
--  name: foo
--  ty: (Eq a) => a -> Integer
--  exp: lamE "x" (\x -> appE (varE "incr") (integerE 41))
--  iscon: False
--
-- The following haskell declarations are generated (approximately):
--  _seriP_foo :: (Eq a, SeriType a) => Typed Exp (a -> Integer)
--  _seriP_foo = lamE "x" (\x -> appE (varE "incr") (integerE 41))
--
--  _seriI_foo :: Typed Exp (a -> Integer) -> InstId
--  _seriI_foo _ = noinst
--
--  data SeriDec_foo = SeriDec_foo
--
--  instance SeriDec SeriDec_foo where
--      dec _ = ValD "foo"
--                  (ForallT ["a"] [Pred "Eq" [VarT_a]] (VarT_a -> Integer))
--                  (typed (_seri_foo :: Typed Exp (VarT_a -> Integer)))
declval' :: Name -> Type -> Exp -> [Dec]
declval' n t e =
  let dt = valuetype t
      sig_P = SigD (valuename n) dt
      impl_P = FunD (valuename n) [Clause [] (NormalB e) []]

      sig_I = SigD (instidname n) (instidtype t)
      impl_I = FunD (instidname n) [Clause [WildP] (NormalB $ ConE 'SIR.NoInst) []]

      exp = apply 'S.typed [SigE (VarE (valuename n)) (concrete dt)]
      body = applyC 'SIR.ValD [string n, seritypeexp t, exp]
      ddec = seridec (prefixed "D_" n) body

  in [sig_P, impl_P, sig_I, impl_I] ++ ddec

-- declcon' name ty
-- Make a seri data constructor declaration
--   name - name of the seri data constructor being defined.
--   ty - the polymorphic haskell type of the expression.
--
-- For (contrived) example, given:
--  name: Foo
--  ty: a -> Bar
--
-- The following haskell declarations are generated (approximately):
--  _seri_Foo :: (SeriType a) => Typed Exp (a -> Bar)
--  _seri_Foo = conE' "Foo"
declcon' :: Name -> Type -> [Dec]
declcon' n t =
  let dt = valuetype t
      sig_P = SigD (valuename n) dt
      impl_P = FunD (valuename n) [Clause [] (NormalB (apply 'S.conE' [string n])) []]
  in [sig_P, impl_P]


-- decltycon'
--
-- Given the name of a type constructor and its kind, make a SeriType instance
-- for it.
--
-- Use 0 for kind *
--     1 for kind * -> *
--     2 for kind * -> * -> *
--     etc...
decltycon' :: Integer -> Name -> [Dec]
decltycon' k nm = 
  let classname = "SeriType" ++ if k == 0 then "" else show k
      methname = "seritype" ++ if k == 0 then "" else show k

      stimpl = FunD (mkName methname) [Clause [WildP] (NormalB (AppE (ConE 'SIR.ConT) (string nm))) []]
      stinst = InstanceD [] (AppT (ConT (mkName classname)) (ConT nm)) [stimpl]
  in [stinst]

-- decltype' 
-- Given a type declaration, make a seri type declaration for it, assuming the
-- type is already defined in haskell.
--
-- For example, given 
--    data Foo a = Bar Integer
--               | Sludge a
--
-- The following haskell declarations are generated:
--    instance SeriType1 Foo where
--       seritype1 _ = ConT "Foo"
--
--    data SeriDecD_Foo = SeriDecD_Foo
--
--    instance SeriDec SeriDecD_Foo where
--        dec _ = DataD "Foo" ["a"] [Con "Bar" [ConT "Integer"],
--                                   Con "Sludge" [ConT "VarT_a"]]
--
--    _seri_Bar :: Typed Exp (Integer -> Foo)
--    _seri_Bar = conE "Bar"
--
--    _seri_Sludge :: (SeriType a) => Typed Exp (a -> Foo)
--    _seri_Sludge = conE "Sludge"
--
-- Record type constructors are also supported, in which case the selector
-- functions will also be declared like normal seri values.
--
decltype' :: Dec -> [Dec]
decltype' (DataD [] dt vars cs _) =
 let vnames = map tyvarname vars
     dtapp = appts $ (ConT dt):(map VarT vnames)

     -- Assuming the data type is polymorphic in type variables a, b, ...
     -- Given type t, return type (forall a b ... . t)
     --
     contextify :: Type -> Type
     contextify t = ForallT vars [] t

     -- contype: given the list of field types [a, b, ...] for a constructor
     -- form the constructor type: a -> b -> ... -> Foo
     contype :: [Type] -> Type
     contype ts = contextify $ arrowts (ts ++ [dtapp])

     -- produce the declarations needed for a given constructor.
     -- Note: RecC is not canonical, so we assume we needn't deal with it
     -- here.
     mkcon :: Con -> [Dec]
     mkcon (NormalC nc sts) = declcon' nc (contype $ map snd sts)

     -- Given a constructor, return an expression corresponding to the Seri
     -- Con representing that constructor.
     mkconinfo :: Con -> Exp
     mkconinfo (NormalC n sts) = applyC 'SIR.Con [string n, ListE (map (\(_, t) -> seritypeexp t) sts)]

     body = applyC 'SIR.DataD [string dt, ListE (map string vnames), ListE (map mkconinfo cs)]
     ddec = seridec (prefixed "D_" dt) body

     constrs = concat $ map mkcon cs

     stinst = decltycon' (toInteger $ length vars) dt
 in stinst ++ ddec ++ constrs


-- declclass
-- Make a seri class declaration.
--
-- For example, given the class:
--   class Foo a where
--      foo :: a -> Integer
--
-- We generate:
--   class (SeriType a) => SeriClass_Foo a where
--     _seriP_foo :: Typed Exp (a -> Integer)
--     _seriI_foo :: Typed Exp (a -> Integer) -> InstId
--   
--   _seriT_foo :: a -> Typed Exp (a -> Integer)
--   _seriT_foo = undefined
-- 
--   data SeriDecC_Foo = SeriDecC_Foo
--   instance SeriDec SeriDecC_Foo where
--     dec = ClassD "Foo" ["a"] [Sig "foo" (VarT_a -> Integer)]
declclass' :: Dec -> [Dec]
declclass' (ClassD [] nm vars [] sigs) =
  let mksig :: Dec -> [Dec]
      mksig (SigD n (ForallT _ _ t)) =
        let sig_P = SigD (valuename n) (valuetype t)
            sig_I = SigD (instidname n) (instidtype t)
        in [sig_P, sig_I]

      ctx = map stpred vars
      class_D = ClassD ctx (classname nm) vars [] (concat $ map mksig sigs)

      mkt :: Dec -> [Dec]
      mkt (SigD n (ForallT _ _ t)) = 
        let vararg :: TyVarBndr -> Type
            vararg v = appts $ [VarT (tyvarname v)] ++ replicate (fromInteger $ tvarkind v) (ConT $ mkName "()")

            ty = case flattenforall t of
                    ForallT vns ctx t' -> ForallT vns ctx (arrowts $ map vararg vars ++ [texpify t'])
                    t' -> arrowts $ map vararg vars ++ [texpify t']
            sig_T = SigD (methodtypename n) (ForallT vars [] ty)
            impl_T = FunD (methodtypename n) [Clause [WildP] (NormalB (VarE 'undefined)) []]
        in [sig_T, impl_T]

      type_ds = concat $ map mkt sigs

      mkdsig :: Dec -> Exp
      mkdsig (SigD n (ForallT _ _ t)) = applyC 'SIR.Sig [string n, seritypeexp t]

      tyvars = ListE $ map (string . tyvarname) vars
      dsigs = ListE $ map mkdsig sigs
      body = applyC 'SIR.ClassD [string nm, tyvars, dsigs]
      ddec = seridec (prefixed "C_" nm) body
      
  in [class_D] ++ type_ds ++ ddec


-- declinst
-- Make a seri instance declaration.
--
-- For example, given the instance
--   instance Foo Bool where
--      foo _ = 2
--
-- Generates:
--   instance SeriClass_Foo Bool where
--     _seriP_foo = ...
--     _seriI_foo _ = Inst "Foo" [Bool]

--   data SeriDecI_Foo$Bool = SeriDecI_Foo$Bool
--   instance SeriDec SeriDecI_Foo$Bool where
--     dec = InstD "Foo" [Bool] [
--             method "foo" (_seriT_foo (undefined :: Bool)) (...)
--             ]
--  
declinst'' :: Bool -> Dec -> [Dec]
declinst'' addseridec i@(InstanceD [] tf@(AppT (ConT cn) t) impls) =
  let -- TODO: don't assume single param type class
      iname = string cn
      itys = ListE [seritypeexp t]

      mkimpl :: Dec -> [Dec]
      mkimpl (ValD (VarP n) (NormalB b) []) =
        let p = ValD (VarP (valuename n)) (NormalB b) []
            i = FunD (instidname n) [Clause [WildP] (NormalB (applyC 'SIR.Inst [iname, itys])) []]
        in [p, i]

      idize :: Type -> String
      idize (AppT a b) = idize a ++ "$" ++ idize b
      idize (ConT nm) = nameBase nm

      impls' = concat $ map mkimpl impls
      inst_D = InstanceD [] (AppT (ConT (classname cn)) t) impls'

      mkmeth (ValD (VarP n) (NormalB b) _) = 
        apply 'S.method [string n, AppE (VarE (methodtypename n)) (SigE (VarE 'undefined) t), b]

      methods = ListE $ map mkmeth impls
      body = applyC 'SIR.InstD [iname, itys, methods]
      ddec = seridec (mkName $ "I_" ++ (idize tf)) body
   in [inst_D] ++ if addseridec then ddec else []

declinst' :: Dec -> [Dec]
declinst' = declinst'' True

declvartinst' :: Dec -> SIR.Name -> [Dec]
declvartinst' (ClassD [] n _ [] sigs) v =
  let mkimpl :: Dec -> Dec
      mkimpl (SigD n t) = ValD (VarP n) (NormalB (VarE 'undefined)) []
    
      inst = InstanceD [] (AppT (ConT n) (ConT $ mkName ("VarT_" ++ v))) (map mkimpl sigs)
  in declinst'' False inst 
