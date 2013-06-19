
module Smten.CodeGen.Data (
    dataCG, mkHaskellyD,
    ) where

import qualified Language.Haskell.TH.Syntax as H

import Data.Functor((<$>))

import Smten.Name
import Smten.Type
import Smten.Dec
import Smten.CodeGen.CG
import Smten.CodeGen.Type
import Smten.CodeGen.Name

dataCG :: Name -> [TyVar] -> [Con] -> CG [H.Dec]
dataCG n tyvars constrs = do
    dataD <- mkDataD n tyvars constrs
    casesD <- concat <$> mapM (mkCaseD n tyvars constrs) constrs
    shsD <- smtenHS n tyvars constrs
    itehelpers <- mkIteHelpersD n tyvars constrs
    return $ concat [dataD, casesD, itehelpers, shsD]

-- data Foo a b ... = FooA A1 A2 ...
--                  | FooB B1 B2 ...
--                  ...
--                  | FooK K1 K2 ...
--                  | Foo_Prim (Assignment -> Foo a b ...) (Foo a b ...)
--                  | Foo_Error ErrorString
--                  | Foo_Ite {
--                      __iteFooA :: P.Maybe (Bool, Foo a b ...),
--                      __iteFooB :: P.Maybe (Bool, Foo a b ...),
--                      ...,
--                      __iteFoo_Error :: P.Maybe (Bool, Foo a b ...)
--                    }
mkDataD :: Name -> [TyVar] -> [Con] -> CG [H.Dec]
mkDataD n tyvars constrs = do
  let tyvars' = [H.PlainTV (nameCG nm) | TyVar nm _ <- tyvars]

      mkcon :: Con -> CG H.Con
      mkcon (Con cn tys) = do
        let cn' = nameCG cn
        tys' <- mapM typeCG tys
        return (H.NormalC cn' [(H.NotStrict, ty') | ty' <- tys'])

      tyme = foldl H.AppT (H.ConT (qtynameCG n)) [H.VarT (nameCG nm) | TyVar nm _ <- tyvars]
      asn = foldl H.AppT H.ArrowT [H.ConT (H.mkName "Smten.Assignment"), tyme]
      prim = H.NormalC (primnmCG n) [(H.NotStrict, ty) | ty <- [asn, tyme]]

      tyerr = H.ConT (H.mkName $ "Smten.ErrorString")
      err = H.NormalC (errnmCG n) [(H.NotStrict, tyerr)]

      tybool = H.ConT (qtynameCG boolN)
      tyfield = H.AppT (H.ConT (H.mkName "Prelude.Maybe"))
                       (foldl H.AppT (H.TupleT 2) [tybool, tyme])

      iteerr = (iteerrnmCG n, H.NotStrict, tyfield)
      ites = [(iteflnmCG cn, H.NotStrict, tyfield) | Con cn _ <- constrs]
      ite = H.RecC (itenmCG n) (ites ++ [iteerr])

  constrs' <- mapM mkcon constrs
  return [H.DataD [] (tynameCG n) tyvars' (constrs' ++ [prim, err, ite]) []]

