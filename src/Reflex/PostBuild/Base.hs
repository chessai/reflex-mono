-- | This module defines 'PostBuildT', the standard implementation of
-- 'PostBuild'.
{-# LANGUAGE CPP #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE RecursiveDo #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -fno-warn-orphans #-} --FIXME
#ifdef USE_REFLEX_OPTIMIZER
{-# OPTIONS_GHC -fplugin=Reflex.Optimizer #-}
#endif
module Reflex.PostBuild.Base
  ( PostBuildT (..)
  -- , runPostBuildT
  -- * Internal
  , mapIntMapWithAdjustImpl
  , mapDMapWithAdjustImpl
  ) where

import Reflex
import Reflex.Patch.DMap (mapPatchDMap)
import Reflex.Patch.DMapWithMove (mapPatchDMapWithMove)
import Reflex.PerformEvent.Class
import Reflex.PostBuild.Class
import Reflex.TriggerEvent.Class

import Control.Applicative (liftA2)
-- import Control.Monad.Exception
import Control.Monad.Identity
import Control.Monad.Primitive
import Control.Monad.Reader
import Control.Monad.Ref
import qualified Control.Monad.Trans.Control as TransControl
import Data.Dependent.Map (DMap)
import qualified Data.Dependent.Map as DMap
import Data.Functor.Compose
import Data.IntMap.Strict (IntMap)
import qualified Data.IntMap.Strict as IntMap
import qualified Data.Semigroup as S

-- | Provides a basic implementation of 'PostBuild'.
-- newtype PostBuildT m a = PostBuildT { unPostBuildT :: ReaderT (Event ()) m a } deriving (Functor, Applicative, Monad, MonadFix, MonadIO, MonadTrans, MonadException, MonadAsyncException)

-- | Run a 'PostBuildT' action.  An 'Event' should be provided that fires
-- immediately after the action is finished running; no other 'Event's should
-- fire first.
-- {-# INLINABLE runPostBuildT #-}
-- runPostBuildT :: PostBuildT m a -> Event () -> m a
-- runPostBuildT (PostBuildT a) = runReaderT a

-- TODO: Monoid and Semigroup can likely be derived once ReaderT has them.
instance (Monoid a, Applicative m) => Monoid (PostBuildT m a) where
  mempty = pure mempty
  mappend = liftA2 mappend

instance (S.Semigroup a, Applicative m) => S.Semigroup (PostBuildT m a) where
  (<>) = liftA2 (S.<>)

instance PrimMonad m => PrimMonad (PostBuildT m) where
  type PrimState (PostBuildT m) = PrimState m
  primitive = lift . primitive

instance (Monad m) => PostBuild (PostBuildT m) where
  {-# INLINABLE getPostBuild #-}
  getPostBuild = PostBuildT ask

instance MonadSample m => MonadSample (PostBuildT m) where
  {-# INLINABLE sample #-}
  sample = lift . sample

instance MonadHold m => MonadHold (PostBuildT m) where
  {-# INLINABLE hold #-}
  hold v0 = lift . hold v0
  {-# INLINABLE holdDyn #-}
  holdDyn v0 = lift . holdDyn v0
  {-# INLINABLE holdIncremental #-}
  holdIncremental v0 = lift . holdIncremental v0
  {-# INLINABLE buildDynamic #-}
  buildDynamic a0 = lift . buildDynamic a0
  {-# INLINABLE headE #-}
  headE = lift . headE

instance PerformEvent m => PerformEvent (PostBuildT m) where
  type Performable (PostBuildT m) = Performable m
  {-# INLINABLE performEvent_ #-}
  performEvent_ = lift . performEvent_
  {-# INLINABLE performEvent #-}
  performEvent = lift . performEvent

instance (MonadReflexCreateTrigger m) => MonadReflexCreateTrigger (PostBuildT m) where
  {-# INLINABLE newEventWithTrigger #-}
  newEventWithTrigger = PostBuildT . lift . newEventWithTrigger
  {-# INLINABLE newFanEventWithTrigger #-}
  newFanEventWithTrigger f = PostBuildT $ lift $ newFanEventWithTrigger f

instance TriggerEvent m => TriggerEvent (PostBuildT m) where
  {-# INLINABLE newTriggerEvent #-}
  newTriggerEvent = lift newTriggerEvent
  {-# INLINABLE newTriggerEventWithOnComplete #-}
  newTriggerEventWithOnComplete = lift newTriggerEventWithOnComplete
  newEventWithLazyTriggerWithOnComplete = lift . newEventWithLazyTriggerWithOnComplete

instance MonadRef m => MonadRef (PostBuildT m) where
  type Ref (PostBuildT m) = Ref m
  {-# INLINABLE newRef #-}
  newRef = lift . newRef
  {-# INLINABLE readRef #-}
  readRef = lift . readRef
  {-# INLINABLE writeRef #-}
  writeRef r = lift . writeRef r

instance MonadAtomicRef m => MonadAtomicRef (PostBuildT m) where
  {-# INLINABLE atomicModifyRef #-}
  atomicModifyRef r = lift . atomicModifyRef r

instance (MonadHold m, MonadFix m, Adjustable m, PerformEvent m) => Adjustable (PostBuildT m) where
  runWithReplace a0 a' = do
    postBuild <- getPostBuild
    lift $ do
      rec result@(_, result') <- runWithReplace (runPostBuildT a0 postBuild) $ fmap (\v -> runPostBuildT v =<< headE voidResult') a'
          let voidResult' = fmapCheap (\_ -> ()) result'
      return result
  traverseIntMapWithKeyAdjust = mapIntMapWithAdjustImpl traverseIntMapWithKeyAdjust
  {-# INLINABLE traverseIntMapWithKeyAdjust #-}
  traverseDMapWithKeyWithAdjust = mapDMapWithAdjustImpl traverseDMapWithKeyWithAdjust mapPatchDMap
  {-# INLINABLE traverseDMapWithKeyWithAdjust #-}
  traverseDMapWithKeyWithAdjustWithMove = mapDMapWithAdjustImpl traverseDMapWithKeyWithAdjustWithMove mapPatchDMapWithMove

{-# INLINABLE mapIntMapWithAdjustImpl #-}
mapIntMapWithAdjustImpl :: forall m v v' p. (MonadFix m, MonadHold m, Functor p)
  => (   (IntMap.Key -> (Event (), v) -> m v')
      -> IntMap (Event (), v)
      -> Event (p (Event (), v))
      -> m (IntMap v', Event (p v'))
     )
  -> (IntMap.Key -> v -> PostBuildT m v')
  -> IntMap v
  -> Event (p v)
  -> PostBuildT m (IntMap v', Event (p v'))
mapIntMapWithAdjustImpl base f dm0 dm' = do
  postBuild <- getPostBuild
  let loweredDm0 = fmap ((,) postBuild) dm0
      f' :: IntMap.Key -> (Event (), v) -> m v'
      f' k (e, v) = do
        runPostBuildT (f k v) e
  lift $ do
    rec (result0, result') <- base f' loweredDm0 loweredDm'
        cohortDone <- numberOccurrencesFrom_ 1 result'
        numberedDm' <- numberOccurrencesFrom 1 dm'
        let postBuild' = fanInt $ fmapCheap (`IntMap.singleton` ()) cohortDone
            loweredDm' = flip pushAlways numberedDm' $ \(n, p) -> do
              return $ fmap ((,) (selectInt postBuild' n)) p
    return (result0, result')

{-# INLINABLE mapDMapWithAdjustImpl #-}
mapDMapWithAdjustImpl :: forall m k v v' p. (MonadFix m, MonadHold m)
  => (   (forall a. k a -> Compose ((,) (Bool, Event ())) v a -> m (v' a))
      -> DMap k (Compose ((,) (Bool, Event ())) v)
      -> Event (p k (Compose ((,) (Bool, Event ())) v))
      -> m (DMap k v', Event (p k v'))
     )
  -> ((forall a. v a -> Compose ((,) (Bool, Event ())) v a) -> p k v -> p k (Compose ((,) (Bool, Event ())) v))
  -> (forall a. k a -> v a -> PostBuildT m (v' a))
  -> DMap k v
  -> Event (p k v)
  -> PostBuildT m (DMap k v', Event (p k v'))
mapDMapWithAdjustImpl base mapPatch f dm0 dm' = do
  postBuild <- getPostBuild
  let loweredDm0 = DMap.map (Compose . (,) (False, postBuild)) dm0
      f' :: forall a. k a -> Compose ((,) (Bool, Event ())) v a -> m (v' a)
      f' k (Compose ((shouldHeadE, e), v)) = do
        eOnce <- if shouldHeadE
          then headE e --TODO: Avoid doing this headE so many times; once per loweredDm' firing ought to be OK, but it's not totally trivial to do because result' might be firing at the same time, and we don't want *that* to be the postBuild occurrence
          else return e
        runPostBuildT (f k v) eOnce
  lift $ do
    rec (result0, result') <- base f' loweredDm0 loweredDm'
        let voidResult' = fmapCheap (\_ -> ()) result'
        let loweredDm' = ffor dm' $ mapPatch (Compose . (,) (True, voidResult'))
    return (result0, result')

--------------------------------------------------------------------------------
-- Deprecated functionality
--------------------------------------------------------------------------------

-- | Deprecated
instance TransControl.MonadTransControl (PostBuildT) where
  type StT (PostBuildT) a = TransControl.StT (ReaderT (Event ())) a
  {-# INLINABLE liftWith #-}
  liftWith = TransControl.defaultLiftWith PostBuildT unPostBuildT
  {-# INLINABLE restoreT #-}
  restoreT = TransControl.defaultRestoreT PostBuildT
