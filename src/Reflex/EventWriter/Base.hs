-- | This module provides 'EventWriterT', the standard implementation of
-- 'EventWriter'.
{-# LANGUAGE CPP #-}
{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE Rank2Types #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}
#ifdef USE_REFLEX_OPTIMIZER
{-# OPTIONS_GHC -fplugin=Reflex.Optimizer #-}
#endif
module Reflex.EventWriter.Base
  ( EventWriterT (..)
  , runEventWriterT
  , runWithReplaceEventWriterTWith
  , sequenceDMapWithAdjustEventWriterTWith
  , mapEventWriterT
  , withEventWriterT
  ) where

import Reflex
import Reflex.EventWriter.Class (EventWriter, tellEvent)
import Reflex.DynamicWriter.Class (MonadDynamicWriter, tellDyn)
-- import Reflex.Host.Class
import Reflex.PerformEvent.Class
import Reflex.PostBuild.Class
import Reflex.Query.Class
import Reflex.Requester.Class
import Reflex.TriggerEvent.Class
import Reflex.Patch

import Control.Monad.Exception
import Control.Monad.Identity
import Control.Monad.Primitive
import Control.Monad.Reader
import Control.Monad.Ref
import Control.Monad.State.Strict
import Data.Dependent.Map (DMap, DSum (..))
import qualified Data.Dependent.Map as DMap
import Data.Functor.Compose
import Data.Functor.Misc
import Data.GADT.Compare (GCompare (..), GEq (..), GOrdering (..))
import Data.IntMap.Strict (IntMap)
import qualified Data.IntMap.Strict as IntMap
import Data.List.NonEmpty (NonEmpty (..))
import Data.Map (Map)
import qualified Data.Map as Map
import Data.Semigroup
import Data.Some (Some)
import Data.Tuple
import Data.Type.Equality hiding (apply)

import Unsafe.Coerce

{-# DEPRECATED TellId "Do not construct this directly; use tellId instead" #-}
newtype TellId w x
  = TellId Int -- ^ WARNING: Do not construct this directly; use 'tellId' instead
  deriving (Show, Eq, Ord, Enum)

tellId :: Int -> TellId w w
tellId = TellId
{-# INLINE tellId #-}

tellIdRefl :: TellId w x -> w :~: x
tellIdRefl _ = unsafeCoerce Refl

withTellIdRefl :: TellId w x -> (w ~ x => r) -> r
withTellIdRefl tid r = case tellIdRefl tid of
  Refl -> r

instance GEq (TellId w) where
  a `geq` b =
    withTellIdRefl a $
    withTellIdRefl b $
    if a == b
    then Just Refl
    else Nothing

instance GCompare (TellId w) where
  a `gcompare` b =
    withTellIdRefl a $
    withTellIdRefl b $
    case a `compare` b of
      LT -> GLT
      EQ -> GEQ
      GT -> GGT

data EventWriterState w = EventWriterState
  { _eventWriterState_nextId :: {-# UNPACK #-} !Int -- Always negative (and decreasing over time)
  , _eventWriterState_told :: ![DSum (TellId w) (Event)] -- In increasing order
  }

-- | A basic implementation of 'EventWriter'.
newtype EventWriterT w m a = EventWriterT { unEventWriterT :: StateT (EventWriterState w) m a }
  deriving (Functor, Applicative, Monad, MonadFix, MonadIO, MonadException, MonadAsyncException)

-- | Run a 'EventWriterT' action.
runEventWriterT :: forall m w a. (Monad m, Semigroup w) => EventWriterT w m a -> m (a, Event w)
runEventWriterT (EventWriterT a) = do
  (result, requests) <- runStateT a $ EventWriterState (-1) []
  let combineResults :: DMap (TellId w) Identity -> w
      combineResults = sconcat
        . (\(h : t) -> h :| t) -- Unconditional; 'merge' guarantees that it will only fire with non-empty DMaps
        . DMap.foldlWithKey (\vs tid (Identity v) -> withTellIdRefl tid $ v : vs) [] -- This is where we finally reverse the DMap to get things in the correct order
  return (result, fmap combineResults $ merge $ DMap.fromDistinctAscList $ _eventWriterState_told requests) --TODO: We can probably make this fromDistinctAscList more efficient by knowing the length in advance, but this will require exposing internals of DMap; also converting it to use a strict list might help

instance (Monad m, Semigroup w) => EventWriter w (EventWriterT w m) where
  tellEvent w = EventWriterT $ modify $ \old ->
    let myId = _eventWriterState_nextId old
    in EventWriterState
       { _eventWriterState_nextId = pred myId
       , _eventWriterState_told = (tellId myId :=> w) : _eventWriterState_told old
       }

instance MonadTrans (EventWriterT w) where
  lift = EventWriterT . lift

instance MonadSample m => MonadSample (EventWriterT w m) where
  sample = lift . sample

instance MonadHold m => MonadHold (EventWriterT w m) where
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

instance (Adjustable m, MonadHold m, Semigroup w) => Adjustable (EventWriterT w m) where
  runWithReplace = runWithReplaceEventWriterTWith $ \dm0 dm' -> lift $ runWithReplace dm0 dm'
  traverseIntMapWithKeyAdjust = sequenceIntMapWithAdjustEventWriterTWith (\f dm0 dm' -> lift $ traverseIntMapWithKeyAdjust f dm0 dm') mergeIntIncremental coincidencePatchIntMap
  traverseDMapWithKeyWithAdjust = sequenceDMapWithAdjustEventWriterTWith (\f dm0 dm' -> lift $ traverseDMapWithKeyWithAdjust f dm0 dm') mapPatchDMap weakenPatchDMapWith mergeMapIncremental coincidencePatchMap
  traverseDMapWithKeyWithAdjustWithMove = sequenceDMapWithAdjustEventWriterTWith (\f dm0 dm' -> lift $ traverseDMapWithKeyWithAdjustWithMove f dm0 dm') mapPatchDMapWithMove weakenPatchDMapWithMoveWith mergeMapIncrementalWithMove coincidencePatchMapWithMove

instance Requester t m => Requester t (EventWriterT w m) where
  type Request (EventWriterT w m) = Request m
  type Response (EventWriterT w m) = Response m
  requesting = lift . requesting
  requesting_ = lift . requesting_

-- | Given a function like 'runWithReplace' for the underlying monad, implement
-- 'runWithReplace' for 'EventWriterT'.  This is necessary when the underlying
-- monad doesn't have a 'Adjustable' instance or to override the default
-- 'Adjustable' behavior.
runWithReplaceEventWriterTWith :: forall m w a b. (MonadHold m, Semigroup w)
                               => (forall a' b'. m a' -> Event (m b') -> EventWriterT w m (a', Event b'))
                               -> EventWriterT w m a
                               -> Event (EventWriterT w m b)
                               -> EventWriterT w m (a, Event b)
runWithReplaceEventWriterTWith f a0 a' = do
  (result0, result') <- f (runEventWriterT a0) $ fmapCheap runEventWriterT a'
  tellEvent =<< switchHoldPromptOnly (snd result0) (fmapCheap snd result')
  return (fst result0, fmapCheap fst result')

-- | Like 'runWithReplaceEventWriterTWith', but for 'sequenceIntMapWithAdjust'.
sequenceIntMapWithAdjustEventWriterTWith
  :: forall m p w v v'
  .  ( MonadHold m
     , Semigroup w
     , Functor p
     , Patch (p (Event w))
     , PatchTarget (p (Event w)) ~ IntMap (Event w)
     , Patch (p w)
     , PatchTarget (p w) ~ IntMap w
     )
  => (   (IntMap.Key -> v -> m (Event w, v'))
      -> IntMap v
      -> Event (p v)
      -> EventWriterT w m (IntMap (Event w, v'), Event (p (Event w, v')))
     )
  -> (Incremental (p (Event w)) -> Event (PatchTarget (p w)))
  -> (Event (p (Event w)) -> Event (p w))
  -> (IntMap.Key -> v -> EventWriterT w m v')
  -> IntMap v
  -> Event (p v)
  -> EventWriterT w m (IntMap v', Event (p v'))
sequenceIntMapWithAdjustEventWriterTWith base mergePatchIncremental coincidencePatch f dm0 dm' = do
  let f' :: IntMap.Key -> v -> m (Event w, v')
      f' k v = swap <$> runEventWriterT (f k v)
  (children0, children') <- base f' dm0 dm'
  let result0 = fmap snd children0
      result' = fmapCheap (fmap snd) children'
      requests0 :: IntMap (Event w)
      requests0 = fmap fst children0
      requests' :: Event (p (Event w))
      requests' = fmapCheap (fmap fst) children'
  e <- switchHoldPromptOnlyIncremental mergePatchIncremental coincidencePatch requests0 requests'
  tellEvent $ fforMaybeCheap e $ \m ->
    case IntMap.elems m of
      [] -> Nothing
      h : t -> Just $ sconcat $ h :| t
  return (result0, result')

-- | Like 'runWithReplaceEventWriterTWith', but for 'sequenceDMapWithAdjust'.
sequenceDMapWithAdjustEventWriterTWith
  :: forall m p p' w k v v'
  .  ( MonadHold m
     , Semigroup w
     , Patch (p' (Some k) (Event w))
     , PatchTarget (p' (Some k) (Event w)) ~ Map (Some k) (Event w)
     , GCompare k
     , Patch (p' (Some k) w)
     , PatchTarget (p' (Some k) w) ~ Map (Some k) w
     )
  => (   (forall a. k a -> v a -> m (Compose ((,) (Event w)) v' a))
      -> DMap k v
      -> Event (p k v)
      -> EventWriterT w m (DMap k (Compose ((,) (Event w)) v'), Event (p k (Compose ((,) (Event w)) v')))
     )
  -> ((forall a. Compose ((,) (Event w)) v' a -> v' a) -> p k (Compose ((,) (Event w)) v') -> p k v')
  -> ((forall a. Compose ((,) (Event w)) v' a -> Event w) -> p k (Compose ((,) (Event w)) v') -> p' (Some k) (Event w))
  -> (Incremental (p' (Some k) (Event w)) -> Event (PatchTarget (p' (Some k) w)))
  -> (Event (p' (Some k) (Event w)) -> Event (p' (Some k) w))
  -> (forall a. k a -> v a -> EventWriterT w m (v' a))
  -> DMap k v
  -> Event (p k v)
  -> EventWriterT w m (DMap k v', Event (p k v'))
sequenceDMapWithAdjustEventWriterTWith base mapPatch weakenPatchWith mergePatchIncremental coincidencePatch f dm0 dm' = do
  let f' :: forall a. k a -> v a -> m (Compose ((,) (Event w)) v' a)
      f' k v = Compose . swap <$> runEventWriterT (f k v)
  (children0, children') <- base f' dm0 dm'
  let result0 = DMap.map (snd . getCompose) children0
      result' = fforCheap children' $ mapPatch $ snd . getCompose
      requests0 :: Map (Some k) (Event w)
      requests0 = weakenDMapWith (fst . getCompose) children0
      requests' :: Event (p' (Some k) (Event w))
      requests' = fforCheap children' $ weakenPatchWith $ fst . getCompose
  e <- switchHoldPromptOnlyIncremental mergePatchIncremental coincidencePatch requests0 requests'
  tellEvent $ fforMaybeCheap e $ \m ->
    case Map.elems m of
      [] -> Nothing
      h : t -> Just $ sconcat $ h :| t
  return (result0, result')

instance PerformEvent m => PerformEvent (EventWriterT w m) where
  type Performable (EventWriterT w m) = Performable m
  performEvent_ = lift . performEvent_
  performEvent = lift . performEvent

instance PostBuild m => PostBuild (EventWriterT w m) where
  getPostBuild = lift getPostBuild

instance TriggerEvent m => TriggerEvent (EventWriterT w m) where
  newTriggerEvent = lift newTriggerEvent
  newTriggerEventWithOnComplete = lift newTriggerEventWithOnComplete
  newEventWithLazyTriggerWithOnComplete = lift . newEventWithLazyTriggerWithOnComplete

instance MonadReader r m => MonadReader r (EventWriterT w m) where
  ask = lift ask
  local f (EventWriterT a) = EventWriterT $ mapStateT (local f) a
  reader = lift . reader

instance MonadRef m => MonadRef (EventWriterT w m) where
  type Ref (EventWriterT w m) = Ref m
  newRef = lift . newRef
  readRef = lift . readRef
  writeRef r = lift . writeRef r

instance MonadAtomicRef m => MonadAtomicRef (EventWriterT w m) where
  atomicModifyRef r = lift . atomicModifyRef r

instance MonadReflexCreateTrigger m => MonadReflexCreateTrigger (EventWriterT w m) where
  newEventWithTrigger = lift . newEventWithTrigger
  newFanEventWithTrigger f = lift $ newFanEventWithTrigger f

instance (MonadQuery t q m, Monad m) => MonadQuery t q (EventWriterT w m) where
  tellQueryIncremental = lift . tellQueryIncremental
  askQueryResult = lift askQueryResult
  queryIncremental = lift . queryIncremental

instance MonadDynamicWriter w m => MonadDynamicWriter w (EventWriterT v m) where
  tellDyn = lift . tellDyn

instance PrimMonad m => PrimMonad (EventWriterT w m) where
  type PrimState (EventWriterT w m) = PrimState m
  primitive = lift . primitive

-- | Map a function over the output of a 'EventWriterT'.
withEventWriterT :: (Semigroup w, Semigroup w', MonadHold m)
                 => (w -> w')
                 -> EventWriterT w m a
                 -> EventWriterT w' m a
withEventWriterT f ew = do
  (r, e) <- lift $ do
    (r, e) <- runEventWriterT ew
    let e' = fmap f e
    return (r, e')
  tellEvent e
  return r

-- | Change the monad underlying an EventWriterT
mapEventWriterT
  :: (forall x. m x -> n x)
  -> EventWriterT w m a
  -> EventWriterT w n a
mapEventWriterT f (EventWriterT a) = EventWriterT $ mapStateT f a