-- __caseFooX :: Foo a b ... -> (X1 -> X2 -> ... -> z__) -> z__ -> z__
-- __caseFooX x y n =
--    case x of
--      Foo1 {} -> n
--      Foo2 {} -> n
--      ...
--      FooX x1 x2 ... -> y x1 x2 ...
--      ...
--      _ -> sapp (\v -> __caseFooX v y n) x
mkCaseD :: Name -> [TyVar] -> [Con] -> Con -> CG [H.Dec]
mkCaseD n tyvars cs (Con cn tys) = do
  let dt = appsT (conT n) (map tyVarType tyvars)
      zt = varT (name "z__")
      yt = arrowsT (tys ++ [zt])
      ty = arrowsT [dt, yt, zt, zt]
  H.SigD _ ty' <- topSigCG (TopSig (name "DONT_CARE") [] ty)
  let sig = H.SigD (casenmCG cn) ty'

      [vv, vx, vy, vn] = map H.mkName ["v", "x", "y", "n"]
      vxs = [H.mkName ("x" ++ show i) | i <- [1..(length tys)]]

      mkcon :: Con -> H.Match
      mkcon (Con n _) 
        | n == cn = H.Match (H.ConP (qnameCG cn) (map H.VarP vxs))
                       (H.NormalB (foldl H.AppE (H.VarE vy) (map H.VarE vxs))) []
        | otherwise = H.Match (H.RecP (qnameCG n) []) (H.NormalB (H.VarE vn)) []

      defbody = H.NormalB $ foldl1 H.AppE [
        H.VarE $ H.mkName "Smten.sapp",
        H.LamE [H.VarP vv] (foldl1 H.AppE (map H.VarE [qcasenmCG cn, vv, vy, vn])),
        H.VarE vx]
      mkdef = H.Match H.WildP defbody []

      matches = map mkcon cs ++ [mkdef]
      cse = H.CaseE (H.VarE vx) matches
      clause = H.Clause (map H.VarP [vx, vy, vn]) (H.NormalB cse) []
      fun = H.FunD (casenmCG cn) [clause]
  return [sig, fun]

-- instance (Haskelly ha sa, Haskelly hb sb, ...) =>
--   Haskelly (Foo ha hb ...) (Smten.Lib.Foo sa sb ...) where
--     frhs ...
--     tohs ...
mkHaskellyD :: String -> Name -> [TyVar] -> [Con] -> CG [H.Dec]
mkHaskellyD hsmod nm tyvars cons = do
  let hvars = [H.VarT (H.mkName $ "h" ++ unname n) | TyVar n _ <- tyvars]
      svars = [H.VarT (H.mkName $ "s" ++ unname n) | TyVar n _ <- tyvars]
      ctx = [H.ClassP (H.mkName "Smten.Haskelly") [ht, st] | (ht, st) <- zip hvars svars]
      ht = foldl H.AppT (H.ConT (qhstynameCG hsmod nm)) hvars
      st = foldl H.AppT (H.ConT (qtynameCG nm)) svars
      ty = foldl1 H.AppT [H.ConT $ H.mkName "Smten.Haskelly", ht, st]
  frhs <- mkFrhsD hsmod cons
  tohs <- mkTohsD hsmod cons
  return [H.InstanceD ctx ty [frhs, tohs]]

--     frhs (FooA x1 x2 ...) = Smten.Lib.FooA (frhs x1) (frhs x2) ...
--     frhs (FooB x1 x2 ...) = Smten.Lib.FooB (frhs xs) (frhs x2) ...
--     ...
mkFrhsD :: String -> [Con] -> CG H.Dec
mkFrhsD hsmod cons = do
  let mkcon :: Con -> H.Clause
      mkcon (Con cn tys) = 
        let xs = [H.mkName $ "x" ++ show i | i <- [1..(length tys)]]
            pat = H.ConP (qhsnameCG hsmod cn) (map H.VarP xs)
            body = foldl H.AppE (H.ConE (qnameCG cn)) [H.AppE (H.VarE $ H.mkName "Smten.frhs") (H.VarE x) | x <- xs]
        in H.Clause [pat] (H.NormalB body) []
  return $ H.FunD (H.mkName "frhs") (map mkcon cons)

--     tohs (Smten.Lib.FooA x1 x2 ...) = FooA (tohs x1) (tohs x2) ...
--     tohs (Smten.Lib.FooB x1 x2 ...) = FooB (tohs xs) (tohs x2) ...
--     ...
mkTohsD :: String -> [Con] -> CG H.Dec
mkTohsD hsmod cons = do
  let mkcon :: Con -> H.Clause
      mkcon (Con cn tys) = 
        let xs = [H.mkName $ "x" ++ show i | i <- [1..(length tys)]]
            pat = H.ConP (qnameCG cn) (map H.VarP xs)
            body = foldl H.AppE (H.ConE (qhsnameCG hsmod cn)) [H.AppE (H.VarE $ H.mkName "Smten.tohs") (H.VarE x) | x <- xs]
        in H.Clause [pat] (H.NormalB body) []
  return $ H.FunD (H.mkName "tohs") (map mkcon cons)

