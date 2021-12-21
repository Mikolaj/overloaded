{-# LANGUAGE DataKinds            #-}
{-# LANGUAGE FlexibleContexts     #-}
{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE GADTs                #-}
{-# LANGUAGE PatternSynonyms      #-}
{-# LANGUAGE RankNTypes           #-}
{-# LANGUAGE ScopedTypeVariables  #-}
{-# LANGUAGE StandaloneDeriving   #-}
{-# LANGUAGE TypeFamilies         #-}
{-# LANGUAGE TypeOperators        #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -Wall #-}
-- | This module is wrongly named.
module VectorSpace (
    LinMap (.., LI),
    lmul,
    HasDim(Dim, dimDict),
    toRawMatrix,
    evalL,
    L (..),
    forkF,
    evalAt,
    linear,
    VectorSpace (..),
    toVector,
    fromVector,
) where

import Data.Constraint       (Dict (..), withDict, (:-))
import Data.Proxy            (Proxy (..))
import GHC.TypeLits
import Overloaded.Categories

import qualified Control.Category      as C
import qualified Data.Constraint.Nat   as C
import qualified Numeric.LinearAlgebra as L

-- import qualified Numeric.LinearAlgebra.Static as LS

data LinMap a b where
    LZ :: LinMap a b
    LD :: Double -> LinMap a a
    LH :: LinMap a b -> LinMap a c -> LinMap a (b, c)
    LV :: LinMap a c -> LinMap b c -> LinMap (a, b) c
    LA :: LinMap a b -> LinMap a b -> LinMap a b
    LF :: (b -> LinMap a c) -> LinMap a (b -> c)
    LE :: b -> LinMap a (b -> c) -> LinMap a c

-- deriving instance Show (LinMap a b)

pattern LI :: forall a b. () => (b ~ a) => LinMap a b
pattern LI = LD 1

lmul :: Double -> LinMap a b -> LinMap a b
lmul _ LZ       = LZ
lmul k (LD x)   = LD (k * x)
lmul k (LH f g) = LH (lmul k f) (lmul k g)
lmul k (LV f g) = LV (lmul k f) (lmul k g)
lmul k (LA f g) = LA (lmul k f) (lmul k g)
lmul k (LF ff)  = LF $ \b -> lmul k (ff b)
lmul k (LE b f) = LE b $ lmul k f

lcomp :: LinMap b c -> LinMap a b -> LinMap a c
lcomp LZ       _        = LZ
lcomp _        LZ       = LZ
lcomp (LD k)   h        = lmul k h
lcomp h        (LD k)   = lmul k h
lcomp (LA f g) h        = LA (lcomp f h) (lcomp g h)
lcomp f        (LA g h) = LA (lcomp f g) (lcomp f h)
lcomp (LH f g) h        = LH (lcomp f h) (lcomp g h)
lcomp h        (LV f g) = LV (lcomp h f) (lcomp h g)
lcomp (LV f g) (LH u v) = LA (lcomp f u) (lcomp g v)
lcomp (LF ff)  h        = LF $ \b -> lcomp (ff b) h
lcomp (LE b f) h        = LE b (lcomp f h)
lcomp _h       (LE _b _f) = undefined  -- not enough tools

instance Category LinMap where
    id  = LI
    (.) = lcomp

instance CategoryWith1 LinMap where
    type Terminal LinMap = ()
    terminal = LZ

instance CartesianCategory LinMap where
    type Product LinMap = (,)
    proj1  = LV C.id LZ
    proj2  = LV LZ C.id
    fanout = LH

instance CategoryWith0 LinMap where
    type Initial LinMap = ()
    initial = LZ

instance CocartesianCategory LinMap where
    type Coproduct LinMap = (,)
    inl   = LH C.id LZ
    inr   = LH LZ C.id
    fanin = LV

instance BicartesianCategory LinMap where
    distr = LH
        (LH (LV (LV LI LZ) LZ) (LV LZ LI))
        (LH (LV (LV LZ LI) LZ) (LV LZ LI))

newtype L a b = L (forall r. LinMap r a -> LinMap r b)

forkF :: (b -> L a c) -> L a (b -> c)
forkF h = L $ \da -> LF $ \b -> let L g = h b in g da

evalAt :: b -> L (b -> c) c
evalAt b = L (LE b)

lfst :: LinMap a (b, c) -> LinMap a b
lfst (LA f g) = LA (lfst f) (lfst g)
lfst (LH f _) = f
lfst (LV f g) = LV (lfst f) (lfst g)
lfst LZ       = LZ
lfst (LD k)   = LV (LD k) LZ
lfst (LE _b _f) = undefined  -- not enough tools

lsnd :: LinMap a (b, c) -> LinMap a c
lsnd (LH _ g) = g
lsnd (LA f g) = LA (lsnd f) (lsnd g)
lsnd (LV f g) = LV (lsnd f) (lsnd g)
lsnd LZ       = LZ
lsnd (LD k)   = LV LZ (LD k)
lsnd (LE _b _f) = undefined  -- not enough tools

linitial :: LinMap r () -> LinMap r a
linitial _ = LZ

linear :: Double -> L a a
linear k = L $ lmul k

-- lmult :: Double -> Double -> LinMap r (a, a) -> LinMap r a
-- lmult x y (LH f g) = LA (LK y f) (LK x g)
-- lmult x y (LV f g) = LV (lmult x y f) (lmult x y g)
-- lmult x y (LA f g) = LA (lmult x y f) (lmult x y g)
-- lmult x y (LK k f) = LK k (lmult x y f)
-- lmult _ _ LZ       = LZ
-- lmult x y LI       = LV (LK y LI) (LK x LI)

instance Category L where
    id = L id
    L f . L g = L (f . g)

instance CategoryWith1 L where
    type Terminal L = ()

    terminal = L (\_ -> LZ)

instance CartesianCategory L where
    type Product L = (,)

    proj1 = L lfst
    proj2 = L lsnd

    fanout (L f) (L g) = L $ \x -> LH (f x) (g x)

instance CategoryWith0 L where
    type Initial L = ()

    initial = L linitial

-- Is this correct?
instance CocartesianCategory L where
    type Coproduct L = (,)

    inl = L $ \f -> LH f LZ
    inr = L $ \g -> LH LZ g

    fanin (L f) (L g) = L $ \x -> LA (f (lfst x)) (g (lsnd x))

class HasDim a where
    type Dim a :: Nat

    dimDict :: Proxy a -> Dict (KnownNat (Dim a))

    splitPair :: (a ~ (b, c)) => (Dict (HasDim b), Dict (HasDim c))
    splitPair = error "impossible: splitPair"

instance HasDim () where
    type Dim () = 0
    dimDict _ = Dict

instance HasDim Double where
    type Dim Double = 1
    dimDict _ = Dict

instance (HasDim a, HasDim b) => HasDim (a, b) where
    type Dim (a, b) = Dim a + Dim b

    dimDict _ =
        withDimDict (Proxy :: Proxy a) $
        withDimDict (Proxy :: Proxy b) $
        withDict (C.plusNat :: (KnownNat (Dim a), KnownNat (Dim b)) :- KnownNat (Dim a + Dim b))
        Dict

    splitPair = (Dict, Dict)


withDimDict :: HasDim a => Proxy a -> (KnownNat (Dim a) => r) -> r
withDimDict p = withDict (dimDict p)

dim :: forall a. HasDim a => Proxy a -> Int
dim p = withDimDict p $ fromInteger $ natVal (Proxy :: Proxy (Dim a))

toRawMatrix :: forall a b. (HasDim a, HasDim b) => LinMap a b -> L.Matrix Double
toRawMatrix LZ       = (dim (Proxy :: Proxy a) L.>< dim (Proxy :: Proxy b)) (repeat 0)
toRawMatrix (LD k)   = L.scale k (L.ident (dim (Proxy :: Proxy a)))
toRawMatrix (LA f g) = L.add (toRawMatrix f) (toRawMatrix g)
toRawMatrix (LH f g) = go splitPair f g where
    go :: (Dict (HasDim x), Dict (HasDim y)) -> LinMap a x -> LinMap a y -> L.Matrix Double
    go (Dict, Dict) f' g' = toRawMatrix f' L.||| toRawMatrix g'
toRawMatrix (LV f g) = go splitPair f g where
    go :: (Dict (HasDim x), Dict (HasDim y)) -> LinMap x b -> LinMap y b -> L.Matrix Double
    go (Dict, Dict) f' g' = toRawMatrix f' L.=== toRawMatrix g'
toRawMatrix LF{} = error "function space may not have a well defined dimension"
toRawMatrix LE{} = error "function space may not have a well defined dimension"

evalL :: (HasDim a, HasDim b) => L a b -> L.Matrix Double
evalL (L f) = toRawMatrix (f (LD 1))

-- toStaticMatrix :: forall a b. (HasDim a, HasDim b) => LinMap a b -> LS.L (Dim a) (Dim b)
-- toStaticMatrix LZ =
--     withDimDict (Proxy :: Proxy a) $
--     withDimDict (Proxy :: Proxy b) 0
-- toStaticMatrix LI =
--     withDimDict (Proxy :: Proxy a) LS.eye
-- toStaticMatrix (LA f g) =
--     withDimDict (Proxy :: Proxy a) $
--     withDimDict (Proxy :: Proxy b) $
--     L.add (toStaticMatrix f) (toStaticMatrix g)
-- toStaticMatrix (LK k f) =
--     withDimDict (Proxy :: Proxy a) $
--     withDimDict (Proxy :: Proxy b) $
--     toStaticMatrix f LS.<> LS.diag (LS.konst k)
-- toStaticMatrix (LH f g) = go splitPair f g where
--     go :: forall x y. (x,y) ~ b => (Dict (HasDim x), Dict (HasDim y)) -> LinMap a x -> LinMap a y -> LS.L (Dim a) (Dim x + Dim y)
--     go (Dict, Dict) f' g' =
--         withDimDict (Proxy :: Proxy a) $
--         withDimDict (Proxy :: Proxy b) $
--         withDimDict (Proxy :: Proxy x) $
--         withDimDict (Proxy :: Proxy y) $
--         toStaticMatrix f' LS.||| toStaticMatrix g'
-- toStaticMatrix (LV f g) = go splitPair f g where
--     go :: forall x y. (x,y) ~ a => (Dict (HasDim x), Dict (HasDim y)) -> LinMap x b -> LinMap y b -> LS.L (Dim x + Dim y) (Dim b)
--     go (Dict, Dict) f' g' =
--         withDimDict (Proxy :: Proxy a) $
--         withDimDict (Proxy :: Proxy b) $
--         withDimDict (Proxy :: Proxy x) $
--         withDimDict (Proxy :: Proxy y) $
--         toStaticMatrix f' LS.=== toStaticMatrix g'

-------------------------------------------------------------------------------
-- Vector space
-------------------------------------------------------------------------------

class HasDim a => VectorSpace a where
    toVector' :: a -> [Double] -> [Double]

    fromVector' :: [Double] -> (a -> [Double] -> r) -> r

toVector :: VectorSpace a => a -> [Double]
toVector x = toVector' x []

fromVector :: VectorSpace a => [Double] -> a
fromVector ds = fromVector' ds const

instance VectorSpace Double where
    toVector' d = (d :)

    fromVector' []     k = k 0 []
    fromVector' (d:ds) k = k d ds

instance (VectorSpace a, VectorSpace b) => VectorSpace (a, b) where
    toVector' (a, b) = toVector' a . toVector' b

    fromVector' xs k =
        fromVector' xs $ \a ys ->
        fromVector' ys $ \b zs ->
        k (a, b) zs
