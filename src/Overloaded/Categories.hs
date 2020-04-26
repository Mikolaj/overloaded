{-# LANGUAGE CPP          #-}
{-# LANGUAGE PolyKinds    #-}
{-# LANGUAGE TypeFamilies #-}
-- | Overloaded Categories, desugar @Arrow@ into classes in this module.
--
-- == Enabled with
--
-- @
-- {-\# OPTIONS -fplugin=Overloaded -fplugin-opt=Overloaded:Categories #-}
-- @
--
-- == Description
--
-- @Arrows@ notation - [GHC manual chapter](https://downloads.haskell.org/~ghc/8.10.1/docs/html/users_guide/glasgow_exts.html#arrow-notation) -
-- is cool, but it desugars into /"wrong"/ classes.
-- The 'arr' combinator is used for plumbing. We should desugar to proper
-- type-classes:
--
-- * 'CartesianCategory', not 'Arrow'
-- * 'CocartesianCategory', not 'ArrowChoice' (implementation relies on 'BicartesianCategory')
-- * 'CCC', not 'ArrowApply' (not implemented yet)
--
-- == Examples
--
-- Expression like
--
-- @
-- catAssoc
--     :: 'CartesianCategory' cat
--     => cat ('Product' cat ('Product' cat a b) c) ('Product' cat a ('Product' cat b c))
-- catAssoc = proc ((x, y), z) -> 'identity' -< (x, (y, z))
-- @
--
-- are desugared to (a mess which is)
--
-- @
-- 'fanout' ('proj1' '%%' 'proj1') ('fanout' ('proj2' '%%' 'proj1') 'proj2')
-- @
--
-- If you are familiar with arrows-operators, this is similar to
--
-- @
-- ('fst' . 'fst') '&&&' ('snd' . 'fst' '&&&' 'snd')
-- @
--
-- expression.
--
-- The @catAssoc@ could be instantiated to @cat = (->)@,
-- or more interestingly for example instantiate it to STLC morphisms to get an expression
-- like:
--
-- @
-- Lam (Pair (Fst (Fst (Var Here))) (Pair (Snd (Fst (Var Here))) (Snd (Var Here))))
-- @
--
-- @proc@ notation is nicer than writing de Bruijn indices.
--
-- This is very similar idea to Conal Elliott's [Compiling to Categories](http://conal.net/papers/compiling-to-categories/) work.
-- This approach is syntactically more heavy, but works in more correct
-- stage of compiler, before actual desugarer.
--
-- As one more example, we implement the automatic differentiation,
-- as in Conal's paper(s).
-- To keep things simple we use
--
-- @
-- newtype AD a b = AD (a -> (b, a -> b))
-- @
--
-- representation, i.e. use ordinary maps to represent linear maps.
-- We then define a function
--
-- @
-- evaluateAD :: Functor f => AD a b -> a -> f a -> (b, f b)
-- evaluateAD (AD f) x xs = let (y, f') = f x in (y, fmap f' xs)
-- @
--
-- which would allow to calculuate function value and
-- derivatives in given directions. Then we can define
-- simple quadratic function:
--
-- @
-- quad :: AD (Double, Double) Double
-- quad = proc (x, y) -> do
--     x2 <- mult -< (x, x)
--     y2 <- mult -< (y, y)
--     plus -< (x2, y2)
-- @
--
-- It's not as simple as writing @quad x y = x * x + y * y@,
-- but not /too far/.
--
-- Then we can play with it. At origo everything is zero:
--
-- @
-- let sqrthf = 1 / sqrt 2
-- in evaluateAD quad (0, 0) [(1,0), (0,1), (sqrthf, sqrthf)] = (0.0,[0.0,0.0,0.0])
-- @
--
-- If we evaluate at some other point, we see things working:
--
-- @
-- evaluateAD quad (1, 2) [(1,0), (0,1), (sqrthf, sqrthf)] = (5.0,[2.0,4.0,4.242640687119285])
-- @
--
-- Obviously, if we would use inspectable representation for linear maps,
-- as Conal describe, we'd get more benefits. And then 'arr' wouldn't
-- be definable!
--
module Overloaded.Categories (
    C.Category,
    identity,
    (%%),
    CategoryWith1 (..),
    CartesianCategory (..),
    CategoryWith0 (..),
    CocartesianCategory (..),
    BicartesianCategory (..),
    CCC (..),
    GeneralizedElement (..),
    ) where

import qualified Control.Category as C

import Data.Functor.Contravariant (Op (..))
import Data.Kind                  (Type)
import Data.Semigroupoid.Dual     (Dual (..))
import Data.Void                  (Void, absurd)

#ifdef __HADDOCK__
import Control.Arrow
#endif

-------------------------------------------------------------------------------
-- Category
-------------------------------------------------------------------------------

-- | A non-clashing name for 'C.id'.
identity :: C.Category cat => cat a a
identity = C.id
{-# INLINE identity #-}

-- | A non-clashing name for @('C..')@.
(%%) :: C.Category cat => cat b c -> cat a b -> cat a c
(%%) = (C..)
{-# INLINE (%%) #-}
infixr 9 %%

-------------------------------------------------------------------------------
-- Monoidal
-------------------------------------------------------------------------------

-- TODO

-------------------------------------------------------------------------------
-- Product
-------------------------------------------------------------------------------

-- | Category with terminal object.
class C.Category cat => CategoryWith1 (cat :: k -> k -> Type) where
    type Terminal cat :: k

    terminal :: cat a (Terminal cat)

-- | Cartesian category is a monoidal category
-- where monoidal product is the categorical product.
--
class CategoryWith1 cat => CartesianCategory (cat :: k -> k -> Type) where
    type Product cat :: k -> k -> k

    proj1 :: cat (Product cat a b) a
    proj2 :: cat (Product cat a b) b

    -- | @'fanout' f g@ is written as \(\langle f, g \rangle\) in category theory literature.
    fanout :: cat a b -> cat a c -> cat a (Product cat b c)

instance CategoryWith1 (->) where
    type Terminal (->) = ()

    terminal _ = ()

instance CartesianCategory (->) where
    type Product (->) = (,)

    proj1 = fst
    proj2 = snd
    fanout f g x = (f x , g x)

instance CategoryWith1 Op where
    type Terminal Op = Void

    terminal = Op absurd

instance CartesianCategory Op where
    type Product Op = Either

    proj1 = Op inl
    proj2 = Op inr
    fanout (Op f) (Op g) = Op (fanin f g)

-------------------------------------------------------------------------------
-- Coproduct
-------------------------------------------------------------------------------

-- | Category with initial object.
class C.Category cat => CategoryWith0 (cat :: k -> k -> Type) where
    type Initial cat :: k

    initial :: cat (Initial cat) a

-- | Cocartesian category is a monoidal category
-- where monoidal product is the categorical coproduct.
--
class CategoryWith0 cat => CocartesianCategory (cat :: k -> k -> Type) where
    type Coproduct cat :: k -> k -> k

    inl :: cat a (Coproduct cat a b)
    inr :: cat b (Coproduct cat a b)

    -- | @'fanin' f g@ is written as \([f, g]\) in category theory literature.
    fanin :: cat a c -> cat b c -> cat (Coproduct cat a b) c

instance CategoryWith0 (->) where
    type Initial (->) = Void

    initial = absurd

instance CocartesianCategory (->) where
    type Coproduct (->) = Either

    inl = Left
    inr = Right
    fanin = either

instance CategoryWith0 Op where
    type Initial Op = ()

    initial = Op (const ())

instance CocartesianCategory Op where
    type Coproduct Op = (,)

    inl = Op proj1
    inr = Op proj2
    fanin (Op f) (Op g) = Op (fanout f g)

-- | Bicartesian category is category which is
-- both cartesian and cocartesian.
--
-- We also require distributive morpism.
class (CartesianCategory cat, CocartesianCategory cat) => BicartesianCategory cat where
    distr :: cat (Product cat (Coproduct cat a b) c)
                 (Coproduct cat (Product cat a c) (Product cat b c))

instance BicartesianCategory (->) where
    distr (Left x,  z) = Left (x, z)
    distr (Right y, z) = Right (y, z)

-------------------------------------------------------------------------------
-- Dual
-------------------------------------------------------------------------------

instance CategoryWith1 cat => CategoryWith0 (Dual cat) where
    type Initial (Dual cat) = Terminal cat
    initial = Dual terminal

instance CategoryWith0 cat => CategoryWith1 (Dual cat) where
    type Terminal (Dual cat) = Initial cat
    terminal = Dual initial

instance CartesianCategory cat => CocartesianCategory (Dual cat) where
    type Coproduct (Dual cat) = Product cat

    inl = Dual proj1
    inr = Dual proj2

    fanin (Dual f) (Dual g) = Dual (fanout f g)

instance CocartesianCategory cat => CartesianCategory (Dual cat) where
    type Product (Dual cat) = Coproduct cat

    proj1 = Dual inl
    proj2 = Dual inr

    fanout (Dual f) (Dual g) = Dual (fanin f g)

-------------------------------------------------------------------------------
-- Exponential
-------------------------------------------------------------------------------

-- | Closed cartesian category.
--
class CartesianCategory cat => CCC (cat :: k -> k -> Type) where
    -- | @'Exponential' cat a b@ represents \(B^A\). This is due how (->) works.
    type Exponential cat :: k -> k -> k

    eval :: cat (Product cat (Exponential cat a b) a) b

    transpose :: cat (Product cat a b) c -> cat a (Exponential cat b c)

instance CCC (->) where
    type Exponential (->) = (->)

    eval      = uncurry ($)
    transpose = curry

-------------------------------------------------------------------------------
-- Generalized Element
-------------------------------------------------------------------------------

class C.Category cat => GeneralizedElement (cat :: k -> k -> Type) where
    type Object cat (a :: k) :: Type

    konst :: Object cat a -> cat x a

instance GeneralizedElement (->) where
    type Object (->) a = a

    konst = const