-- Note: we currently don't support crazy kinded instances of SmtenHS. This
-- means we are limited to "linear" kinds of the form (* -> * -> ... -> *)
--
-- To handle that properly, we chop off as many type variables as needed to
-- get to a linear kind.
--   call the chopped off type variables c1, c2, ...
--
-- instance (SmtenN c1, SmtenN c2, ...) => SmtenHSN (Foo c1 c2 ...) where
--   realizeN = ...
--   primitiveN = ...
--   errorN = ...
--   ...
smtenHS :: Name -> [TyVar] -> [Con] -> CG [H.Dec]
smtenHS nm tyvs cs = do
   let (rkept, rdropped) = span (\(TyVar n k) -> knum k == 0) (reverse tyvs)
       n = length rkept
       dropped = reverse rdropped
       ctx = [H.ClassP (H.mkName $ "Smten.SmtenHS" ++ show (knum k)) [H.VarT (nameCG n)] | TyVar n k <- dropped]
       ty = H.AppT (H.VarT (H.mkName $ "Smten.SmtenHS" ++ show n))
                   (foldl H.AppT (H.ConT $ qtynameCG nm) [H.VarT (nameCG n) | TyVar n _ <- dropped])
   rel <- realizeD nm n cs
   prim <- primD nm n
   ite <- iteD nm n cs
   err <- errorD nm n
   sapp <- sappD nm n cs
   return [H.InstanceD ctx ty [rel, ite, prim, err, sapp]]

--   primN = Foo_Prim
primD :: Name -> Int -> CG H.Dec
primD nm n = do
  let body = H.ConE (qprimnmCG nm)
      clause = H.Clause [] (H.NormalB body) []
      fun = H.FunD (H.mkName $ "primitive" ++ show n) [clause]
  return fun

