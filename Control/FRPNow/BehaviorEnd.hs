{-# LANGUAGE DoAndIfThenElse, FlexibleInstances , MultiParamTypeClasses,GADTs, TypeOperators, TupleSections, ScopedTypeVariables,ConstraintKinds,FlexibleContexts,UndecidableInstances #-}
-----------------------------------------------------------------------------
-- |
-- Module      :  Control.FRPNow.Until
-- Copyright   :  (c) Atze van der Ploeg 2015
-- License     :  BSD-style
-- Maintainer  :  atzeus@gmail.org
-- Stability   :  provisional
-- Portability :  portable
-- 
-- The until abstraction, and related definitions.
--
--
-- A value of type @BehaviorEnd@ is a behavior and an ending event.
-- This also forms a monad, such that we can write
-- 
-- > do a1 `Until` e1
-- >    b1 `Until` e2
--
-- for behaviors consisting of multiple phases.
-- This concept is similar to "Monadic FRP" (Haskell symposium 2013, van der Ploeg) and
--  the Task monad abstraction (Lambda in motion: Controlling robots with haskell, Peterson, Hudak and Elliot, PADL 1999) 
module Control.FRPNow.BehaviorEnd(
   -- * Until
   BehaviorEnd(..), combineUntil, (.:),parList,
   -- * Derived monads
   -- $compose
   
   till,
   (:.)(..), 
   Swap(..),
   liftLeft,
   liftRight)
  where
import Control.FRPNow.Core
import Control.FRPNow.Lib
import Control.FRPNow.EvStream
import Control.Monad
import Control.Applicative

data BehaviorEnd x a = Until { behavior :: Behavior x, end ::  Event a }

instance Monad (BehaviorEnd x) where
  return x = pure (error "ended!") `Until` pure x
  (b `Until` e) >>= f  =
     let v = f <$> e
         b' = b `switch` (behavior <$> v)
         e' = v >>= end
     in b' `Until` e'

instance Functor (BehaviorEnd x) where fmap = liftM
instance Applicative (BehaviorEnd x) where pure = return ; (<*>) = ap

-- | Combine the behavior of the @Until@ and the other behavior until the
-- with the given function until the end event happens.
combineUntil :: (a -> b -> b) -> BehaviorEnd a x -> Behavior b -> Behavior b
combineUntil f (bx `Until` e) b = (f <$> bx <*> b) `switch` fmap (const b) e

-- | Add the values in the behavior of the @Until@ to the front of the list 
-- until the end event happsens.
(.:) :: BehaviorEnd a x -> Behavior [a] -> Behavior [a]
(.:) = combineUntil (:)

-- | Given an eventstream that spawns behaviors with an end,
-- returns a behavior with list of the values of currently active 
-- behavior ends.
parList :: EvStream (BehaviorEnd b ()) -> Behavior (Behavior [b])
parList = foldBs (pure []) (flip (.:))

-- $compose
-- The monad for @Until@ is a bit restrictive, because we cannot sample other behaviors 
-- in this monad. For this reason we also define a monad for @(Behavior :. Until x)@, 
-- where @ :. @ is functor composition, which can sample other monads. 
-- This relies on the @swap@ construction from "Composing monads", Mark Jones and Luc Duponcheel.
--   

-- | Like 'Until', but the event can now be generated by a behavior (@Behavior (Event a)@) or even
-- (@Now (Event a)@). 
--
-- Name is not "until" to prevent a clash with 'Prelude.until'.
till :: Swap b (BehaviorEnd x) =>
          Behavior x -> b (Event a) -> (b :. BehaviorEnd x) a
till b e = liftLeft e >>= liftRight . (b `Until`)

instance (Swap b e, Sample b) => Sample (b :. e) where sample b = liftLeft (sample b)

assoc :: Functor f => ((f :. g) :. h) x -> (f :. (g :. h)) x
assoc = Close . fmap Close . open . open

coassoc :: Functor f => (f :. (g :. h)) x -> ((f :. g) :. h) x
coassoc = Close . Close . fmap open . open

instance (Functor a, Functor b) => Functor (a :. b) where 
  fmap f = Close . fmap (fmap f) . open

-- | Composition of functors.
newtype (f :. g) x = Close { open :: f (g x) }

-- | Lift a value from the left monad into the composite monad.
liftLeft :: (Monad f, Monad g) => f x -> (f :. g) x 
liftLeft = Close . liftM return 

-- | Lift a value from the right monad into the composite monad.
liftRight :: Monad f => g x -> (f :. g) x 
liftRight  = Close . return 


class (Monad f, Monad g) => Swap f g where
  -- | Swap the composition of two monads.
  -- Laws (from Composing Monads, Jones and Duponcheel)
  -- 
  -- > swap . fmap (fmap f) == fmap (fmap f) . swap
  -- > swap . return        == fmap unit
  -- > swap . fmap return   == return
  -- > prod . fmap dorp     == dorp . prod 
  -- >            where prod = fmap join . swap
  -- >                  dorp = join . fmap swap
  swap :: g (f a) -> f (g a)

instance Plan b => Swap b Event where
  swap = plan

instance (Monad b, Plan b) => Swap b (BehaviorEnd x) where
  swap (Until b e) = liftM (Until b) (plan e)

instance Swap f g => Monad (f :. g) where
  -- see (Composing Monads, Jones and Duponcheel) for proof
  return  = Close . return . return
  m >>= f = joinComp (fmap2m f m)

-- anoyance that Monad is not a subclass of functor
fmap2m f = Close . liftM (liftM f) . open

joinComp :: (Swap b e) => (b :. e) ((b :. e) x) -> (b :. e) x
joinComp = Close . joinFlip . open . fmap2m open

joinFlip :: (Swap b e, Monad e, Monad b) => b (e (b (e x))) -> b (e x)
joinFlip =  liftM join . join . liftM swap 
-- this works as follows, we have 
-- b . e . b . e      flip middle two
-- b . b . e . e      join left and right
-- b . e 


instance (Applicative b, Applicative e) => Applicative (b :. e) where
   pure = Close . pure . pure
   x <*> y = Close $ (<*>) <$> open x <*> open y  