-- iteN p (FooA a1 a2 ...) (FooA b1 b2 ...) = FooA (ite p a1 b1) (ite p a2 b2) ...
-- iteN p (FooB a1 a2 ...) (FooB b1 b2 ...) = FooB (ite p a1 b1) (ite p a2 b2) ...
--  ...
-- iteN p (Foo_Error a1) (Foo_Error b1) = Foo_Error (ite p a1 b1)
-- iteN p a@(Foo_Ite {}) b@(Foo_ite {}) = Foo_Ite {
--           __iteFooA = flmerge p (__iteFooA a) (__iteFooA b)
--           __iteFooB = flmerge p (__iteFooB a) (__iteFooB b)
--           ...
--         }
-- iteN p a@(Foo_Prim r c) b -> Foo_Prim (iterealize p a b) (ite p c b)
-- iteN p a b@(Foo_Prim r c) -> Foo_Prim (iterealize p a b) (ite p a c)
-- iteN p a b -> ite p (__LiftIteFoo a) (__LiftIteFoo b)
iteD :: Name -> Int -> [Con] -> CG H.Dec
iteD n k cs = do
  let ite a b = foldl1 H.AppE [
                  H.VarE $ H.mkName "Smten.ite",
                  H.VarE $ H.mkName "p", a, b]

      mkcon :: Con -> H.Clause
      mkcon (Con cn cts) =
        let as = [H.mkName $ "a" ++ show i | i <- [1..length cts]]
            bs = [H.mkName $ "b" ++ show i | i <- [1..length cts]]
            pats = [H.VarP $ H.mkName "p",
                    H.ConP (qnameCG cn) (map H.VarP as),
                    H.ConP (qnameCG cn) (map H.VarP bs)]
            ites = [ite (H.VarE a) (H.VarE b) | (a, b) <- zip as bs]
            body = foldl H.AppE (H.ConE $ qnameCG cn) ites
        in H.Clause pats (H.NormalB body) []

      an = H.mkName "a"
      bn = H.mkName "b"
      ap = H.VarP an
      bp = H.VarP bn
      ae = H.VarE an
      be = H.VarE bn
      errpats = [H.VarP $ H.mkName "p",
                 H.ConP (qerrnmCG n) [ap],
                 H.ConP (qerrnmCG n) [bp]]
      errbody = H.AppE (H.ConE (qerrnmCG n)) (ite ae be)
      errcon = H.Clause errpats (H.NormalB errbody) []

      mkfe :: Con -> H.FieldExp
      mkfe (Con cn tys) = (iteflnmCG cn, foldl1 H.AppE [
                        H.VarE $ H.mkName "Smten.flmerge",
                        H.VarE $ H.mkName "p",
                        H.AppE (H.VarE $ qiteflnmCG cn) ae,
                        H.AppE (H.VarE $ qiteflnmCG cn) be])

      efe = (iteerrnmCG n, foldl1 H.AppE [
                        H.VarE $ H.mkName "Smten.flmerge",
                        H.VarE $ H.mkName "p",
                        H.AppE (H.VarE $ qiteerrnmCG n) ae,
                        H.AppE (H.VarE $ qiteerrnmCG n) be])
      itepats = [H.VarP $ H.mkName "p",
                 H.AsP an (H.RecP (qitenmCG n) []),
                 H.AsP bn (H.RecP (qitenmCG n) [])]
      itebody = H.RecConE (qitenmCG n) (map mkfe cs ++ [efe])
      itecon = H.Clause itepats (H.NormalB itebody) []

      lprimpats = [H.VarP $ H.mkName "p",
                   H.AsP an (H.ConP (qprimnmCG n) [H.VarP (H.mkName "r"), H.VarP $ H.mkName "c"]),
                   bp]
      lprimbody = foldl1 H.AppE [
         H.ConE $ qprimnmCG n,
         foldl1 H.AppE (map H.VarE [H.mkName $ "Smten.iterealize", H.mkName "p", an, bn]),
         ite (H.VarE $ H.mkName "c") be]
      lprimcon = H.Clause lprimpats (H.NormalB lprimbody) []

      rprimpats = [H.VarP $ H.mkName "p", ap,
                   H.AsP bn (H.ConP (qprimnmCG n) [H.VarP (H.mkName "r"), H.VarP $ H.mkName "c"])]
      rprimbody = foldl1 H.AppE [
         H.ConE $ qprimnmCG n,
         foldl1 H.AppE (map H.VarE [H.mkName $ "Smten.iterealize", H.mkName "p", an, bn]),
         ite ae (H.VarE $ H.mkName "c")]
      rprimcon = H.Clause rprimpats (H.NormalB rprimbody) []

      defpats = [H.VarP $ H.mkName "p", ap, bp]
      defbody = ite (H.AppE (H.VarE $ qliftitenmCG n) ae)
                    (H.AppE (H.VarE $ qliftitenmCG n) be)
      defcon = H.Clause defpats (H.NormalB defbody) []

  return $ H.FunD (H.mkName $ "ite" ++ show k) (map mkcon cs ++ [errcon, lprimcon, rprimcon, itecon, defcon])

--   errorN = Foo_Error
errorD :: Name -> Int -> CG H.Dec
errorD nm n = do
  let body = H.NormalB $ H.VarE (qerrnmCG nm)
      fun = H.ValD (H.VarP (H.mkName $ "error" ++ show n)) body []
  return fun

--   realizeN m (FooA x1 x2 ...) = FooA (realize m x1) (realize m x2) ...
--   realizeN m (FooB x1 x2 ...) = FooB (realize m x1) (realize m x2) ...
--   ...
--   realizeN m (Foo_Prim r _) = r m
--   realizeN m x@(Foo_Ite {}) = flrealize m [__iteFooA x, __iteFooB x, ...]
--   realizeN m x@(Foo_Error _) = x
realizeD :: Name -> Int -> [Con] -> CG H.Dec
realizeD n k cs = do
  let mkcon :: Con -> H.Clause
      mkcon (Con cn cts) =
        let xs = [H.mkName $ "x" ++ show i | i <- [1..length cts]]
            pats = [H.VarP $ H.mkName "m", H.ConP (qnameCG cn) (map H.VarP xs)]
            rs = [foldl1 H.AppE [
                    H.VarE (H.mkName "Smten.realize"),
                    H.VarE (H.mkName "m"),
                    H.VarE x] | x <- xs]
            body = foldl H.AppE (H.ConE (qnameCG cn)) rs
        in H.Clause pats (H.NormalB body) []

      primpats = [H.VarP $ H.mkName "m", H.ConP (qprimnmCG n) [H.VarP (H.mkName "r"), H.WildP]]
      primbody = H.AppE (H.VarE (H.mkName "r")) (H.VarE (H.mkName "m"))
      primcon = H.Clause primpats (H.NormalB primbody) []

      itecons = [H.AppE (H.VarE $ qiteflnmCG cn) (H.VarE $ H.mkName "x") | Con cn _ <- cs]
      iteerr = H.AppE (H.VarE $ qiteerrnmCG n) (H.VarE $ H.mkName "x")
      itepats = [H.VarP $ H.mkName "m", H.AsP (H.mkName "x") (H.RecP (qitenmCG n) [])]
      itebody = foldl1 H.AppE [
                    H.VarE $ H.mkName "Smten.flrealize",
                    H.VarE $ H.mkName "m",
                    H.ListE $ itecons ++ [iteerr]]
      itecon = H.Clause itepats (H.NormalB itebody) []

      errpats = [H.VarP $ H.mkName "m", H.AsP (H.mkName "x") (H.ConP (qerrnmCG n) [H.WildP])]
      errbody = H.VarE $ H.mkName "x"
      errcon = H.Clause errpats (H.NormalB errbody) []
  return $ H.FunD (H.mkName $ "realize" ++ show k) (map mkcon cs ++ [primcon, itecon, errcon])

-- sappN f x@(Foo_Ite {}) = flsapp f x [__iteFooA x, __iteFooB x, ...]
-- sappN f (Foo_Error msg) = error0 msg
-- sappN f (Foo_Prim r c) = primsapp f r c
-- sappN f x = f x
sappD :: Name -> Int -> [Con] -> CG H.Dec
sappD n k cs = do
  let primpats = [H.VarP $ H.mkName "f", H.ConP (qprimnmCG n) [H.VarP (H.mkName "r"), H.VarP (H.mkName "c")]]
      primbody = foldl1 H.AppE [
                    H.VarE $ H.mkName "Smten.primsapp",
                    H.VarE $ H.mkName "f",
                    H.VarE $ H.mkName "r",
                    H.VarE $ H.mkName "c"]
      primcon = H.Clause primpats (H.NormalB primbody) []

      x = H.VarE $ H.mkName "x"

      itecons = [H.AppE (H.VarE $ qiteflnmCG cn) x | Con cn _ <- cs]
      iteerr = H.AppE (H.VarE $ qiteerrnmCG n) x
      itepats = [H.VarP $ H.mkName "f", H.AsP (H.mkName "x") (H.RecP (qitenmCG n) [])]
      itebody = foldl1 H.AppE [
                    H.VarE $ H.mkName "Smten.flsapp",
                    H.VarE $ H.mkName "f", x,
                    H.ListE $ itecons ++ [iteerr]]
      itecon = H.Clause itepats (H.NormalB itebody) []

      errpats = [H.VarP $ H.mkName "f", H.ConP (qerrnmCG n) [H.VarP $ H.mkName "msg"]]
      errbody = H.AppE (H.VarE $ H.mkName "Smten.error0") (H.VarE $ H.mkName "msg")
      errcon = H.Clause errpats (H.NormalB errbody) []

      defpats = [H.VarP $ H.mkName "f", H.VarP $ H.mkName "x"]
      defbody = H.AppE (H.VarE $ H.mkName "f") (H.VarE $ H.mkName "x")
      defcon = H.Clause defpats (H.NormalB defbody) []
  return $ H.FunD (H.mkName $ "sapp" ++ show k) [itecon, errcon, primcon, defcon]

mkIteHelpersD :: Name -> [TyVar] -> [Con] -> CG [H.Dec]
mkIteHelpersD n ts cs = do
    null <- mkNullIteD n ts cs
    to <- mkLiftIteD n ts cs
    return $ concat [null, to]

-- __IteNullFoo :: Foo a b ...
-- __IteNullFoo = Foo_Ite {
--    __fl* = Nothing,
--    ...
-- }
mkNullIteD :: Name -> [TyVar] -> [Con] -> CG [H.Dec]
mkNullIteD n ts cs = do
  let dt = appsT (conT n) (map tyVarType ts)
  H.SigD _ ty' <- topSigCG (TopSig (name "DONT_CARE") [] dt)
  let sig = H.SigD (nullitenmCG n) ty'

      fes = [(iteflnmCG cn, H.ConE $ H.mkName "Prelude.Nothing") | Con cn _ <- cs]
      efe = (iteerrnmCG n, H.ConE $ H.mkName "Prelude.Nothing")
      body = H.RecConE (qitenmCG n) (fes ++ [efe])
      clause = H.Clause [] (H.NormalB body) []
      fun = H.FunD (nullitenmCG n) [clause]
  return [sig, fun]

-- __IteLiftFoo :: Foo a b ... -> Foo a b ...
-- __IteLiftFoo x@(FooA {}) = (__IteNullFoo :: Foo a b ...) {
--         __iteFooA = Just (True, x)
--         }
--  ...
-- __IteLiftFoo x@(Foo_Error msg) = (__IteNullFoo :: Foo a b ...) {
--         __iteErrFoo = Just (True, x)
--         }
-- __IteLiftFoo x@(Foo_Ite {}) = x
-- __IteLiftFoo (Foo_Prim {}) = Prelude.error "iteliftFoo.prim"
mkLiftIteD :: Name -> [TyVar] -> [Con] -> CG [H.Dec]
mkLiftIteD n ts cs = do
  let dt = appsT (conT n) (map tyVarType ts)
      ty = arrowT dt dt
  tyme <- typeCG dt
  H.SigD _ ty' <- topSigCG (TopSig (name "DONT_CARE") [] ty)
  let sig = H.SigD (liftitenmCG n) ty'

      mkcon :: Con -> H.Clause
      mkcon (Con cn cts) =
        let pats = [H.AsP (H.mkName "x") (H.RecP (qnameCG cn) [])]
            tuple = H.TupE [H.ConE $ H.mkName "Smten.True", H.VarE $ H.mkName "x"]
            fields = [(iteflnmCG cn, H.AppE (H.ConE $ H.mkName "Prelude.Just") tuple)]
            body = H.RecUpdE (H.SigE (H.VarE $ qnullitenmCG n) tyme) fields
        in H.Clause pats (H.NormalB body) []

      errpats = [H.AsP (H.mkName "x") (H.RecP (qerrnmCG n) [])]
      errtuple = H.TupE [H.ConE $ H.mkName "Smten.True", H.VarE $ H.mkName "x"]
      errfields = [(iteerrnmCG n, H.AppE (H.ConE $ H.mkName "Prelude.Just") errtuple)]
      errbody = H.RecUpdE (H.SigE (H.VarE $ qnullitenmCG n) tyme) errfields
      errcon = H.Clause errpats (H.NormalB errbody) []

      itepats = [H.AsP (H.mkName "x") (H.RecP (qitenmCG n) [])]
      itebody = H.VarE $ H.mkName "x"
      itecon = H.Clause itepats (H.NormalB itebody) []

      primpats = [H.RecP (qprimnmCG n) []]
      primbody = H.AppE (H.VarE $ H.mkName "Prelude.error")
                        (H.LitE $ H.StringL (H.nameBase (liftitenmCG n) ++ ".prim"))
      primcon = H.Clause primpats (H.NormalB primbody) []

      fun = H.FunD (liftitenmCG n) (map mkcon cs ++ [primcon, itecon, errcon])
  return [sig, fun]

