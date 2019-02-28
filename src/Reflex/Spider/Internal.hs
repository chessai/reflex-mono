{-# language BangPatterns #-}
{-# language CPP #-}
{-# language EmptyDataDecls #-}
{-# language ExistentialQuantification #-}
{-# language GeneralizedNewtypeDeriving #-}
{-# language InstanceSigs #-}
{-# language LambdaCase #-}
{-# language RankNTypes #-}
{-# language RoleAnnotations #-}
{-# language ScopedTypeVariables #-}
{-# language TypeFamilies #-}
{-# language UndecidableInstances #-}
{-# language RecursiveDo #-}
{-# language MagicHash #-}

-- | This module is the implementation of the 'Spider' 'Reflex' engine.  It uses
-- a graph traversal algorithm to propagate 'Event's and 'Behavior's.
module Reflex.Spider.Internal
  ( -- * Primitives
    -- ** Primitive types
    Behavior(..)
  , Event(..) 
  , Dynamic(..)
  , Incremental(..)
  , PullM(..)
  , PushM(..)
  , EventM(..)

    -- ** Primitive functions
  , never
  , constant
  , push
  , pushCheap
  , pull
  , merge
  , fan
  , switch
  , coincidence
  , current
  , updated
  , unsafeBuildDynamic
  , unsafeBuildIncremental
  , mergeIncremental
  , mergeIncrementalWithMove
  , currentIncremental
  , updatedIncremental
  , incrementalToDynamic
  , mergeIntIncremental
  , fanInt
  , mergeInt
    -- ** Primitive coercions 
  , behaviorCoercion
  , eventCoercion
  , dynamicCoercion
  , coerceBehavior
  , coerceEvent
  , coerceDynamic

    -- * Fan-related types
  , EventSelector(..)
  , EventSelectorInt(..)

    -- * Convenience functions
  , constDyn
  , pushAlways
    -- ** Combining 'Event's
  , leftmost
  , mergeMap
  , mergeIntMap
  , mergeMapIncremental
  , mergeMapIncrementalWithMove
  , mergeIntMapIncremental
  , coincidencePatchMap
  , coincidencePatchMapWithMove
  , coincidencePatchIntMap
  , mergeList
  , mergeWith
  , difference
  , alignEventWithMaybe

    -- ** Breaking up 'Event's
  , splitE
  , splitF
  , fanEither
  , fanThese
  , fanMap
  , dmapToThese
  , EitherTag(..)
  , eitherToDSum
  , dsumToEither
  , factorEvent
  , filterEventKey

    -- ** Collapsing 'Event's of 'Event's
  , switchHold
  , switchHoldPromptly
  , switchHoldPromptOnly
  , switchHoldPromptOnlyIncremental

    -- ** Using 'Event's to sample 'Behavior's
  , tag
  , tagMaybe
  , attach
  , attachWithMaybe

    -- ** Blocking an 'Event' based on a 'Behavior'
  , gate

    -- ** Combining 'Dynamic's
  , distributeDMapOverDynPure
  , distributeListOverDyn
  , distributeListOverDynWith
  , zipDyn
  , zipDynWith
  
    -- * Accumulating state
  , Accumulator(..)
  , accumDyn
  , accumMDyn
  , accumMaybeDyn
  , accumMaybeMDyn
  , mapAccumDyn
  , mapAccumMDyn
  , mapAccumMaybeDyn
  , mapAccumMaybeMDyn
  , accumB
  , accumMB
  , accumMaybeB
  , accumMaybeMB
  , mapAccumB
  , mapAccumMB
  , mapAccumMaybeB
  , mapAccumMaybeMB
  , mapAccum_
  , mapAccumM_
  , mapAccumMaybe_
  , mapAccumMaybeM_
--  , accumIncremental
--  , accumMIncremental
--  , accumMaybeMIncremental
--  , mapAccumIncremental
--  , mapAccumMIncremental
--  , mapAccumMaybeIncremental
--  , mapAccumMaybeMIncremental

  , zipListWithEvent
  , numberOccurrences
  , numberOccurrencesFrom
  , numberOccurrencesFrom_
  , (<@>)
  , (<@)
  , tailE
  , headTailE
  , takeWhileE
  , takeWhileJustE
  , dropWhileE
  , takeDropWhileJustE
  , switcher
    
    -- * Debugging functions
  , traceEvent
  , traceEventWith

    -- * Unsafe functions
  , unsafeDynamic
-- , unsafeMapIncremental

    -- * FunctorMaybe
  , FunctorMaybe(..)

    -- * 'UniqDynamic'
  , UniqDynamic(..)
  , alreadyUniqDynamic

    -- * Spider
  , SpiderHost(..)
  , SpiderHostFrame(..)
  , MonadSubscribeEvent(..)
  , MonadReflexCreateTrigger(..)
  , MonadReflexHost(..)
  , fireEvents
  , newEventWithTriggerRef
  , fireEventRef
  , fireEventRefAndRead

  , SpiderTimelineEnv(..)
  , newSpiderTimeline
  , runSpiderHost
  , runSpiderHostForTimeline
  ) where

import Control.Applicative (liftA2)
import Control.Concurrent (MVar,withMVar,newMVar)
import Control.Exception (evaluate)
import Control.Monad (when,ap,unless,void,(<=<),guard,forM_)
import Control.Monad.Exception (MonadException(..),MonadAsyncException(..))
import Control.Monad.Fix (MonadFix)
import Control.Monad.IO.Class (MonadIO(liftIO))
import Control.Monad.Identity (Identity(..))
import Control.Monad.Primitive (touch)
import Control.Monad.Reader (ReaderT(..),runReaderT,asks,ask)
import Control.Monad.Ref
import Control.Monad.State (StateT)
import Control.Monad.Trans (MonadTrans(lift))
import Control.Monad.Trans.Cont (ContT)
import Control.Monad.Trans.Except (ExceptT)
import Control.Monad.Trans.RWS (RWST)
import Control.Monad.Trans.Writer (WriterT)
import Data.Align (Align(..))
import Data.Bifunctor (bimap,first)
import Data.Coerce (Coercible,coerce)
import Data.Default (Default(def))
import Data.Dependent.Map (DMap, DSum (..))
import Data.FastMutableIntMap (FastMutableIntMap, PatchIntMap (..))
import Data.FastWeakBag (FastWeakBag)
import Data.Foldable (Foldable(foldl'),foldlM,for_,traverse_)
import qualified Data.Foldable
--import Data.Foldable hiding (concat, elem, sequence_)
import Data.Functor (($>))
import Data.Functor.Apply (Apply((<.>)))
import Data.Functor.Bind (Bind((>>-),join))
import Data.Functor.Compose (Compose(..))
import Data.Functor.Constant (Constant(..))
import Data.Functor.Misc (ComposeMaybe(..),dmapToThese,EitherTag(..),Const2(..),dmapToMap,mapWithFunctorToDMap,intMapWithFunctorToDMap,dmapToIntMap,mapToDMap,eitherToDSum,dsumToEither)
import Data.Functor.Plus (Alt(..),Plus(..))
import Data.Functor.Product (Product(..))
import Data.FunctorMaybe (FunctorMaybe(..))
import Data.GADT.Compare (GEq(..),GCompare(..))
import Data.IORef (newIORef,readIORef,writeIORef,modifyIORef',modifyIORef)
import Data.IntMap.Strict (IntMap)
import Data.List.NonEmpty (NonEmpty(..))
import Data.Map (Map)
import Data.Maybe (isJust,maybeToList,catMaybes,mapMaybe,fromMaybe)
import Data.Proxy (Proxy(Proxy))
import Data.Reflection (reify)
import Data.Semigroup (Semigroup(..))
import Data.Some (Some)
import Data.These (These(..),mergeThese)
import Data.Traversable (forM)
import Data.Type.Coercion (Coercion(..),coerceWith)
import Data.Type.Equality ((:~:)(..))
import Data.WeakBag (WeakBag, WeakBagTicket, _weakBag_children)
import Debug.Trace (trace)
import GHC.Exts (Any,reallyUnsafePtrEquality#)
import GHC.IORef (IORef (..))
import GHC.Stack (whoCreated)
import Reflex.FastWeak (FastWeak,emptyFastWeak,getFastWeakTicket,mkFastWeakTicket,getFastWeakTicketWeak,getFastWeakTicketValue)
import Reflex.Patch (Patch(..),PatchDMap(..),PatchDMapWithMove,unPatchDMapWithMove,applyAlways,PatchMap(..),const2PatchDMapWith,const2IntPatchDMapWith,PatchMapWithMove,const2PatchDMapWithMoveWith)
import System.IO.Unsafe (unsafePerformIO,unsafeInterleaveIO)
import System.Mem.Weak (Weak,mkWeakPtr,finalize,deRefWeak)
import Unsafe.Coerce (unsafeCoerce)
import qualified Control.Monad.Trans.State.Strict as StrictStateT
import qualified Control.Monad
import qualified Data.Dependent.Map as DMap
import qualified Data.FastMutableIntMap as FastMutableIntMap
import qualified Data.FastWeakBag as FastWeakBag
import qualified Data.IntMap.Strict as IntMap
import qualified Data.Some as Some
import qualified Data.WeakBag as WeakBag
import qualified Reflex.Patch.DMapWithMove as PatchDMapWithMove
import qualified Reflex.Patch.MapWithMove as PatchMapWithMove

#ifdef DEBUG_CYCLES
import Control.Monad.State hiding (forM, forM_, mapM, mapM_, sequence)
import Data.List.NonEmpty (NonEmpty (..), nonEmpty)
import qualified Data.List.NonEmpty as NonEmpty
import Data.Monoid (mempty)
import Data.Tree (Forest, Tree (..), drawForest)
#endif

#ifdef DEBUG_TRACE_EVENTS
import qualified Data.ByteString.Char8 as BS8
import System.IO (stderr)
#endif

#ifdef DEBUG_TRACE_EVENTS
withStackOneLine :: (BS8.ByteString -> a) -> a
withStackOneLine expr = unsafePerformIO $ do
  stack <- currentCallStack
  return (expr (BS8.pack (unwords (reverse stack))))
#endif

debugPropagate,debugInvalidateHeight,debugInvalidate :: Bool

#ifdef DEBUG

#define DEBUG_NODEIDS
debugPropagate = True
debugInvalidateHeight = False
debugInvalidate = True

class HasNodeId a where getNodeId :: a -> Int
instance HasNodeId (Hold p a) where getNodeId = holdNodeId
instance HasNodeId (PushSubscribed a b) where getNodeId = pushSubscribedNodeId
instance HasNodeId (SwitchSubscribed a) where getNodeId = switchSubscribedNodeId
instance HasNodeId (FanSubscribed a) where getNodeId = fanSubscribedNodeId
instance HasNodeId (CoincidenceSubscribed a) where getNodeId = coincidenceSubscribedNodeId
instance HasNodeId (RootSubscribed a) where getNodeId = rootSubscribedNodeId
instance HasNodeId (Pull a) where getNodeId = pullNodeId

{-# inline showNodeId #-}
showNodeId :: HasNodeId a => a -> String
showNodeId = ("#"<>) . show . getNodeId

showSubscriberType :: Subscriber a -> String
showSubscriberType = \case
  SubscriberPush _ _ -> "SubscriberPush"
  SubscriberMerge _ _ -> "SubscriberMerge"
  SubscriberFan _ -> "SubscriberFan"
  SubscriberMergeChange _ -> "SubscriberMergeChange"
  SubscriberHold _ -> "SubscriberHold"
  SubscriberHoldIdentity _ -> "SubscriberHoldIdentity"
  SubscriberSwitch _ -> "SubscriberSwitch"
  SubscriberCoincidenceOuter _ -> "SubscriberCoincidenceOuter"
  SubscriberCoincidenceInner _ -> "SubscriberCoincidenceInner"
  SubscriberHandle -> "SubscriberHandle"

showEventType :: Event a -> String
showEventType = \case
  EventRoot _ _ -> "EventRoot"
  EventNever -> "EventNever"
  EventPush _ -> "EventPush"
  EventMerge _ -> "EventMerge"
  EventFan _ _ -> "EventFan"
  EventSwitch _ -> "EventSwitch"
  EventCoincidence _ -> "EventCoincidence"
  EventHold _ -> "EventHold"
  EventDyn _ -> "EventDyn"
  EventHoldIdentity _ -> "EventHoldIdentity"
  EventDynIdentity _ -> "EventDynIdentity"

#else

debugPropagate = False
debugInvalidateHeight = False
debugInvalidate = False

-- This must be inline, or error messages will cause memory leaks due to retaining the node in question
{-# inline showNodeId #-}
showNodeId :: a -> String
showNodeId _ = ""

#endif

#ifdef DEBUG_NODEIDS
{-# noinline nextNodeIdRef #-}
nextNodeIdRef :: IORef Int
nextNodeIdRef = unsafePerformIO $ newIORef 1

newNodeId :: IO Int
newNodeId = atomicModifyIORef' nextNodeIdRef $ \n -> (succ n, n)

{-# noinline unsafeNodeId #-}
unsafeNodeId :: a -> Int
unsafeNodeId a = unsafePerformIO $ do
  touch a
  newNodeId
#endif

--------------------------------------------------------------------------------
-- EventSubscription
--------------------------------------------------------------------------------

--NB: Once you subscribe to an Event, you must always hold on the the WHOLE EventSubscription you get back
-- If you do not retain the subscription, you may be prematurely unsubscribed from the parent event.
data EventSubscription = EventSubscription
  { _eventSubscription_unsubscribe :: !(IO ())
  , _eventSubscription_subscribed :: {-# UNPACK #-} !EventSubscribed
  }

unsubscribe :: EventSubscription -> IO ()
unsubscribe (EventSubscription u _) = u

--------------------------------------------------------------------------------
-- Event
--------------------------------------------------------------------------------

newtype Event a = Event { unEvent :: Subscriber a -> EventM (EventSubscription, Maybe a) }

instance Functor Event where
  fmap f = fmapMaybe $ Just . f
  x <$ e = fmapCheap (const x) e

instance Alt Event where
  ev1 <!> ev2 = leftmost [ev1,ev2]

instance Apply Event where
  evf <.> evx = coincidence (fmap (<$> evx) evf)

instance Bind Event where
  evx >>- f = coincidence (f <$> evx)
  join = coincidence

instance FunctorMaybe Event where
  fmapMaybe f = push $ pure . f

instance Plus Event where
  zero = never

instance Semigroup a => Semigroup (Event a) where
  (<>) = alignWith (mergeThese (<>))
  sconcat = fmap sconcat . mergeList . Data.Foldable.toList
  stimes n = fmap $ stimes n

instance Semigroup a => Monoid (Event a) where
  mempty = never
  mappend = (<>)
  mconcat = fmap sconcat . mergeList
 
-- EventM can do everything BehaviorM can, plus create holds
newtype EventM a = EventM { unEventM :: IO a } deriving (Functor, Applicative, Monad, MonadIO, MonadFix, MonadException, MonadAsyncException) -- The environment should be Nothing if we are not in a frame, and Just if we are - in which case it is a list of assignments to be done after the frame is over

data EventSubscribed = EventSubscribed
  { eventSubscribedHeightRef :: {-# UNPACK #-} !(IORef Height)
  , eventSubscribedRetained :: {-# NOUNPACK #-} !Any
#ifdef DEBUG_CYCLES
  , eventSubscribedGetParents :: !(IO [Some EventSubscribed]) -- For debugging loops
  , eventSubscribedHasOwnHeightRef :: !Bool
  , eventSubscribedWhoCreated :: !(IO [String])
#endif
  }

data Subscriber a = Subscriber
  { subscriberPropagate :: !(a -> EventM ())
  , subscriberInvalidateHeight :: !(Height -> IO ())
  , subscriberRecalculateHeight :: !(Height -> IO ())
  }

newtype Height = Height { unHeight :: Int } deriving (Show, Read, Eq, Ord, Bounded)

push' :: (a -> EventM (Maybe b)) -> Event a -> Event b
push' f e = cacheEvent (pushCheap' f e)

{-# inline subscribeAndRead #-}
subscribeAndRead :: Event a -> Subscriber a -> EventM (EventSubscription, Maybe a)
subscribeAndRead = unEvent

{-# inline [1] pushCheap' #-}
-- | Construct an 'Event' equivalent to that constructed by 'push', but with no
-- caching; if the computation function is very cheap, this is (much) more
-- efficient than 'push'
pushCheap' :: (a -> EventM (Maybe b)) -> Event a -> Event b
pushCheap' f e = Event $ \sub -> do
  (subscription, occ) <- subscribeAndRead e $ sub
    { subscriberPropagate = \a -> f a >>= mapM_ (subscriberPropagate sub) }
  occ' <- Control.Monad.join <$> mapM f occ
  pure (subscription, occ')

{-
{-# inline terminalSubscriber #-}
-- | A subscriber that never triggers other 'Event's
terminalSubscriber :: (a -> EventM ()) -> Subscriber a
terminalSubscriber p = Subscriber
  { subscriberPropagate = p
  , subscriberInvalidateHeight = const (pure ())
  , subscriberRecalculateHeight = const (pure ())
  }


{-# inline subscribeAndReadHead #-}
-- | Subscribe to an 'Event' only for the duration of one occurence
subscribeAndReadHead :: Event a -> Subscriber a -> EventM (EventSubscription, Maybe a)
subscribeAndReadHead e sub = do
  subscriptionRef <- liftIO $ newIORef $ error "subscribeAndReadHead: not initialised"
  (subscription, occ) <- subscribeAndRead e $ sub
    { subscriberPropagate = \a -> do
        liftIO $ unsubscribe =<< readIORef subscriptionRef
        subscriberPropagate sub a
    }
  liftIO $ case occ of
    Nothing -> writeIORef subscriptionRef $! subscription
    Just _ -> unsubscribe subscription
  pure (subscription, occ)

--TODO: Make this lazy in its input event
headE' :: (MonadIO m) => Defer SomeMergeInit m -> Event a -> m (Event a)
headE' d originalE = do
  parent <- liftIO $ newIORef $ Just originalE
  defer d $ SomeMergeInit $ do --TODO: Rename SomeMergeInit appropriately
    let clearParent = liftIO $ writeIORef parent Nothing
    (_, occ) <- subscribeAndReadHead originalE $ terminalSubscriber $ \_ -> clearParent
    when (isJust occ) clearParent
  return $ Event $ \sub -> do
    liftIO (readIORef parent) >>= \case
      Nothing -> return (EventSubscription (return ()) $ EventSubscribed zeroRef $ toAny (), Nothing)
      Just e -> subscribeAndReadHead e sub
-}

{-# RULES
"cacheEvent/cacheEvent" forall e. cacheEvent (cacheEvent e) = cacheEvent e
"cacheEvent/pushCheap'" forall f e. pushCheap' f (cacheEvent e) = cacheEvent (pushCheap' f e)
"hold/cacheEvent" forall f e. hold f (cacheEvent e) = hold f e
   #-}

data CacheSubscribed a
   = CacheSubscribed { _cacheSubscribed_subscribers :: {-# UNPACK #-} !(FastWeakBag (Subscriber a))
                     , _cacheSubscribed_parent :: {-# UNPACK #-} !EventSubscription
                     , _cacheSubscribed_occurrence :: {-# UNPACK #-} !(IORef (Maybe a))
                     }

-- | Construct an 'Event' whose value is guaranteed not to be recomputed
-- repeatedly
--
--TODO: Try a caching strategy where we subscribe directly to the parent when
--there's only one subscriber, and then build our own FastWeakBag only when a second
--subscriber joins
{-# noinline [0] cacheEvent #-}
cacheEvent :: forall a. Event a -> Event a
cacheEvent e =
#ifdef DEBUG_TRACE_EVENTS
  withStackOneLine $ \callSite -> Event $
#else
  Event $
#endif
    let mSubscribedRef :: IORef (FastWeak (CacheSubscribed a))
        !mSubscribedRef = unsafeNewIORef e emptyFastWeak
    in \sub -> {-# SCC "cacheEvent" #-} do
#ifdef DEBUG_TRACE_EVENTS
          unless (BS8.null callSite) $ liftIO $ BS8.hPutStrLn stderr callSite
#endif
          subscribedTicket <- liftIO (readIORef mSubscribedRef >>= getFastWeakTicket) >>= \case
            Just subscribedTicket -> return subscribedTicket
            Nothing -> do
              subscribers <- liftIO FastWeakBag.empty
              occRef <- liftIO $ newIORef Nothing -- This should never be read prior to being set below
              (parentSub, occ) <- subscribeAndRead e $ Subscriber
                { subscriberPropagate = \a -> do
                    liftIO $ writeIORef occRef $ Just a
                    scheduleClear occRef
                    propagateFast a subscribers
                , subscriberInvalidateHeight = \old -> do
                    FastWeakBag.traverse subscribers $ invalidateSubscriberHeight old
                , subscriberRecalculateHeight = \new -> do
                    FastWeakBag.traverse subscribers $ recalculateSubscriberHeight new
                }
              when (isJust occ) $ do
                liftIO $ writeIORef occRef occ -- Set the initial value of occRef; we don't need to do this if occ is Nothing
                scheduleClear occRef
              let !subscribed = CacheSubscribed
                    { _cacheSubscribed_subscribers = subscribers
                    , _cacheSubscribed_parent = parentSub
                    , _cacheSubscribed_occurrence = occRef
                    }
              subscribedTicket <- liftIO $ mkFastWeakTicket subscribed
              liftIO $ writeIORef mSubscribedRef =<< getFastWeakTicketWeak subscribedTicket
              return subscribedTicket
          liftIO $ do
            subscribed <- getFastWeakTicketValue subscribedTicket
            ticket <- FastWeakBag.insert sub $ _cacheSubscribed_subscribers subscribed
            occ <- readIORef $ _cacheSubscribed_occurrence subscribed
            let es = EventSubscription
                  { _eventSubscription_unsubscribe = do
                      FastWeakBag.remove ticket
                      isEmpty <- FastWeakBag.isEmpty $ _cacheSubscribed_subscribers subscribed
                      when isEmpty $ do
                        writeIORef mSubscribedRef emptyFastWeak
                        unsubscribe $ _cacheSubscribed_parent subscribed
                      touch ticket
                      touch subscribedTicket
                  , _eventSubscription_subscribed = EventSubscribed
                      { eventSubscribedHeightRef = eventSubscribedHeightRef $ _eventSubscription_subscribed $ _cacheSubscribed_parent subscribed
                      , eventSubscribedRetained = toAny subscribedTicket
                      }
                  }
            return (es, occ)

subscribe :: Event a -> Subscriber a -> EventM EventSubscription
subscribe e s = fst <$> subscribeAndRead e s

{-# inline wrap #-}
wrap :: MonadIO m => (t -> EventSubscribed) -> (Subscriber a -> m (WeakBagTicket, t, Maybe a)) -> Subscriber a -> m (EventSubscription, Maybe a)
wrap tag' getSpecificSubscribed sub = do
  (sln, subd, occ) <- getSpecificSubscribed sub
  let es = tag' subd
  return (EventSubscription (WeakBag.remove sln >> touch sln) es, occ)

eventRoot :: GCompare k => k a -> Root k -> Event a
eventRoot !k !r = Event $ wrap eventSubscribedRoot $ liftIO . getRootSubscribed k r

eventFan :: (GCompare k) => k a -> Fan k -> Event a
eventFan !k !f = Event $ wrap eventSubscribedFan $ getFanSubscribed k f

eventSwitch :: Switch a -> Event a
eventSwitch !s = Event $ wrap eventSubscribedSwitch $ getSwitchSubscribed s

eventCoincidence :: Coincidence a -> Event a
eventCoincidence !c = Event $ wrap eventSubscribedCoincidence $ getCoincidenceSubscribed c

eventHold :: Hold p -> Event p
eventHold !h = Event $ subscribeHoldEvent h

eventDyn :: (Patch p) => Dyn p -> Event p
eventDyn !j = Event $ \sub -> getDynHoldE j >>= \h -> subscribeHoldEvent h sub

{-# inline subscribeCoincidenceInner #-}
subscribeCoincidenceInner :: Event a -> Height -> CoincidenceSubscribed a -> EventM (Maybe a, Height, EventSubscribed)
subscribeCoincidenceInner inner outerHeight subscribedUnsafe = do
  subInner <- liftIO $ newSubscriberCoincidenceInner subscribedUnsafe
  (subscription@(EventSubscription _ innerSubd), innerOcc) <- subscribeAndRead inner subInner
  innerHeight <- liftIO $ getEventSubscribedHeight innerSubd
  let height = max innerHeight outerHeight
  defer deferSomeResetCoincidenceEventM $ SomeResetCoincidence subscription $ if height > outerHeight then Just subscribedUnsafe else Nothing
  return (innerOcc, height, innerSubd)

--------------------------------------------------------------------------------
-- Subscriber
--------------------------------------------------------------------------------

--TODO: Move this comment to WeakBag
-- These function are constructor functions that are marked noinline so they are
-- opaque to GHC. If we do not do this, then GHC will sometimes fuse the constructor away
-- so any weak references that are attached to the constructors will have their
-- finalizer run. Using the opaque constructor, does not see the
-- constructor application, so it behaves like an IORef and cannot be fused away.
--
-- The result is also evaluated to WHNF, since forcing a thunk invalidates
-- the weak pointer to it in some cases.

newSubscriberHold :: (Patch p) => Hold p -> IO (Subscriber p)
newSubscriberHold h = return $ Subscriber
  { subscriberPropagate = {-# SCC "traverseHold" #-} propagateSubscriberHold h
  , subscriberInvalidateHeight = \_ -> return ()
  , subscriberRecalculateHeight = \_ -> return ()
  }

newSubscriberFan :: forall k. (GCompare k) => FanSubscribed k -> IO (Subscriber (DMap k Identity))
newSubscriberFan subscribed = return $ Subscriber
  { subscriberPropagate = \a -> {-# SCC "traverseFan" #-} do
      subs <- liftIO $ readIORef $ fanSubscribedSubscribers subscribed
      tracePropagate (Proxy :: Proxy x) $ "SubscriberFan" <> showNodeId subscribed <> ": " ++ show (DMap.size subs) ++ " keys subscribed, " ++ show (DMap.size a) ++ " keys firing"
      liftIO $ writeIORef (fanSubscribedOccurrence subscribed) $ Just a
      scheduleClear $ fanSubscribedOccurrence subscribed
      let f _ (Pair (Identity v) subsubs) = do
            propagate v $ _fanSubscribedChildren_list subsubs
            return $ Constant ()
      _ <- DMap.traverseWithKey f $ DMap.intersectionWithKey (\_ -> Pair) a subs --TODO: Would be nice to have DMap.traverse_
      return ()
  , subscriberInvalidateHeight = \old -> do
      when debugInvalidateHeight $ putStrLn $ "invalidateSubscriberHeight: SubscriberFan" <> showNodeId subscribed
      subscribers <- readIORef $ fanSubscribedSubscribers subscribed
      forM_ (DMap.toList subscribers) $ \(_ :=> v) -> WeakBag.traverse (_fanSubscribedChildren_list v) $ invalidateSubscriberHeight old
      when debugInvalidateHeight $ putStrLn $ "invalidateSubscriberHeight: SubscriberFan" <> showNodeId subscribed <> " done"
  , subscriberRecalculateHeight = \new -> do
      when debugInvalidateHeight $ putStrLn $ "recalculateSubscriberHeight: SubscriberFan" <> showNodeId subscribed
      subscribers <- readIORef $ fanSubscribedSubscribers subscribed
      forM_ (DMap.toList subscribers) $ \(_ :=> v) -> WeakBag.traverse (_fanSubscribedChildren_list v) $ recalculateSubscriberHeight new
      when debugInvalidateHeight $ putStrLn $ "recalculateSubscriberHeight: SubscriberFan" <> showNodeId subscribed <> " done"
  }

newSubscriberSwitch :: forall a. SwitchSubscribed a -> IO (Subscriber a)
newSubscriberSwitch subscribed = return $ Subscriber
  { subscriberPropagate = \a -> {-# SCC "traverseSwitch" #-} do
      tracePropagate (Proxy :: Proxy x) $ "SubscriberSwitch" <> showNodeId subscribed
      liftIO $ writeIORef (switchSubscribedOccurrence subscribed) $ Just a
      scheduleClear $ switchSubscribedOccurrence subscribed
      propagate a $ switchSubscribedSubscribers subscribed
  , subscriberInvalidateHeight = \_ -> do
      when debugInvalidateHeight $ putStrLn $ "invalidateSubscriberHeight: SubscriberSwitch" <> showNodeId subscribed
      oldHeight <- readIORef $ switchSubscribedHeight subscribed
      when (oldHeight /= invalidHeight) $ do
        writeIORef (switchSubscribedHeight subscribed) $! invalidHeight
        WeakBag.traverse (switchSubscribedSubscribers subscribed) $ invalidateSubscriberHeight oldHeight
      when debugInvalidateHeight $ putStrLn $ "invalidateSubscriberHeight: SubscriberSwitch" <> showNodeId subscribed <> " done"
  , subscriberRecalculateHeight = \new -> do
      when debugInvalidateHeight $ putStrLn $ "recalculateSubscriberHeight: SubscriberSwitch" <> showNodeId subscribed
      updateSwitchHeight new subscribed
      when debugInvalidateHeight $ putStrLn $ "recalculateSubscriberHeight: SubscriberSwitch" <> showNodeId subscribed <> " done"
  }

newSubscriberCoincidenceOuter :: forall b. CoincidenceSubscribed b -> IO (Subscriber (Event b))
newSubscriberCoincidenceOuter subscribed = return $ Subscriber
  { subscriberPropagate = \a -> {-# SCC "traverseCoincidenceOuter" #-} do
      tracePropagate (Proxy :: Proxy x) $ "SubscriberCoincidenceOuter" <> showNodeId subscribed
      outerHeight <- liftIO $ readIORef $ coincidenceSubscribedHeight subscribed
      tracePropagate (Proxy :: Proxy x) $ "  outerHeight = " <> show outerHeight
      (occ, innerHeight, innerSubd) <- subscribeCoincidenceInner a outerHeight subscribed
      tracePropagate (Proxy :: Proxy x) $ "  isJust occ = " <> show (isJust occ)
      tracePropagate (Proxy :: Proxy x) $ "  innerHeight = " <> show innerHeight
      liftIO $ writeIORef (coincidenceSubscribedInnerParent subscribed) $ Just innerSubd
      scheduleClear $ coincidenceSubscribedInnerParent subscribed
      case occ of
        Nothing -> do
          when (innerHeight > outerHeight) $ liftIO $ do -- If the event fires, it will fire at a later height
            writeIORef (coincidenceSubscribedHeight subscribed) $! innerHeight
            WeakBag.traverse (coincidenceSubscribedSubscribers subscribed) $ invalidateSubscriberHeight outerHeight
            WeakBag.traverse (coincidenceSubscribedSubscribers subscribed) $ recalculateSubscriberHeight innerHeight
        Just o -> do -- Since it's already firing, no need to adjust height
          liftIO $ writeIORef (coincidenceSubscribedOccurrence subscribed) occ
          scheduleClear $ coincidenceSubscribedOccurrence subscribed
          propagate o $ coincidenceSubscribedSubscribers subscribed
  , subscriberInvalidateHeight = \_ -> do
      when debugInvalidateHeight $ putStrLn $ "invalidateSubscriberHeight: SubscriberCoincidenceOuter" <> showNodeId subscribed
      invalidateCoincidenceHeight subscribed
      when debugInvalidateHeight $ putStrLn $ "invalidateSubscriberHeight: SubscriberCoincidenceOuter" <> showNodeId subscribed <> " done"
  , subscriberRecalculateHeight = \_ -> do
      when debugInvalidateHeight $ putStrLn $ "recalculateSubscriberHeight: SubscriberCoincidenceOuter" <> showNodeId subscribed
      recalculateCoincidenceHeight subscribed
      when debugInvalidateHeight $ putStrLn $ "recalculateSubscriberHeight: SubscriberCoincidenceOuter" <> showNodeId subscribed <> " done"
  }

newSubscriberCoincidenceInner :: forall a. CoincidenceSubscribed a -> IO (Subscriber a)
newSubscriberCoincidenceInner subscribed = return $ Subscriber
  { subscriberPropagate = \a -> {-# SCC "traverseCoincidenceInner" #-} do
      tracePropagate (Proxy :: Proxy x) $ "SubscriberCoincidenceInner" <> showNodeId subscribed
      occ <- liftIO $ readIORef $ coincidenceSubscribedOccurrence subscribed
      case occ of
        Just _ -> return () -- SubscriberCoincidenceOuter must have already propagated this event
        Nothing -> do
          liftIO $ writeIORef (coincidenceSubscribedOccurrence subscribed) $ Just a
          scheduleClear $ coincidenceSubscribedOccurrence subscribed
          propagate a $ coincidenceSubscribedSubscribers subscribed
  , subscriberInvalidateHeight = \_ -> do
      when debugInvalidateHeight $ putStrLn $ "invalidateSubscriberHeight: SubscriberCoincidenceInner" <> showNodeId subscribed
      invalidateCoincidenceHeight subscribed
      when debugInvalidateHeight $ putStrLn $ "invalidateSubscriberHeight: SubscriberCoincidenceInner" <> showNodeId subscribed <> " done"
  , subscriberRecalculateHeight = \_ -> do
      when debugInvalidateHeight $ putStrLn $ "recalculateSubscriberHeight: SubscriberCoincidenceInner" <> showNodeId subscribed
      recalculateCoincidenceHeight subscribed
      when debugInvalidateHeight $ putStrLn $ "recalculateSubscriberHeight: SubscriberCoincidenceInner" <> showNodeId subscribed <> " done"
  }

invalidateSubscriberHeight :: Height -> Subscriber a -> IO ()
invalidateSubscriberHeight = flip subscriberInvalidateHeight

recalculateSubscriberHeight :: Height -> Subscriber a -> IO ()
recalculateSubscriberHeight = flip subscriberRecalculateHeight

-- | Propagate everything at the current height
propagate :: a -> WeakBag (Subscriber a) -> EventM ()
propagate a subscribers = withIncreasedDepth $ do
  -- Note: in the following traversal, we do not visit nodes that are added to the list during our traversal; they are new events, which will necessarily have full information already, so there is no need to traverse them
  --TODO: Should we check if nodes already have their values before propagating?  Maybe we're re-doing work
  WeakBag.traverse subscribers $ \s -> subscriberPropagate s a

-- | Propagate everything at the current height
propagateFast :: a -> FastWeakBag (Subscriber a) -> EventM ()
propagateFast a subscribers = withIncreasedDepth $ do
  -- Note: in the following traversal, we do not visit nodes that are added to the list during our traversal; they are new events, which will necessarily have full information already, so there is no need to traverse them
  --TODO: Should we check if nodes already have their values before propagating?  Maybe we're re-doing work
  FastWeakBag.traverse subscribers $ \s -> subscriberPropagate s a

--------------------------------------------------------------------------------
-- EventSubscribed
--------------------------------------------------------------------------------

toAny :: a -> Any
toAny = unsafeCoerce
{-# inline toAny #-}

eventSubscribedRoot :: RootSubscribed a -> EventSubscribed
eventSubscribedRoot !r = EventSubscribed
  { eventSubscribedHeightRef = zeroRef
  , eventSubscribedRetained = toAny r
#ifdef DEBUG_CYCLES
  , eventSubscribedGetParents = return []
  , eventSubscribedHasOwnHeightRef = False
  , eventSubscribedWhoCreated = return ["root"]
#endif
  }

eventSubscribedNever :: EventSubscribed
eventSubscribedNever = EventSubscribed
  { eventSubscribedHeightRef = zeroRef
  , eventSubscribedRetained = toAny ()
#ifdef DEBUG_CYCLES
  , eventSubscribedGetParents = return []
  , eventSubscribedHasOwnHeightRef = False
  , eventSubscribedWhoCreated = return ["never"]
#endif
  }

eventSubscribedFan :: FanSubscribed k -> EventSubscribed
eventSubscribedFan !subscribed = EventSubscribed
  { eventSubscribedHeightRef = eventSubscribedHeightRef $ _eventSubscription_subscribed $ fanSubscribedParent subscribed
  , eventSubscribedRetained = toAny subscribed
#ifdef DEBUG_CYCLES
  , eventSubscribedGetParents = return [Some.This $ _eventSubscription_subscribed $ fanSubscribedParent subscribed]
  , eventSubscribedHasOwnHeightRef = False
  , eventSubscribedWhoCreated = whoCreatedIORef $ fanSubscribedCachedSubscribed subscribed
#endif
  }

eventSubscribedSwitch :: SwitchSubscribed a -> EventSubscribed
eventSubscribedSwitch !subscribed = EventSubscribed
  { eventSubscribedHeightRef = switchSubscribedHeight subscribed
  , eventSubscribedRetained = toAny subscribed
#ifdef DEBUG_CYCLES
  , eventSubscribedGetParents = do
      s <- readIORef $ switchSubscribedCurrentParent subscribed
      return [Some.This $ _eventSubscription_subscribed s]
  , eventSubscribedHasOwnHeightRef = True
  , eventSubscribedWhoCreated = whoCreatedIORef $ switchSubscribedCachedSubscribed subscribed
#endif
  }

eventSubscribedCoincidence :: CoincidenceSubscribed a -> EventSubscribed
eventSubscribedCoincidence !subscribed = EventSubscribed
  { eventSubscribedHeightRef = coincidenceSubscribedHeight subscribed
  , eventSubscribedRetained = toAny subscribed
#ifdef DEBUG_CYCLES
  , eventSubscribedGetParents = do
      innerSubscription <- readIORef $ coincidenceSubscribedInnerParent subscribed
      let outerParent = Some.This $ _eventSubscription_subscribed $ coincidenceSubscribedOuterParent subscribed
          innerParents = maybeToList $ fmap Some.This innerSubscription
      return $ outerParent : innerParents
  , eventSubscribedHasOwnHeightRef = True
  , eventSubscribedWhoCreated = whoCreatedIORef $ coincidenceSubscribedCachedSubscribed subscribed
#endif
  }

getEventSubscribedHeight :: EventSubscribed -> IO Height
getEventSubscribedHeight es = readIORef $ eventSubscribedHeightRef es

#ifdef DEBUG_CYCLES
whoCreatedEventSubscribed :: EventSubscribed -> IO [String]
whoCreatedEventSubscribed = eventSubscribedWhoCreated

walkInvalidHeightParents :: EventSubscribed -> IO [Some (EventSubscribed)]
walkInvalidHeightParents s0 = do
  subscribers <- flip execStateT mempty $ ($ Some.This s0) $ fix $ \loop (Some.This s) -> do
    h <- liftIO $ readIORef $ eventSubscribedHeightRef s
    when (h == invalidHeight) $ do
      when (eventSubscribedHasOwnHeightRef s) $ liftIO $ writeIORef (eventSubscribedHeightRef s) $! invalidHeightBeingTraversed
      modify (Some.This s :)
      mapM_ loop =<< liftIO (eventSubscribedGetParents s)
  forM_ subscribers $ \(Some.This s) -> writeIORef (eventSubscribedHeightRef s) $! invalidHeight
  return subscribers
#endif

{-# inline subscribeHoldEvent #-}
subscribeHoldEvent :: Hold p -> Subscriber p -> EventM (EventSubscription, Maybe p)
subscribeHoldEvent = subscribeAndRead . holdEvent

--------------------------------------------------------------------------------
-- Behavior
--------------------------------------------------------------------------------

newtype Behavior a = Behavior { readBehaviorTracked :: BehaviorM a }

instance Functor Behavior where
  fmap f = pull' . fmap f . readBehaviorTracked

instance Applicative Behavior where
  pure = constant
  f <*> x = pull $ sample f `ap` sample x
  _ *> b = b
  a <* _ = a

instance Apply Behavior where
  (<.>) = (<*>)

instance Bind Behavior where
  (>>-) = (>>=)

instance Monad Behavior where
  return = pure
  a >>= f = pull $ sample a >>= sample . f
  -- N.B.: It is tempting to write (_ >> b = b; however, this would result in
  -- (fail x >> return y) succeeding (returning y), which violates the law that
  -- (a >> b = a >>= const b), since the implementation of (>>=) above actually will fail.
  -- Since we can't examine 'Behavior's other than by using sample, I don't think it's
  -- possible to write (>>) to be more efficient than the (>>=) above.

instance Semigroup a => Semigroup (Behavior a) where
  a <> b = pull $ liftA2 (<>) (sample a) (sample b)
  sconcat = pull . fmap sconcat . mapM sample
  stimes n = fmap $ stimes n

instance Monoid a => Monoid (Behavior a) where
  mempty = constant mempty
  mappend = (<>)
  mconcat = pull . fmap mconcat . mapM sample

behaviorHold :: Hold p -> Behavior (PatchTarget p)
behaviorHold !h = Behavior $ readHoldTracked h

behaviorHoldIdentity :: Hold (Identity a) -> Behavior a
behaviorHoldIdentity = behaviorHold

behaviorConst :: a -> Behavior a
behaviorConst !a = Behavior $ return a

behaviorPull :: Pull a -> Behavior a
behaviorPull !p = Behavior $ do
    val <- liftIO $ readIORef $ pullValue p
    case val of
      Just subscribed -> do
        askParentsRef >>= mapM_ (\r -> liftIO $ modifyIORef' r (SomeBehaviorSubscribed (BehaviorSubscribedPull subscribed) :))
        askInvalidator >>= mapM_ (\wi -> liftIO $ modifyIORef' (pullSubscribedInvalidators subscribed) (wi:))
        liftIO $ touch $ pullSubscribedOwnInvalidator subscribed
        return $ pullSubscribedValue subscribed
      Nothing -> do
        i <- liftIO $ newInvalidatorPull p
        wi <- liftIO $ mkWeakPtrWithDebug i "InvalidatorPull"
        parentsRef <- liftIO $ newIORef []
        holdInits <- askBehaviorHoldInits
        a <- liftIO $ runReaderT (unBehaviorM $ pullCompute p) (Just (wi, parentsRef), holdInits)
        invsRef <- liftIO . newIORef . maybeToList =<< askInvalidator
        parents <- liftIO $ readIORef parentsRef
        let subscribed = PullSubscribed
              { pullSubscribedValue = a
              , pullSubscribedInvalidators = invsRef
              , pullSubscribedOwnInvalidator = i
              , pullSubscribedParents = parents
              }
        liftIO $ writeIORef (pullValue p) $ Just subscribed
        askParentsRef >>= mapM_ (\r -> liftIO $ modifyIORef' r (SomeBehaviorSubscribed (BehaviorSubscribedPull subscribed) :))
        return a

behaviorDyn :: Patch p => Dyn p -> Behavior (PatchTarget p)
behaviorDyn !d = Behavior $ readHoldTracked =<< getDynHoldB d

{-# inline readHoldTracked #-}
readHoldTracked :: Hold p -> BehaviorM (PatchTarget p)
readHoldTracked h = do
  result <- liftIO $ readIORef $ holdValue h
  askInvalidator >>= mapM_ (\wi -> liftIO $ modifyIORef' (holdInvalidators h) (wi:))
  askParentsRef >>= mapM_ (\r -> liftIO $ modifyIORef' r (SomeBehaviorSubscribed (BehaviorSubscribedHold h) :))
  liftIO $ touch h -- Otherwise, if this gets inlined enough, the hold's parent reference may get collected
  return result

{-# inline readBehaviorUntrackedE #-}
readBehaviorUntrackedE :: Behavior a -> EventM a
readBehaviorUntrackedE b = readBehaviorUntracked deferSomeHoldInitEventM b

{-# inline readBehaviorUntrackedB #-}
readBehaviorUntrackedB :: Behavior a -> BehaviorM a
readBehaviorUntrackedB b = readBehaviorUntracked deferSomeHoldInitBehaviorM b

{-# inlinable readBehaviorUntracked #-}
readBehaviorUntracked :: MonadIO m => Defer SomeHoldInit m -> Behavior a -> m a
readBehaviorUntracked d b = do
  holdInits <- unDefer d
  liftIO $ runBehaviorM (readBehaviorTracked b) Nothing holdInits
    --TODO: Specialize readBehaviorTracked to the Nothing and Just cases

--------------------------------------------------------------------------------
-- Dynamic
--------------------------------------------------------------------------------

newtype Dynamic a = Dynamic { unDynamic :: Dynamic' (Identity a) }

data Dynamic' p = Dynamic'
  { dynamicCurrent :: !(Behavior (PatchTarget p))
  , dynamicUpdated :: !(Event p)
  }

dynamicHold' :: Hold p -> Dynamic' p
dynamicHold' !h = Dynamic'
  { dynamicCurrent = behaviorHold h
  , dynamicUpdated = eventHold h
  }

dynamicHoldIdentity' :: Hold (Identity a) -> Dynamic' (Identity a)
dynamicHoldIdentity' = dynamicHold'

dynamicConst' :: PatchTarget p -> Dynamic' p
dynamicConst' !a = Dynamic'
  { dynamicCurrent = behaviorConst a
  , dynamicUpdated = never
  }

dynamicDyn' :: (Patch p) => Dyn p -> Dynamic' p
dynamicDyn' !d = Dynamic'
  { dynamicCurrent = behaviorDyn d
  , dynamicUpdated = eventDyn d
  }

dynamicDynIdentity' :: Dyn (Identity a) -> Dynamic' (Identity a)
dynamicDynIdentity' = dynamicDyn'

--------------------------------------------------------------------------------
-- Combinators
--------------------------------------------------------------------------------

--TODO: Figure out why certain things are not 'representational', then make them
--representational so we can use coerce

--type role Hold representational
data Hold p
   = Hold { holdValue :: !(IORef (PatchTarget p))
          , holdInvalidators :: !(IORef [Weak Invalidator])
          , holdEvent :: Event p -- This must be lazy, or holds cannot be defined before their input Events
          , holdParent :: !(IORef (Maybe EventSubscription)) -- Keeps its parent alive (will be undefined until the hold is initialized) --TODO: Probably shouldn't be an IORef
#ifdef DEBUG_NODEIDS
          , holdNodeId :: Int
#endif
          }

{-# noinline spiderTimeline #-}
spiderTimeline :: SpiderTimelineEnv x
spiderTimeline = unsafePerformIO unsafeNewSpiderTimelineEnv

-- | Stores all global data relevant to a particular Spider timeline; only one
-- value should exist for each type @x@
data SpiderTimelineEnv x = SpiderTimelineEnv
  { _spiderTimeline_lock :: {-# UNPACK #-} !(MVar ())
  , _spiderTimeline_eventEnv :: {-# UNPACK #-} !EventEnv
#ifdef DEBUG
  , _spiderTimeline_depth :: {-# UNPACK #-} !(IORef Int)
#endif
  }

instance Eq (SpiderTimelineEnv x) where
  _ == _ = True -- Since only one exists of each type
  {-# inline (==) #-}

instance GEq SpiderTimelineEnv where
  a `geq` b = if _spiderTimeline_lock a == _spiderTimeline_lock b
              then Just $ unsafeCoerce Refl -- This unsafeCoerce is safe because the same SpiderTimelineEnv can't have two different 'x' arguments
              else Nothing

data EventEnv
   = EventEnv { eventEnvAssignments :: !(IORef [SomeAssignment]) -- Needed for Subscribe
              , eventEnvHoldInits :: !(IORef [SomeHoldInit]) -- Needed for Subscribe
              , eventEnvDynInits :: !(IORef [SomeDynInit])
              , eventEnvMergeUpdates :: !(IORef [SomeMergeUpdate])
              , eventEnvMergeInits :: !(IORef [SomeMergeInit]) -- Needed for Subscribe
              , eventEnvClears :: !(IORef [SomeClear]) -- Needed for Subscribe
              , eventEnvIntClears :: !(IORef [SomeIntClear])
              , eventEnvRootClears :: !(IORef [SomeRootClear])
              , eventEnvCurrentHeight :: !(IORef Height) -- Needed for Subscribe
              , eventEnvResetCoincidences :: !(IORef [SomeResetCoincidence]) -- Needed for Subscribe
              , eventEnvDelayedMerges :: !(IORef (IntMap [EventM ()]))
              }

{-# inline runEventM #-}
runEventM :: EventM a -> IO a
runEventM = unEventM

asksEventEnv :: forall a. (EventEnv -> a) -> EventM a
asksEventEnv f = return $ f $ _spiderTimeline_eventEnv spiderTimeline

newtype Defer a m = Defer { unDefer :: m (IORef [a]) }

{-# inline defer #-}
defer :: MonadIO m => Defer a m -> a -> m ()
defer d a = do
  q <- unDefer d
  liftIO $ modifyIORef' q (a:)

deferSomeAssignmentEventM :: Defer SomeAssignment EventM
deferSomeAssignmentEventM = Defer (asksEventEnv eventEnvAssignments)

deferSomeHoldInitEventM :: Defer SomeHoldInit EventM
deferSomeHoldInitEventM = Defer (asksEventEnv eventEnvHoldInits)

deferSomeDynInitEventM :: Defer SomeDynInit EventM
deferSomeDynInitEventM = Defer (asksEventEnv eventEnvDynInits)

deferSomeHoldInitBehaviorM :: Defer SomeHoldInit BehaviorM
deferSomeHoldInitBehaviorM = Defer (BehaviorM $ asks snd)

deferSomeMergeUpdateEventM :: Defer SomeMergeUpdate EventM
deferSomeMergeUpdateEventM = Defer (asksEventEnv eventEnvMergeUpdates)

deferSomeMergeInitEventM :: Defer SomeMergeInit EventM
deferSomeMergeInitEventM = Defer (asksEventEnv eventEnvMergeInits)

{-# inline getCurrentHeight #-}
getCurrentHeight :: EventM Height
getCurrentHeight = do
  heightRef <- asksEventEnv eventEnvCurrentHeight
  liftIO $ readIORef heightRef

{-# inline scheduleMerge #-}
scheduleMerge :: Height -> EventM () -> EventM ()
scheduleMerge height subscribed = do
  delayedRef <- asksEventEnv eventEnvDelayedMerges
  liftIO $ modifyIORef' delayedRef $ IntMap.insertWith (++) (unHeight height) [subscribed]

putCurrentHeight :: Height -> EventM ()
putCurrentHeight h = do
  heightRef <- asksEventEnv eventEnvCurrentHeight
  liftIO $ writeIORef heightRef $! h

deferSomeClearEventM :: Defer SomeClear EventM
deferSomeClearEventM = Defer (asksEventEnv eventEnvClears)

{-# inline scheduleClear #-}
scheduleClear :: IORef (Maybe a) -> EventM ()
scheduleClear r = defer deferSomeClearEventM (SomeClear r)

deferSomeIntClearEventM :: Defer SomeIntClear EventM
deferSomeIntClearEventM = Defer (asksEventEnv eventEnvIntClears)

{-# inline scheduleIntClear #-}
scheduleIntClear :: IORef (IntMap a) -> EventM ()
scheduleIntClear r = defer deferSomeIntClearEventM $ SomeIntClear r

deferSomeRootClearEventM :: Defer SomeRootClear EventM
deferSomeRootClearEventM = Defer (asksEventEnv eventEnvRootClears)

{-# inline scheduleRootClear #-}
scheduleRootClear :: IORef (DMap k Identity) -> EventM ()
scheduleRootClear r = defer deferSomeRootClearEventM $ SomeRootClear r

deferSomeResetCoincidenceEventM :: Defer SomeResetCoincidence EventM
deferSomeResetCoincidenceEventM = Defer (asksEventEnv eventEnvResetCoincidences)

holdE :: Patch p => PatchTarget p -> Event p -> EventM (Hold p)
holdE v0 e = hold' deferSomeHoldInitEventM v0 e

--holdB :: Patch p => PatchTarget p -> Event p -> BehaviorM (Hold p)
--holdB v0 e = hold' deferSomeHoldInitBehaviorM v0 e
 
-- Note: hold cannot examine its event until after the phase is over
{-# inline [1] hold' #-}
hold' :: (Patch p) => MonadIO m => Defer SomeHoldInit m -> PatchTarget p -> Event p -> m (Hold p)
hold' d v0 e = do
  valRef <- liftIO $ newIORef v0
  invsRef <- liftIO $ newIORef []
  parentRef <- liftIO $ newIORef Nothing
#ifdef DEBUG_NODEIDS
  nodeId <- liftIO newNodeId
#endif
  let h = Hold
        { holdValue = valRef
        , holdInvalidators = invsRef
        , holdEvent = e
        , holdParent = parentRef
#ifdef DEBUG_NODEIDS
        , holdNodeId = nodeId
#endif
        }
  defer d $ SomeHoldInit h
  return h

{-# inline getHoldEventSubscription #-}
getHoldEventSubscription :: forall p. (Patch p) => Hold p -> EventM (EventSubscription)
getHoldEventSubscription h = do
  ep <- liftIO $ readIORef $ holdParent h
  case ep of
    Just subd -> return subd
    Nothing -> do
      let e = holdEvent h
      subscriptionRef <- liftIO $ newIORef $ error "getHoldEventSubscription: subdRef uninitialized"
      (subscription@(EventSubscription _ _), occ) <- subscribeAndRead e =<< liftIO (newSubscriberHold h)
      liftIO $ writeIORef subscriptionRef $! subscription
      case occ of
        Nothing -> return ()
        Just o -> do
          old <- liftIO $ readIORef $ holdValue h
          case apply o old of
            Nothing -> return ()
            Just new -> do
              -- Need to evaluate these so that we don't retain the Hold itself
              v <- liftIO $ evaluate $ holdValue h
              i <- liftIO $ evaluate $ holdInvalidators h
              defer deferSomeAssignmentEventM $ SomeAssignment v i new
      liftIO $ writeIORef (holdParent h) $ Just subscription
      return subscription

type BehaviorEnv = (Maybe (Weak Invalidator, IORef [SomeBehaviorSubscribed]), IORef [SomeHoldInit])

--type role BehaviorM representational
-- BehaviorM can sample behaviors
newtype BehaviorM a = BehaviorM { unBehaviorM :: ReaderT BehaviorEnv IO a } deriving (Functor, Applicative, MonadIO, MonadFix)

instance Monad BehaviorM where
  {-# inline (>>=) #-}
  BehaviorM x >>= f = BehaviorM $ x >>= unBehaviorM . f
  {-# inline (>>) #-}
  BehaviorM x >> BehaviorM y = BehaviorM $ x >> y
  {-# inline return #-}
  return x = BehaviorM $ return x
  {-# inline fail #-}
  fail s = BehaviorM $ fail s

data BehaviorSubscribed a
   = forall p. BehaviorSubscribedHold (Hold p)
   | BehaviorSubscribedPull (PullSubscribed a)

data SomeBehaviorSubscribed = forall a. SomeBehaviorSubscribed (BehaviorSubscribed a)

--type role PullSubscribed representational
data PullSubscribed a
   = PullSubscribed { pullSubscribedValue :: !a
                    , pullSubscribedInvalidators :: !(IORef [Weak Invalidator])
                    , pullSubscribedOwnInvalidator :: !Invalidator
                    , pullSubscribedParents :: ![SomeBehaviorSubscribed] -- Need to keep parent behaviors alive, or they won't let us know when they're invalidated
                    }

--type role Pull representational
data Pull a
   = Pull { pullValue :: !(IORef (Maybe (PullSubscribed a)))
          , pullCompute :: !(BehaviorM a)
#ifdef DEBUG_NODEIDS
          , pullNodeId :: Int
#endif
          }

data Invalidator
   = forall a. InvalidatorPull (Pull a)
   | forall a. InvalidatorSwitch (SwitchSubscribed a)

data RootSubscribed a = forall k. GCompare k => RootSubscribed
  { rootSubscribedKey :: !(k a)
  , rootSubscribedCachedSubscribed :: !(IORef (DMap k RootSubscribed)) -- From the original Root
  , rootSubscribedSubscribers :: !(WeakBag (Subscriber a))
  , rootSubscribedOccurrence :: !(IO (Maybe a)) -- Lookup from rootOccurrence
  , rootSubscribedUninit :: IO ()
  , rootSubscribedWeakSelf :: !(IORef (Weak (RootSubscribed a))) --TODO: Can we make this a lazy non-IORef and then force it manually to avoid an indirection each time we use it?
#ifdef DEBUG_NODEIDS
  , rootSubscribedNodeId :: Int
#endif
  }

data Root (k :: * -> *)
   = Root { rootOccurrence :: !(IORef (DMap k Identity)) -- The currently-firing occurrence of this event
          , rootSubscribed :: !(IORef (DMap k RootSubscribed))
          , rootInit :: !(forall a. k a -> EventTrigger a -> IO (IO ()))
          }

data SomeHoldInit = forall p. Patch p => SomeHoldInit !(Hold p)

data SomeDynInit = forall p. Patch p => SomeDynInit !(Dyn p)

data SomeMergeUpdate = SomeMergeUpdate
  { _someMergeUpdate_update :: !(EventM [EventSubscription])
  , _someMergeUpdate_invalidateHeight :: !(IO ())
  , _someMergeUpdate_recalculateHeight :: !(IO ())
  }

newtype SomeMergeInit = SomeMergeInit { unSomeMergeInit :: EventM () }

newtype MergeSubscribedParent a = MergeSubscribedParent { unMergeSubscribedParent :: EventSubscription }

data MergeSubscribedParentWithMove k a = MergeSubscribedParentWithMove
  { _mergeSubscribedParentWithMove_subscription :: !EventSubscription
  , _mergeSubscribedParentWithMove_key :: !(IORef (k a))
  }

data HeightBag = HeightBag
  { _heightBag_size :: {-# UNPACK #-} !Int
  , _heightBag_contents :: !(IntMap Word) -- Number of excess in each bucket
  }
  deriving (Show, Read, Eq, Ord)

heightBagEmpty :: HeightBag
heightBagEmpty = heightBagVerify $ HeightBag 0 IntMap.empty

heightBagSize :: HeightBag -> Int
heightBagSize = _heightBag_size

heightBagFromList :: [Height] -> HeightBag
heightBagFromList heights = heightBagVerify $ foldl' (flip heightBagAdd) heightBagEmpty heights

heightBagAdd :: Height -> HeightBag -> HeightBag
heightBagAdd (Height h) (HeightBag s c) = heightBagVerify $ HeightBag (succ s) $ IntMap.insertWithKey (\_ _ old -> succ old) h 0 c

heightBagRemove :: Height -> HeightBag -> HeightBag
heightBagRemove (Height h) b@(HeightBag s c) = heightBagVerify $ case IntMap.lookup h c of
  Nothing -> error $ "heightBagRemove: Height " <> show h <> " not present in bag " <> show b
  Just old -> HeightBag (pred s) $ case old of
    0 -> IntMap.delete h c
    _ -> IntMap.insert h (pred old) c

heightBagMax :: HeightBag -> Height
heightBagMax (HeightBag _ c) = case IntMap.maxViewWithKey c of
  Just ((h, _), _) -> Height h
  Nothing -> zeroHeight

heightBagVerify :: HeightBag -> HeightBag
#ifdef DEBUG
heightBagVerify b@(HeightBag s c) = if
  | s /= IntMap.size c + fromIntegral (sum (IntMap.elems c))
    -> error $ "heightBagVerify: size doesn't match: " <> show b
  | unHeight invalidHeight `IntMap.member` c
    -> error $ "heightBagVerify: contains invalid height: " <> show b
  | otherwise -> b
#else
heightBagVerify = id
#endif

data FanSubscribedChildren (k :: * -> *) (a :: *) = FanSubscribedChildren
  { _fanSubscribedChildren_list :: !(WeakBag (Subscriber a))
  , _fanSubscribedChildren_self :: {-# NOUNPACK #-} !(k a, FanSubscribed k)
  , _fanSubscribedChildren_weakSelf :: !(IORef (Weak (k a, FanSubscribed k)))
  }

data FanSubscribed (k :: * -> *)
   = FanSubscribed { fanSubscribedCachedSubscribed :: !(IORef (Maybe (FanSubscribed k)))
                   , fanSubscribedOccurrence :: !(IORef (Maybe (DMap k Identity)))
                   , fanSubscribedSubscribers :: !(IORef (DMap k (FanSubscribedChildren k))) -- This DMap should never be empty
                   , fanSubscribedParent :: !EventSubscription
#ifdef DEBUG_NODEIDS
                   , fanSubscribedNodeId :: Int
#endif
                   }

data Fan k
   = Fan { fanParent :: !(Event (DMap k Identity))
         , fanSubscribed :: !(IORef (Maybe (FanSubscribed k)))
         }

data SwitchSubscribed a
   = SwitchSubscribed { switchSubscribedCachedSubscribed :: !(IORef (Maybe (SwitchSubscribed a)))
                      , switchSubscribedOccurrence :: !(IORef (Maybe a))
                      , switchSubscribedHeight :: !(IORef Height)
                      , switchSubscribedSubscribers :: !(WeakBag (Subscriber a))
                      , switchSubscribedOwnInvalidator :: {-# NOUNPACK #-} !Invalidator
                      , switchSubscribedOwnWeakInvalidator :: !(IORef (Weak Invalidator ))
                      , switchSubscribedBehaviorParents :: !(IORef [SomeBehaviorSubscribed])
                      , switchSubscribedParent :: !(Behavior (Event a))
                      , switchSubscribedCurrentParent :: !(IORef EventSubscription)
                      , switchSubscribedWeakSelf :: !(IORef (Weak (SwitchSubscribed a)))
#ifdef DEBUG_NODEIDS
                      , switchSubscribedNodeId :: Int
#endif
                      }

data Switch a
   = Switch { switchParent :: !(Behavior (Event a))
            , switchSubscribed :: !(IORef (Maybe (SwitchSubscribed a)))
            }

#ifdef USE_TEMPLATE_HASKELL
{-# ANN CoincidenceSubscribed "HLint: ignore Redundant bracket" #-}
#endif
data CoincidenceSubscribed a
   = CoincidenceSubscribed { coincidenceSubscribedCachedSubscribed :: !(IORef (Maybe (CoincidenceSubscribed a)))
                           , coincidenceSubscribedOccurrence :: !(IORef (Maybe a))
                           , coincidenceSubscribedSubscribers :: !(WeakBag (Subscriber a))
                           , coincidenceSubscribedHeight :: !(IORef Height)
                           , coincidenceSubscribedOuter :: {-# NOUNPACK #-} (Subscriber (Event a))
                           , coincidenceSubscribedOuterParent :: !(EventSubscription)
                           , coincidenceSubscribedInnerParent :: !(IORef (Maybe (EventSubscribed)))
                           , coincidenceSubscribedWeakSelf :: !(IORef (Weak (CoincidenceSubscribed a)))
#ifdef DEBUG_NODEIDS
                           , coincidenceSubscribedNodeId :: Int
#endif
                           }

data Coincidence a
   = Coincidence { coincidenceParent :: !(Event (Event a))
                 , coincidenceSubscribed :: !(IORef (Maybe (CoincidenceSubscribed a)))
                 }

{-# noinline newInvalidatorSwitch #-}
newInvalidatorSwitch :: SwitchSubscribed a -> IO Invalidator
newInvalidatorSwitch subd = return $! InvalidatorSwitch subd

{-# noinline newInvalidatorPull #-}
newInvalidatorPull :: Pull a -> IO Invalidator
newInvalidatorPull p = return $! InvalidatorPull p

instance Align Event where
  nil = never
  align :: Event a -> Event b -> Event (These a b)
  align ea eb = fmapMaybe dmapToThese $ merge' $ dynamicConst' $ DMap.fromDistinctAscList [LeftTag :=> ea, RightTag :=> eb]

data DynType p
  = UnsafeDyn !(BehaviorM (PatchTarget p), Event p)
  | BuildDyn  !(EventM (PatchTarget p), Event p)
  | HoldDyn   !(Hold p)

newtype Dyn p = Dyn { unDyn :: IORef (DynType p) }

newMapDyn :: (a -> b) -> Dynamic' (Identity a) -> Dynamic' (Identity b)
newMapDyn f d = dynamicDynIdentity' $ unsafeBuildDynamic' (fmap f $ readBehaviorTracked $ dynamicCurrent d) (Identity . f . runIdentity <$> dynamicUpdated d)

zipDyn :: Dynamic a -> Dynamic b -> Dynamic (a, b)
zipDyn = zipDynWith (,)

{-# inline zipDynWith #-}
zipDynWith :: (a -> b -> c) -> Dynamic a -> Dynamic b -> Dynamic c
zipDynWith f da db = Dynamic $ zipDynWith' f (unDynamic da) (unDynamic db)

--TODO: Avoid the duplication between this and R.zipDynWith
zipDynWith' :: (a -> b -> c) -> Dynamic' (Identity a) -> Dynamic' (Identity b) -> Dynamic' (Identity c)
zipDynWith' f da db =
  let eab = align (dynamicUpdated da) (dynamicUpdated db)
      ec = flip push' eab $ \o -> do
        (a, b) <- case o of
          This (Identity a) -> do
            b <- readBehaviorUntrackedE $ dynamicCurrent db
            return (a, b)
          That (Identity b) -> do
            a <- readBehaviorUntrackedE $ dynamicCurrent da
            return (a, b)
          These (Identity a) (Identity b) -> return (a, b)
        return $ Just $ Identity $ f a b
  in dynamicDynIdentity' $ unsafeBuildDynamic' (f <$> readBehaviorUntrackedB (dynamicCurrent da) <*> readBehaviorUntrackedB (dynamicCurrent db)) ec

buildDynamic' :: (Patch p) => EventM (PatchTarget p) -> Event p -> EventM (Dyn p)
buildDynamic' readV0 v' = do
  result <- liftIO $ newIORef $ BuildDyn (readV0, v')
  let !d = Dyn result
  defer deferSomeDynInitEventM $ SomeDynInit d
  pure d

unsafeBuildDynamic' :: BehaviorM (PatchTarget p) -> Event p -> Dyn p
unsafeBuildDynamic' readV0 v' = Dyn $ unsafeNewIORef x $ UnsafeDyn x
  where x = (readV0, v')

{-# noinline unsafeNewIORef #-}
unsafeNewIORef :: a -> b -> IORef b
unsafeNewIORef a b = unsafePerformIO $ do
  touch a
  newIORef b

tag :: Behavior b -> Event a -> Event b
tag b = pushAlways $ const (sample b)

tagMaybe :: Behavior (Maybe b) -> Event a -> Event b
tagMaybe b = push (const (sample b))

attach :: Behavior a -> Event b -> Event (a,b)
attach = attachWith (,)

attachWith :: (a -> b -> c) -> Behavior a -> Event b -> Event c
attachWith f = attachWithMaybe $ \a b -> Just $ f a b

attachWithMaybe :: (a -> b -> Maybe c) -> Behavior a -> Event b -> Event c
attachWithMaybe f b e = flip push e $ \o -> (`f` o) <$> sample b

-- Propagate the given event occurrence; before cleaning up, run the given action, which may read the state of events and behaviors
run :: forall b. [DSum EventTrigger Identity] -> EventM b -> SpiderHost b
run roots after = do
  tracePropagate (Proxy :: Proxy x) $ "Running an event frame with " <> show (length roots) <> " events"
  let t = spiderTimeline :: SpiderTimelineEnv x
  result <- SpiderHost $ withMVar (_spiderTimeline_lock t) $ \_ -> unSpiderHost $ runFrame $ do
    rootsToPropagate <- forM roots $ \r@(EventTrigger (_, occRef, k) :=> a) -> do
      occBefore <- liftIO $ do
        occBefore <- readIORef occRef
        writeIORef occRef $! DMap.insert k a occBefore
        return occBefore
      if DMap.null occBefore
        then do scheduleRootClear occRef
                return $ Just r
        else return Nothing
    forM_ (catMaybes rootsToPropagate) $ \(EventTrigger (subscribersRef, _, _) :=> Identity a) -> do
      propagate a subscribersRef
    delayedRef <- asksEventEnv eventEnvDelayedMerges
    let go = do
          delayed <- liftIO $ readIORef delayedRef
          case IntMap.minViewWithKey delayed of
            Nothing -> return ()
            Just ((currentHeight, cur), future) -> do
              tracePropagate (Proxy :: Proxy x) $ "Running height " ++ show currentHeight
              putCurrentHeight $ Height currentHeight
              liftIO $ writeIORef delayedRef $! future
              sequence_ cur
              go
    go
    putCurrentHeight maxBound
    after
  tracePropagate (Proxy :: Proxy x) "Done running an event frame"
  return result

scheduleMerge' :: Height -> IORef Height -> EventM () -> EventM ()
scheduleMerge' initialHeight heightRef a = scheduleMerge initialHeight $ do
  height <- liftIO $ readIORef heightRef
  currentHeight <- getCurrentHeight
  case height `compare` currentHeight of
    LT -> error "Somehow a merge's height has been decreased after it was scheduled"
    GT -> scheduleMerge' height heightRef a -- The height has been increased (by a coincidence event; TODO: is this the only way?)
    EQ -> a

data SomeClear = forall a. SomeClear {-# UNPACK #-} !(IORef (Maybe a))

data SomeIntClear = forall a. SomeIntClear {-# UNPACK #-} !(IORef (IntMap a))

data SomeRootClear = forall k. SomeRootClear {-# UNPACK #-} !(IORef (DMap k Identity))

data SomeAssignment = forall a. SomeAssignment {-# UNPACK #-} !(IORef a) {-# UNPACK #-} !(IORef [Weak Invalidator]) a

debugFinalize :: Bool
debugFinalize = False

mkWeakPtrWithDebug :: a -> String -> IO (Weak a)
mkWeakPtrWithDebug x debugNote = do
  x' <- evaluate x
  mkWeakPtr x' $
    if debugFinalize
    then Just $ putStrLn $ "finalizing: " ++ debugNote
    else Nothing

type WeakList a = [Weak a]

{-# inline withIncreasedDepth #-}
#ifdef DEBUG
withIncreasedDepth :: CanTrace x m => m a -> m a
withIncreasedDepth a = do
  spiderTimeline <- askSpiderTimelineEnv
  liftIO $ modifyIORef' (_spiderTimeline_depth spiderTimeline) succ
  result <- a
  liftIO $ modifyIORef' (_spiderTimeline_depth spiderTimeline) pred
  return result
#else
withIncreasedDepth :: m a -> m a
withIncreasedDepth = id
#endif

{-# inline tracePropagate #-}
tracePropagate :: MonadIO m => proxy x -> String -> m ()
tracePropagate p = traceWhen p debugPropagate

{-# inline traceInvalidate #-}
traceInvalidate :: String -> IO ()
traceInvalidate = when debugInvalidate . liftIO . putStrLn

{-# inline traceWhen #-}
traceWhen :: MonadIO m => proxy x -> Bool -> String -> m ()
traceWhen p b message = traceMWhen p b $ return message

{-# inline traceMWhen #-}
traceMWhen :: MonadIO m => proxy x -> Bool -> m String -> m ()
traceMWhen _ b getMessage = when b $ do
  message <- getMessage
#ifdef DEBUG
  spiderTimeline <- askSpiderTimelineEnv
  d <- liftIO $ readIORef $ _spiderTimeline_depth spiderTimeline
#else
  let d = 0
#endif
  liftIO $ putStrLn $ replicate d ' ' <> message

whoCreatedIORef :: IORef a -> IO [String]
whoCreatedIORef (IORef a) = whoCreated $! a

#ifdef DEBUG_CYCLES
groupByHead :: Eq a => [NonEmpty a] -> [(a, NonEmpty [a])]
groupByHead = \case
  [] -> []
  (x :| xs) : t -> case groupByHead t of
    [] -> [(x, xs :| [])]
    l@((y, yss) : t')
      | x == y -> (x, xs `NonEmpty.cons` yss) : t'
      | otherwise -> (x, xs :| []) : l

listsToForest :: Eq a => [[a]] -> Forest a
listsToForest l = fmap (\(a, l') -> Node a $ listsToForest $ toList l') $ groupByHead $ catMaybes $ fmap nonEmpty l
#endif

{-# inline propagateSubscriberHold #-}
propagateSubscriberHold :: forall p. (Patch p) => Hold p -> p -> EventM ()
propagateSubscriberHold h a = do
  {-# SCC "trace" #-} traceMWhen (Proxy :: Proxy x) debugPropagate $ liftIO $ do
    invalidators <- liftIO $ readIORef $ holdInvalidators h
    return $ "SubscriberHold" <> showNodeId h <> ": " ++ show (length invalidators)
  v <- {-# SCC "read" #-} liftIO $ readIORef $ holdValue h
  case {-# SCC "apply" #-} apply a v of
    Nothing -> return ()
    Just v' -> do
      {-# SCC "trace2" #-} withIncreasedDepth $ tracePropagate (Proxy :: Proxy x) $ "propagateSubscriberHold: assigning Hold" <> showNodeId h
      vRef <- {-# SCC "vRef" #-} liftIO $ evaluate $ holdValue h
      iRef <- {-# SCC "iRef" #-} liftIO $ evaluate $ holdInvalidators h
      defer deferSomeAssignmentEventM $ {-# SCC "assignment" #-} SomeAssignment vRef iRef v'

data SomeResetCoincidence = forall a. SomeResetCoincidence !(EventSubscription) !(Maybe (CoincidenceSubscribed a)) -- The CoincidenceSubscriber will be present only if heights need to be reset

runBehaviorM :: BehaviorM a -> Maybe (Weak Invalidator, IORef [SomeBehaviorSubscribed]) -> IORef [SomeHoldInit] -> IO a
runBehaviorM a mwi holdInits = runReaderT (unBehaviorM a) (mwi, holdInits)

askInvalidator :: BehaviorM (Maybe (Weak Invalidator))
askInvalidator = do
  (!m, _) <- BehaviorM ask
  case m of
    Nothing -> return Nothing
    Just (!wi, _) -> return $ Just wi

askParentsRef :: BehaviorM (Maybe (IORef [SomeBehaviorSubscribed]))
askParentsRef = do
  (!m, _) <- BehaviorM ask
  case m of
    Nothing -> return Nothing
    Just (_, !p) -> return $ Just p

askBehaviorHoldInits :: BehaviorM (IORef [SomeHoldInit])
askBehaviorHoldInits = do
  (_, !his) <- BehaviorM ask
  return his

getDynHoldE :: Patch p => Dyn p -> EventM (Hold p)
getDynHoldE d = getDynHold deferSomeHoldInitEventM d

getDynHoldB :: Patch p => Dyn p -> BehaviorM (Hold p)
getDynHoldB d = getDynHold deferSomeHoldInitBehaviorM d

{-# inline getDynHold #-}
getDynHold :: (Patch p, MonadIO m) => Defer SomeHoldInit m -> Dyn p -> m (Hold p)
getDynHold defr d = do
  mh <- liftIO $ readIORef $ unDyn d
  case mh of
    HoldDyn h -> return h
    UnsafeDyn (readV0, v') -> do
      holdInits <- unDefer defr
      v0 <- liftIO $ runBehaviorM readV0 Nothing holdInits
      hold'' v0 v'
    BuildDyn (readV0, v') -> do
      v0 <- liftIO $ runEventM readV0
      hold'' v0 v'
  where
    hold'' v0 v' = do
      h <- hold' defr v0 v'
      liftIO $ writeIORef (unDyn d) $ HoldDyn h
      return h


-- Always refers to 0
{-# noinline zeroRef #-}
zeroRef :: IORef Height
zeroRef = unsafePerformIO $ newIORef zeroHeight

getRootSubscribed :: GCompare k => k a -> Root k -> Subscriber a -> IO (WeakBagTicket, RootSubscribed a, Maybe a)
getRootSubscribed k r sub = do
  mSubscribed <- readIORef $ rootSubscribed r
  let getOcc = fmap (coerce . DMap.lookup k) $ readIORef $ rootOccurrence r
  case DMap.lookup k mSubscribed of
    Just subscribed -> {-# SCC "hitRoot" #-} do
      sln <- subscribeRootSubscribed subscribed sub
      occ <- getOcc
      return (sln, subscribed, occ)
    Nothing -> {-# SCC "missRoot" #-} do
      weakSelf <- newIORef $ error "getRootSubscribed: weakSelfRef not initialized"
      let !cached = rootSubscribed r
      uninitRef <- newIORef $ error "getRootsubscribed: uninitRef not initialized"
      (subs, sln) <- WeakBag.singleton sub weakSelf cleanupRootSubscribed
      when debugPropagate $ putStrLn $ "getRootSubscribed: calling rootInit"
      uninit <- rootInit r k $ EventTrigger (subs, rootOccurrence r, k)
      writeIORef uninitRef $! uninit
      let !subscribed = RootSubscribed
            { rootSubscribedKey = k
            , rootSubscribedCachedSubscribed = cached
            , rootSubscribedOccurrence = getOcc
            , rootSubscribedSubscribers = subs
            , rootSubscribedUninit = uninit
            , rootSubscribedWeakSelf = weakSelf
#ifdef DEBUG_NODEIDS
            , rootSubscribedNodeId = unsafeNodeId (k, r, subs)
#endif
            }
          -- If we die at the same moment that all our children die, they will
          -- try to clean us up but will fail because their Weak reference to us
          -- will also be dead.  So, if we are dying, check if there are any
          -- children; since children don't bother cleaning themselves up if
          -- their parents are already dead, I don't think there's a race
          -- condition here.  However, if there are any children, then we can
          -- infer that we need to clean ourselves up, so we do.
          finalCleanup = do
            cs <- readIORef $ _weakBag_children subs
            when (not $ IntMap.null cs) (cleanupRootSubscribed subscribed)
      writeIORef weakSelf =<< evaluate =<< mkWeakPtr subscribed (Just finalCleanup)
      modifyIORef' (rootSubscribed r) $ DMap.insertWith (error $ "getRootSubscribed: duplicate key inserted into Root") k subscribed --TODO: I think we can just write back mSubscribed rather than re-reading it
      occ <- getOcc
      return (sln, subscribed, occ)

#ifdef USE_TEMPLATE_HASKELL
{-# ANN cleanupRootSubscribed "HLint: ignore Redundant bracket" #-}
#endif
cleanupRootSubscribed :: RootSubscribed a -> IO ()
cleanupRootSubscribed self@RootSubscribed { rootSubscribedKey = k, rootSubscribedCachedSubscribed = cached } = do
  rootSubscribedUninit self
  modifyIORef' cached $ DMap.delete k

{-# inline subscribeRootSubscribed #-}
subscribeRootSubscribed :: RootSubscribed a -> Subscriber a -> IO WeakBagTicket
subscribeRootSubscribed subscribed sub = WeakBag.insert sub (rootSubscribedSubscribers subscribed) (rootSubscribedWeakSelf subscribed) cleanupRootSubscribed

newtype EventSelectorInt a = EventSelectorInt { selectInt :: Int -> Event a }

data FanInt a = FanInt
  { _fanInt_subscribers :: {-# UNPACK #-} !(FastMutableIntMap (FastWeakBag (Subscriber a))) --TODO: Clean up the keys in here when their child weak bags get empty --TODO: Remove our own subscription when the subscribers list is completely empty
  , _fanInt_subscriptionRef :: {-# UNPACK #-} !(IORef (EventSubscription)) -- This should have a valid subscription iff subscribers is non-empty
  , _fanInt_occRef :: {-# UNPACK #-} !(IORef (IntMap a))
  }

newFanInt :: IO (FanInt a)
newFanInt = do
  subscribers <- FastMutableIntMap.newEmpty --TODO: Clean up the keys in here when their child weak bags get empty --TODO: Remove our own subscription when the subscribers list is completely empty
  subscriptionRef <- newIORef $ error "fanInt: no subscription"
  occRef <- newIORef $ error "fanInt: no occurrence"
  return $ FanInt
    { _fanInt_subscribers = subscribers
    , _fanInt_subscriptionRef = subscriptionRef
    , _fanInt_occRef = occRef
    }

{-# noinline unsafeNewFanInt #-}
unsafeNewFanInt :: b -> FanInt a
unsafeNewFanInt b = unsafePerformIO $ do
  touch b
  newFanInt

{-# inlinable getFanSubscribed #-}
getFanSubscribed :: (GCompare k) => k a -> Fan k -> Subscriber a -> EventM (WeakBagTicket, FanSubscribed k, Maybe a)
getFanSubscribed k f sub = do
  mSubscribed <- liftIO $ readIORef $ fanSubscribed f
  case mSubscribed of
    Just subscribed -> {-# SCC "hitFan" #-} liftIO $ do
      sln <- subscribeFanSubscribed k subscribed sub
      occ <- readIORef $ fanSubscribedOccurrence subscribed
      return (sln, subscribed, coerce $ DMap.lookup k =<< occ)
    Nothing -> {-# SCC "missFan" #-} do
      subscribedRef <- liftIO $ newIORef $ error "getFanSubscribed: subscribedRef not yet initialized"
      subscribedUnsafe <- liftIO $ unsafeInterleaveIO $ readIORef subscribedRef
      s <- liftIO $ newSubscriberFan subscribedUnsafe
      (subscription, parentOcc) <- subscribeAndRead (fanParent f) s
      weakSelf <- liftIO $ newIORef $ error "getFanSubscribed: weakSelf not yet initialized"
      (subsForK, slnForSub) <- liftIO $ WeakBag.singleton sub weakSelf cleanupFanSubscribed
      subscribersRef <- liftIO $ newIORef $ error "getFanSubscribed: subscribersRef not yet initialized"
      occRef <- liftIO $ newIORef parentOcc
      when (isJust parentOcc) $ scheduleClear occRef
      let subscribed = FanSubscribed
            { fanSubscribedCachedSubscribed = fanSubscribed f
            , fanSubscribedOccurrence = occRef
            , fanSubscribedParent = subscription
            , fanSubscribedSubscribers = subscribersRef
#ifdef DEBUG_NODEIDS
            , fanSubscribedNodeId = unsafeNodeId f
#endif
            }
      let !self = (k, subscribed)
      liftIO $ writeIORef subscribersRef $! DMap.singleton k $ FanSubscribedChildren subsForK self weakSelf
      liftIO $ writeIORef weakSelf =<< evaluate =<< mkWeakPtrWithDebug self "FanSubscribed"
      liftIO $ writeIORef subscribedRef $! subscribed
      liftIO $ writeIORef (fanSubscribed f) $ Just subscribed
      return (slnForSub, subscribed, coerce $ DMap.lookup k =<< parentOcc)

cleanupFanSubscribed :: GCompare k => (k a, FanSubscribed k) -> IO ()
cleanupFanSubscribed (k, subscribed) = do
  subscribers <- readIORef $ fanSubscribedSubscribers subscribed
  let reducedSubscribers = DMap.delete k subscribers
  if DMap.null reducedSubscribers
    then do
      unsubscribe $ fanSubscribedParent subscribed
      -- Not necessary in this case, because this whole FanSubscribed is dead: writeIORef (fanSubscribedSubscribers subscribed) reducedSubscribers
      writeIORef (fanSubscribedCachedSubscribed subscribed) Nothing
    else writeIORef (fanSubscribedSubscribers subscribed) $! reducedSubscribers

{-# inline subscribeFanSubscribed #-}
subscribeFanSubscribed :: GCompare k => k a -> FanSubscribed k -> Subscriber a -> IO WeakBagTicket
subscribeFanSubscribed k subscribed sub = do
  subscribers <- readIORef $ fanSubscribedSubscribers subscribed
  case DMap.lookup k subscribers of
    Nothing -> {-# SCC "missSubscribeFanSubscribed" #-} do
      let !self = (k, subscribed)
      weakSelf <- newIORef =<< mkWeakPtrWithDebug self "FanSubscribed"
      (list, sln) <- WeakBag.singleton sub weakSelf cleanupFanSubscribed
      writeIORef (fanSubscribedSubscribers subscribed) $! DMap.insertWith (error "subscribeFanSubscribed: key that we just failed to find is present - should be impossible") k (FanSubscribedChildren list self weakSelf) subscribers
      return sln
    Just (FanSubscribedChildren list _ weakSelf) -> {-# SCC "hitSubscribeFanSubscribed" #-} WeakBag.insert sub list weakSelf cleanupFanSubscribed

{-# inlinable getSwitchSubscribed #-}
getSwitchSubscribed :: Switch a -> Subscriber a -> EventM (WeakBagTicket, SwitchSubscribed a, Maybe a)
getSwitchSubscribed s sub = do
  mSubscribed <- liftIO $ readIORef $ switchSubscribed s
  case mSubscribed of
    Just subscribed -> {-# SCC "hitSwitch" #-} liftIO $ do
      sln <- subscribeSwitchSubscribed subscribed sub
      occ <- readIORef $ switchSubscribedOccurrence subscribed
      return (sln, subscribed, occ)
    Nothing -> {-# SCC "missSwitch" #-} do
      subscribedRef <- liftIO $ newIORef $ error "getSwitchSubscribed: subscribed has not yet been created"
      subscribedUnsafe <- liftIO $ unsafeInterleaveIO $ readIORef subscribedRef
      i <- liftIO $ newInvalidatorSwitch subscribedUnsafe
      mySub <- liftIO $ newSubscriberSwitch subscribedUnsafe
      wi <- liftIO $ mkWeakPtrWithDebug i "InvalidatorSwitch"
      wiRef <- liftIO $ newIORef wi
      parentsRef <- liftIO $ newIORef [] --TODO: This should be unnecessary, because it will always be filled with just the single parent behavior
      holdInits <- unDefer deferSomeHoldInitEventM
      e <- liftIO $ runBehaviorM (readBehaviorTracked (switchParent s)) (Just (wi, parentsRef)) holdInits
      (subscription@(EventSubscription _ subd), parentOcc) <- subscribeAndRead e mySub
      heightRef <- liftIO $ newIORef =<< getEventSubscribedHeight subd
      subscriptionRef <- liftIO $ newIORef subscription
      occRef <- liftIO $ newIORef parentOcc
      when (isJust parentOcc) $ scheduleClear occRef
      weakSelf <- liftIO $ newIORef $ error "getSwitchSubscribed: weakSelf not yet initialized"
      (subs, slnForSub) <- liftIO $ WeakBag.singleton sub weakSelf cleanupSwitchSubscribed
      let !subscribed = SwitchSubscribed
            { switchSubscribedCachedSubscribed = switchSubscribed s
            , switchSubscribedOccurrence = occRef
            , switchSubscribedHeight = heightRef
            , switchSubscribedSubscribers = subs
            , switchSubscribedOwnInvalidator = i
            , switchSubscribedOwnWeakInvalidator = wiRef
            , switchSubscribedBehaviorParents = parentsRef
            , switchSubscribedParent = switchParent s
            , switchSubscribedCurrentParent = subscriptionRef
            , switchSubscribedWeakSelf = weakSelf
#ifdef DEBUG_NODEIDS
            , switchSubscribedNodeId = unsafeNodeId s
#endif
            }
      liftIO $ writeIORef weakSelf =<< evaluate =<< mkWeakPtrWithDebug subscribed "switchSubscribedWeakSelf"
      liftIO $ writeIORef subscribedRef $! subscribed
      liftIO $ writeIORef (switchSubscribed s) $ Just subscribed
      return (slnForSub, subscribed, parentOcc)

cleanupSwitchSubscribed :: SwitchSubscribed a -> IO ()
cleanupSwitchSubscribed subscribed = do
  unsubscribe =<< readIORef (switchSubscribedCurrentParent subscribed)
  finalize =<< readIORef (switchSubscribedOwnWeakInvalidator subscribed) -- We don't need to get invalidated if we're dead
  writeIORef (switchSubscribedCachedSubscribed subscribed) Nothing

{-# inline subscribeSwitchSubscribed #-}
subscribeSwitchSubscribed :: SwitchSubscribed a -> Subscriber a -> IO WeakBagTicket
subscribeSwitchSubscribed subscribed sub = WeakBag.insert sub (switchSubscribedSubscribers subscribed) (switchSubscribedWeakSelf subscribed) cleanupSwitchSubscribed

{-# inlinable getCoincidenceSubscribed #-}
getCoincidenceSubscribed :: forall a. Coincidence a -> Subscriber a -> EventM (WeakBagTicket, CoincidenceSubscribed a, Maybe a)
getCoincidenceSubscribed c sub = do
  mSubscribed <- liftIO $ readIORef $ coincidenceSubscribed c
  case mSubscribed of
    Just subscribed -> {-# SCC "hitCoincidence" #-} liftIO $ do
      sln <- subscribeCoincidenceSubscribed subscribed sub
      occ <- readIORef $ coincidenceSubscribedOccurrence subscribed
      return (sln, subscribed, occ)
    Nothing -> {-# SCC "missCoincidence" #-} do
      subscribedRef <- liftIO $ newIORef $ error "getCoincidenceSubscribed: subscribed has not yet been created"
      subscribedUnsafe <- liftIO $ unsafeInterleaveIO $ readIORef subscribedRef
      subOuter <- liftIO $ newSubscriberCoincidenceOuter subscribedUnsafe
      (outerSubscription@(EventSubscription _ outerSubd), outerOcc) <- subscribeAndRead (coincidenceParent c) subOuter
      outerHeight <- liftIO $ getEventSubscribedHeight outerSubd
      (occ, height, mInnerSubd) <- case outerOcc of
        Nothing -> return (Nothing, outerHeight, Nothing)
        Just o -> do
          (occ, height, innerSubd) <- subscribeCoincidenceInner o outerHeight subscribedUnsafe
          return (occ, height, Just innerSubd)
      occRef <- liftIO $ newIORef occ
      when (isJust occ) $ scheduleClear occRef
      heightRef <- liftIO $ newIORef height
      innerSubdRef <- liftIO $ newIORef mInnerSubd
      scheduleClear innerSubdRef
      weakSelf <- liftIO $ newIORef $ error "getCoincidenceSubscribed: weakSelf not yet implemented"
      (subs, slnForSub) <- liftIO $ WeakBag.singleton sub weakSelf cleanupCoincidenceSubscribed
      let subscribed = CoincidenceSubscribed
            { coincidenceSubscribedCachedSubscribed = coincidenceSubscribed c
            , coincidenceSubscribedOccurrence = occRef
            , coincidenceSubscribedHeight = heightRef
            , coincidenceSubscribedSubscribers = subs
            , coincidenceSubscribedOuter = subOuter
            , coincidenceSubscribedOuterParent = outerSubscription
            , coincidenceSubscribedInnerParent = innerSubdRef
            , coincidenceSubscribedWeakSelf = weakSelf
#ifdef DEBUG_NODEIDS
            , coincidenceSubscribedNodeId = unsafeNodeId c
#endif
            }
      liftIO $ writeIORef weakSelf =<< evaluate =<< mkWeakPtrWithDebug subscribed "CoincidenceSubscribed"
      liftIO $ writeIORef subscribedRef $! subscribed
      liftIO $ writeIORef (coincidenceSubscribed c) $ Just subscribed
      return (slnForSub, subscribed, occ)

cleanupCoincidenceSubscribed :: CoincidenceSubscribed a -> IO ()
cleanupCoincidenceSubscribed subscribed = do
  unsubscribe $ coincidenceSubscribedOuterParent subscribed
  writeIORef (coincidenceSubscribedCachedSubscribed subscribed) Nothing

{-# inline subscribeCoincidenceSubscribed #-}
subscribeCoincidenceSubscribed :: CoincidenceSubscribed a -> Subscriber a -> IO WeakBagTicket
subscribeCoincidenceSubscribed subscribed sub = WeakBag.insert sub (coincidenceSubscribedSubscribers subscribed) (coincidenceSubscribedWeakSelf subscribed) cleanupCoincidenceSubscribed

{-# inline merge #-}
merge' :: forall k. (GCompare k) => Dynamic' (PatchDMap k (Event)) -> Event (DMap k Identity)
merge' d = cacheEvent (mergeCheap d)

{-# inline mergeWithMove #-}
mergeWithMove :: forall k. (GCompare k) => Dynamic' (PatchDMapWithMove k (Event)) -> Event (DMap k Identity)
mergeWithMove d = cacheEvent (mergeCheapWithMove d)

{-# inline [1] mergeCheap #-}
mergeCheap :: forall k. (GCompare k) => Dynamic' (PatchDMap k (Event)) -> Event (DMap k Identity)
mergeCheap = mergeCheap' getInitialSubscribers updateMe destroy
  where
      updateMe :: MergeUpdateFunc k (PatchDMap k Event) MergeSubscribedParent
      updateMe subscriber heightBagRef oldParents (PatchDMap p) = do
        let f (subscriptionsToKill, ps) (k :=> ComposeMaybe me) = do
              (mOldSubd, newPs) <- case me of
                Nothing -> return $ DMap.updateLookupWithKey (\_ _ -> Nothing) k ps
                Just e -> do
                  let s = subscriber $ return k
                  subscription@(EventSubscription _ subd) <- subscribe e s
                  newParentHeight <- liftIO $ getEventSubscribedHeight subd
                  let newParent = MergeSubscribedParent subscription
                  liftIO $ modifyIORef' heightBagRef $ heightBagAdd newParentHeight
                  return $ DMap.insertLookupWithKey' (\_ new _ -> new) k newParent ps
              forM_ mOldSubd $ \oldSubd -> do
                oldHeight <- liftIO $ getEventSubscribedHeight $ _eventSubscription_subscribed $ unMergeSubscribedParent oldSubd
                liftIO $ modifyIORef heightBagRef $ heightBagRemove oldHeight
              return (maybeToList (unMergeSubscribedParent <$> mOldSubd) ++ subscriptionsToKill, newPs)
        foldlM f ([], oldParents) $ DMap.toList p
      getInitialSubscribers :: MergeInitFunc k MergeSubscribedParent
      getInitialSubscribers initialParents subscriber = do
        subscribers <- forM (DMap.toList initialParents) $ \(k :=> e) -> do
          let s = subscriber $ return k
          (subscription@(EventSubscription _ parentSubd), parentOcc) <- subscribeAndRead e s
          height <- liftIO $ getEventSubscribedHeight parentSubd
          return (fmap (\x -> k :=> Identity x) parentOcc, height, k :=> MergeSubscribedParent subscription)
        return ( DMap.fromDistinctAscList $ mapMaybe (\(x, _, _) -> x) subscribers
               , fmap (\(_, h, _) -> h) subscribers --TODO: Assert that there's no invalidHeight in here
               , DMap.fromDistinctAscList $ map (\(_, _, x) -> x) subscribers
               )
      destroy :: MergeDestroyFunc k MergeSubscribedParent
      destroy s = forM_ (DMap.toList s) $ \(_ :=> MergeSubscribedParent sub) -> unsubscribe sub

{-# inline [1] mergeCheapWithMove #-}
mergeCheapWithMove :: forall k. (GCompare k) => Dynamic' (PatchDMapWithMove k (Event)) -> Event (DMap k Identity)
mergeCheapWithMove = mergeCheap' getInitialSubscribers updateMe destroy
  where
      updateMe :: MergeUpdateFunc k (PatchDMapWithMove k (Event)) (MergeSubscribedParentWithMove k)
      updateMe subscriber heightBagRef oldParents p = do
        -- Prepare new parents for insertion
        let subscribeParent :: forall a. k a -> Event a -> EventM (MergeSubscribedParentWithMove k a)
            subscribeParent k e = do
              keyRef <- liftIO $ newIORef k
              let s = subscriber $ liftIO $ readIORef keyRef
              subscription@(EventSubscription _ subd) <- subscribe e s
              liftIO $ do
                newParentHeight <- getEventSubscribedHeight subd
                modifyIORef' heightBagRef $ heightBagAdd newParentHeight
                return $ MergeSubscribedParentWithMove subscription keyRef
        p' <- PatchDMapWithMove.traversePatchDMapWithMoveWithKey subscribeParent p
        -- Collect old parents for deletion and update the keys of moved parents
        let moveOrDelete :: forall a. k a -> PatchDMapWithMove.NodeInfo k (Event) a -> MergeSubscribedParentWithMove k a -> Constant (EventM (Maybe (EventSubscription))) a
            moveOrDelete _ ni parent = Constant $ case getComposeMaybe $ PatchDMapWithMove._nodeInfo_to ni of
              Nothing -> do
                oldHeight <- liftIO $ getEventSubscribedHeight $ _eventSubscription_subscribed $ _mergeSubscribedParentWithMove_subscription parent
                liftIO $ modifyIORef heightBagRef $ heightBagRemove oldHeight
                return $ Just $ _mergeSubscribedParentWithMove_subscription parent
              Just toKey -> do
                liftIO $ writeIORef (_mergeSubscribedParentWithMove_key parent) $! toKey
                return Nothing
        toDelete <- fmap catMaybes $ mapM (\(_ :=> v) -> getConstant v) $ DMap.toList $ DMap.intersectionWithKey moveOrDelete (unPatchDMapWithMove p) oldParents
        return (toDelete, applyAlways p' oldParents)
      getInitialSubscribers :: MergeInitFunc k (MergeSubscribedParentWithMove k)
      getInitialSubscribers initialParents subscriber = do
        subscribers <- forM (DMap.toList initialParents) $ \(k :=> e) -> do
          keyRef <- liftIO $ newIORef k
          let s = subscriber $ liftIO $ readIORef keyRef
          (subscription@(EventSubscription _ parentSubd), parentOcc) <- subscribeAndRead e s
          height <- liftIO $ getEventSubscribedHeight parentSubd
          return (fmap (\x -> k :=> Identity x) parentOcc, height, k :=> MergeSubscribedParentWithMove subscription keyRef)
        return ( DMap.fromDistinctAscList $ mapMaybe (\(x, _, _) -> x) subscribers
               , fmap (\(_, h, _) -> h) subscribers --TODO: Assert that there's no invalidHeight in here
               , DMap.fromDistinctAscList $ map (\(_, _, x) -> x) subscribers
               )
      destroy :: MergeDestroyFunc k (MergeSubscribedParentWithMove k)
      destroy s = forM_ (DMap.toList s) $ \(_ :=> MergeSubscribedParentWithMove sub _) -> unsubscribe sub

type MergeUpdateFunc k p s
   = (forall a. EventM (k a) -> Subscriber a)
  -> IORef HeightBag
  -> DMap k s
  -> p
  -> EventM ([EventSubscription], DMap k s)

type MergeInitFunc k s
   = DMap k (Event)
  -> (forall a. EventM (k a) -> Subscriber a)
  -> EventM (DMap k Identity, [Height], DMap k s)

type MergeDestroyFunc k s
   = DMap k s
  -> IO ()

data Merge k s = Merge
  { _merge_parentsRef :: {-# UNPACK #-} !(IORef (DMap k s))
  , _merge_heightBagRef :: {-# UNPACK #-} !(IORef HeightBag)
  , _merge_heightRef :: {-# UNPACK #-} !(IORef Height)
  , _merge_sub :: {-# UNPACK #-} !(Subscriber (DMap k Identity))
  , _merge_accumRef :: {-# UNPACK #-} !(IORef (DMap k Identity))
  }

invalidateMergeHeight :: Merge k s -> IO ()
invalidateMergeHeight m = invalidateMergeHeight' (_merge_heightRef m) (_merge_sub m)

invalidateMergeHeight' :: IORef Height -> Subscriber a -> IO ()
invalidateMergeHeight' heightRef sub = do
  oldHeight <- readIORef heightRef
  when (oldHeight /= invalidHeight) $ do -- If the height used to be valid, it must be invalid now; we should never have *more* heights than we have parents
    writeIORef heightRef $! invalidHeight
    subscriberInvalidateHeight sub oldHeight


revalidateMergeHeight :: Merge k s -> IO ()
revalidateMergeHeight m = do
  currentHeight <- readIORef $ _merge_heightRef m
  when (currentHeight == invalidHeight) $ do -- revalidateMergeHeight may be called multiple times; perhaps the's a way to finesse it to avoid this check
    heights <- readIORef $ _merge_heightBagRef m
    parents <- readIORef $ _merge_parentsRef m
    -- When the number of heights in the bag reaches the number of parents, we should have a valid height
    case heightBagSize heights `compare` DMap.size parents of
      LT -> return ()
      EQ -> do
        let height = succHeight $ heightBagMax heights
        when debugInvalidateHeight $ putStrLn $ "recalculateSubscriberHeight: height: " <> show height
        writeIORef (_merge_heightRef m) $! height
        subscriberRecalculateHeight (_merge_sub m) height
      GT -> error $ "revalidateMergeHeight: more heights (" <> show (heightBagSize heights) <> ") than parents (" <> show (DMap.size parents) <> ") for Merge"

scheduleMergeSelf :: Merge k s -> Height -> EventM ()
scheduleMergeSelf m height = scheduleMerge' height (_merge_heightRef m) $ do
  vals <- liftIO $ readIORef $ _merge_accumRef m
  liftIO $ writeIORef (_merge_accumRef m) $! DMap.empty -- Once we're done with this, we can clear it immediately, because if there's a cacheEvent in front of us, it'll handle subsequent subscribers, and if not, we won't get subsequent subscribers
  --TODO: Assert that m is not empty
  subscriberPropagate (_merge_sub m) vals

mergeSubscriber :: forall k s a. (GCompare k) => Merge k s -> EventM (k a) -> Subscriber a
mergeSubscriber m getKey = Subscriber
  { subscriberPropagate = \a -> do
      oldM <- liftIO $ readIORef $ _merge_accumRef m
      k <- getKey
      let newM = DMap.insertWith (error $ "Same key fired multiple times for Merge") k (Identity a) oldM
      tracePropagate (Proxy :: Proxy x) $ "  DMap.size oldM = " <> show (DMap.size oldM) <> "; DMap.size newM = " <> show (DMap.size newM)
      liftIO $ writeIORef (_merge_accumRef m) $! newM
      when (DMap.null oldM) $ do -- Only schedule the firing once
        height <- liftIO $ readIORef $ _merge_heightRef m
        --TODO: assertions about height
        currentHeight <- getCurrentHeight
        when (height <= currentHeight) $ do
          if height /= invalidHeight
            then do
            myStack <- liftIO $ whoCreatedIORef undefined --TODO
            error $ "Height (" ++ show height ++ ") is not greater than current height (" ++ show currentHeight ++ ")\n" ++ unlines (reverse myStack)
            else liftIO $ do
#ifdef DEBUG_CYCLES
            nodesInvolvedInCycle <- walkInvalidHeightParents $ eventSubscribedMerge subscribed
            stacks <- forM nodesInvolvedInCycle $ \(Some.This es) -> whoCreatedEventSubscribed es
            let cycleInfo = ":\n" <> drawForest (listsToForest stacks)
#else
            let cycleInfo = ""
#endif
            error $ "Causality loop found" <> cycleInfo
        scheduleMergeSelf m height
  , subscriberInvalidateHeight = \old -> do --TODO: When removing a parent doesn't actually change the height, maybe we can avoid invalidating
      modifyIORef' (_merge_heightBagRef m) $ heightBagRemove old
      invalidateMergeHeight m
  , subscriberRecalculateHeight = \new -> do
      modifyIORef' (_merge_heightBagRef m) $ heightBagAdd new
      revalidateMergeHeight m
  }

--TODO: Be able to run as much of this as possible promptly
updateMerge :: (GCompare k) => Merge k s -> MergeUpdateFunc k p s -> p -> SomeMergeUpdate
updateMerge m updateFunc p = SomeMergeUpdate updateMe (invalidateMergeHeight m) (revalidateMergeHeight m)
  where updateMe = do
          oldParents <- liftIO $ readIORef $ _merge_parentsRef m
          (subscriptionsToKill, newParents) <- updateFunc (mergeSubscriber m) (_merge_heightBagRef m) oldParents p
          liftIO $ writeIORef (_merge_parentsRef m) $! newParents
          return subscriptionsToKill

{-# inline mergeCheap' #-}
mergeCheap' :: forall k p s. (GCompare k, PatchTarget p ~ DMap k (Event)) => MergeInitFunc k s -> MergeUpdateFunc k p s -> MergeDestroyFunc k s -> Dynamic' p -> Event (DMap k Identity)
mergeCheap' getInitialSubscribers updateFunc destroy d = Event $ \sub -> do
  initialParents <- readBehaviorUntrackedE $ dynamicCurrent d
  accumRef <- liftIO $ newIORef $ error "merge: accumRef not yet initialized"
  heightRef <- liftIO $ newIORef $ error "merge: heightRef not yet initialized"
  heightBagRef <- liftIO $ newIORef $ error "merge: heightBagRef not yet initialized"
  parentsRef :: IORef (DMap k s) <- liftIO $ newIORef $ error "merge: parentsRef not yet initialized"
  let m = Merge
        { _merge_parentsRef = parentsRef
        , _merge_heightBagRef = heightBagRef
        , _merge_heightRef = heightRef
        , _merge_sub = sub
        , _merge_accumRef = accumRef
        }
  (dm, heights, initialParentState) <- getInitialSubscribers initialParents $ mergeSubscriber m
  let myHeightBag = heightBagFromList $ filter (/= invalidHeight) heights
      myHeight = if invalidHeight `elem` heights
                 then invalidHeight
                 else succHeight $ heightBagMax myHeightBag
  currentHeight <- getCurrentHeight
  let (occ, accum') = if currentHeight >= myHeight -- If we should have fired by now
                     then (if DMap.null dm then Nothing else Just dm, DMap.empty)
                     else (Nothing, dm)
  unless (DMap.null accum') $ do
    scheduleMergeSelf m myHeight
  liftIO $ writeIORef accumRef $! accum'
  liftIO $ writeIORef heightRef $! myHeight
  liftIO $ writeIORef heightBagRef $! myHeightBag
  changeSubdRef <- liftIO $ newIORef $ error "getMergeSubscribed: changeSubdRef not yet initialized"
  liftIO $ writeIORef parentsRef $! initialParentState
  defer deferSomeMergeInitEventM $ SomeMergeInit $ do
    let s = Subscriber
          { subscriberPropagate = \a -> {-# SCC "traverseMergeChange" #-} do
              tracePropagate (Proxy :: Proxy x) $ "SubscriberMerge/Change"
              defer deferSomeMergeUpdateEventM $ updateMerge m updateFunc a
          , subscriberInvalidateHeight = \_ -> return ()
          , subscriberRecalculateHeight = \_ -> return ()
          }
    (changeSubscription, change) <- subscribeAndRead (dynamicUpdated d) s
    forM_ change $ \c -> defer deferSomeMergeUpdateEventM $ updateMerge m updateFunc c
    -- We explicitly hold on to the unsubscribe function from subscribing to the update event.
    -- If we don't do this, there are certain cases where mergeCheap will fail to properly retain
    -- its subscription.
    liftIO $ writeIORef changeSubdRef (s, changeSubscription)
  let unsubscribeAll = destroy =<< readIORef parentsRef
  return ( EventSubscription unsubscribeAll $ EventSubscribed heightRef $ toAny (parentsRef, changeSubdRef)
         , occ
         )

mergeInt' :: forall a. Dynamic' (PatchIntMap (Event a)) -> Event (IntMap a)
mergeInt' = cacheEvent . mergeIntCheap

{-# inlinable mergeIntCheap #-}
mergeIntCheap :: forall a. Dynamic' (PatchIntMap (Event a)) -> Event (IntMap a)
mergeIntCheap d = Event $ \sub -> do
  initialParents <- readBehaviorUntrackedE $ dynamicCurrent d
  accum' <- liftIO $ FastMutableIntMap.newEmpty
  heightRef <- liftIO $ newIORef zeroHeight
  heightBagRef <- liftIO $ newIORef heightBagEmpty
  parents <- liftIO $ FastMutableIntMap.newEmpty
  let scheduleSelf = do
        height <- liftIO $ readIORef $ heightRef
        scheduleMerge' height heightRef $ do
          vals <- liftIO $ FastMutableIntMap.getFrozenAndClear accum'
          subscriberPropagate sub vals
      invalidateMyHeight = do
        invalidateMergeHeight' heightRef sub
      recalculateMyHeight = do
        currentHeight <- readIORef heightRef
        when (currentHeight == invalidHeight) $ do --TODO: This will almost always be true; can we get rid of this check and just proceed to the next one always?
          heights <- readIORef heightBagRef
          numParents <- FastMutableIntMap.size parents
          case heightBagSize heights `compare` numParents of
            LT -> return ()
            EQ -> do
              let height = succHeight $ heightBagMax heights
              when debugInvalidateHeight $ putStrLn $ "recalculateSubscriberHeight: height: " <> show height
              writeIORef heightRef $! height
              subscriberRecalculateHeight sub height
            GT -> error $ "revalidateMergeHeight: more heights (" <> show (heightBagSize heights) <> ") than parents (" <> show numParents <> ") for Merge"
      mySubscriber k = Subscriber
        { subscriberPropagate = \a -> do
            wasEmpty <- liftIO $ FastMutableIntMap.isEmpty accum'
            liftIO $ FastMutableIntMap.insert accum' k a
            when wasEmpty scheduleSelf
        , subscriberInvalidateHeight = \old -> do
            modifyIORef' heightBagRef $ heightBagRemove old
            invalidateMyHeight
        , subscriberRecalculateHeight = \new -> do
            modifyIORef' heightBagRef $ heightBagAdd new
            recalculateMyHeight
        }
  forM_ (IntMap.toList initialParents) $ \(k, p) -> do
    (subscription@(EventSubscription _ parentSubd), parentOcc) <- subscribeAndRead p $ mySubscriber k
    liftIO $ do
      forM_ parentOcc $ FastMutableIntMap.insert accum' k
      FastMutableIntMap.insert parents k subscription
      height <- getEventSubscribedHeight parentSubd
      if height == invalidHeight
        then writeIORef heightRef invalidHeight
        else do
          modifyIORef' heightBagRef $ heightBagAdd height
          modifyIORef' heightRef $ \oldHeight ->
            if oldHeight == invalidHeight
            then invalidHeight
            else max (succHeight height) oldHeight
  myHeight <- liftIO $ readIORef heightRef
  currentHeight <- getCurrentHeight
  isEmpty <- liftIO $ FastMutableIntMap.isEmpty accum'
  occ <- if currentHeight >= myHeight -- If we should have fired by now
    then if isEmpty
         then return Nothing
         else liftIO $ Just <$> FastMutableIntMap.getFrozenAndClear accum'
    else do when (not isEmpty) scheduleSelf -- We have things accumulated, but we shouldn't have fired them yet
            return Nothing
  changeSubdRef <- liftIO $ newIORef $ error "getMergeSubscribed: changeSubdRef not yet initialized"
  defer deferSomeMergeInitEventM $ SomeMergeInit $ do
    let updateMe a = SomeMergeUpdate u invalidateMyHeight recalculateMyHeight
          where
            u = do
              let f k newParent = do
                    subscription@(EventSubscription _ subd) <- subscribe newParent $ mySubscriber k
                    newParentHeight <- liftIO $ getEventSubscribedHeight subd
                    liftIO $ modifyIORef' heightBagRef $ heightBagAdd newParentHeight
                    return subscription
              newSubscriptions <- FastMutableIntMap.traverseIntMapPatchWithKey f a
              oldParents <- liftIO $ FastMutableIntMap.applyPatch parents newSubscriptions
              liftIO $ for_ oldParents $ \oldParent -> do
                oldParentHeight <- getEventSubscribedHeight $ _eventSubscription_subscribed oldParent
                modifyIORef' heightBagRef $ heightBagRemove oldParentHeight
              return $ IntMap.elems oldParents
    let s = Subscriber
          { subscriberPropagate = \a -> {-# SCC "traverseMergeChange" #-} do
              tracePropagate (Proxy :: Proxy x) $ "SubscriberMergeInt/Change"
              defer deferSomeMergeUpdateEventM $ updateMe a
          , subscriberInvalidateHeight = const (pure ())
          , subscriberRecalculateHeight = const (pure ())
          }
    (changeSubscription, change) <- subscribeAndRead (dynamicUpdated d) s
    forM_ change $ \c -> defer deferSomeMergeUpdateEventM $ updateMe c
    -- We explicitly hold on to the unsubscribe function from subscribing to the update event.
    -- If we don't do this, there are certain cases where mergeCheap will fail to properly retain
    -- its subscription.
    liftIO $ writeIORef changeSubdRef (s, changeSubscription)
  let unsubscribeAll = traverse_ unsubscribe =<< FastMutableIntMap.getFrozenAndClear parents
  return ( EventSubscription unsubscribeAll $ EventSubscribed heightRef $ toAny (parents, changeSubdRef)
         , occ
         )

runHoldInits :: IORef [SomeHoldInit] -> IORef [SomeDynInit] -> IORef [SomeMergeInit] -> EventM ()
runHoldInits holdInitRef dynInitRef mergeInitRef = do
  holdInits <- liftIO $ readIORef holdInitRef
  dynInits <- liftIO $ readIORef dynInitRef
  mergeInits <- liftIO $ readIORef mergeInitRef
  unless (null holdInits && null dynInits && null mergeInits) $ do
    liftIO $ writeIORef holdInitRef []
    liftIO $ writeIORef dynInitRef []
    liftIO $ writeIORef mergeInitRef []
    mapM_ initHold holdInits
    mapM_ initDyn dynInits
    mapM_ unSomeMergeInit mergeInits
    runHoldInits holdInitRef dynInitRef mergeInitRef

initHold :: SomeHoldInit -> EventM ()
initHold (SomeHoldInit h) = void $ getHoldEventSubscription h

initDyn :: SomeDynInit -> EventM ()
initDyn (SomeDynInit d) = void $ getDynHoldE d

newEventEnv :: IO EventEnv
newEventEnv = do
  toAssignRef <- newIORef [] -- This should only actually get used when events are firing
  holdInitRef <- newIORef []
  dynInitRef <- newIORef []
  mergeUpdateRef <- newIORef []
  mergeInitRef <- newIORef []
  heightRef <- newIORef zeroHeight
  toClearRef <- newIORef []
  toClearIntRef <- newIORef []
  toClearRootRef <- newIORef []
  coincidenceInfosRef <- newIORef []
  delayedRef <- newIORef IntMap.empty
  return $ EventEnv toAssignRef holdInitRef dynInitRef mergeUpdateRef mergeInitRef toClearRef toClearIntRef toClearRootRef heightRef coincidenceInfosRef delayedRef

clearEventEnv :: EventEnv -> IO ()
clearEventEnv (EventEnv toAssignRef holdInitRef dynInitRef mergeUpdateRef mergeInitRef toClearRef toClearIntRef toClearRootRef heightRef coincidenceInfosRef delayedRef) = do
  writeIORef toAssignRef []
  writeIORef holdInitRef []
  writeIORef dynInitRef []
  writeIORef mergeUpdateRef []
  writeIORef mergeInitRef []
  writeIORef heightRef zeroHeight
  writeIORef toClearRef []
  writeIORef toClearIntRef []
  writeIORef toClearRootRef []
  writeIORef coincidenceInfosRef []
  writeIORef delayedRef IntMap.empty

-- | Run an event action outside of a frame
runFrame :: forall a. EventM a -> SpiderHost a --TODO: This function also needs to hold the mutex
runFrame a = SpiderHost $ do
  let env = _spiderTimeline_eventEnv (spiderTimeline :: SpiderTimelineEnv x)
  let go = do
        result <- a
        runHoldInits (eventEnvHoldInits env) (eventEnvDynInits env) (eventEnvMergeInits env) -- This must happen before doing the assignments, in case subscribing a Hold causes existing Holds to be read by the newly-propagated events
        return result
  result <- runEventM go
  toClear <- readIORef $ eventEnvClears env
  forM_ toClear $ \(SomeClear ref) -> {-# SCC "clear" #-} writeIORef ref Nothing
  toClearInt <- readIORef $ eventEnvIntClears env
  forM_ toClearInt $ \(SomeIntClear ref) -> {-# SCC "intClear" #-} writeIORef ref $! IntMap.empty
  toClearRoot <- readIORef $ eventEnvRootClears env
  forM_ toClearRoot $ \(SomeRootClear ref) -> {-# SCC "rootClear" #-} writeIORef ref $! DMap.empty
  toAssign <- readIORef $ eventEnvAssignments env
  toReconnectRef <- newIORef []
  coincidenceInfos <- readIORef $ eventEnvResetCoincidences env
  forM_ toAssign $ \(SomeAssignment vRef iRef v) -> {-# SCC "assignment" #-} do
    writeIORef vRef v
    when debugInvalidate $ putStrLn $ "Invalidating Hold"
    writeIORef iRef =<< evaluate =<< invalidate toReconnectRef =<< readIORef iRef
  mergeUpdates <- readIORef $ eventEnvMergeUpdates env
  writeIORef (eventEnvMergeUpdates env) []
  when debugPropagate $ putStrLn "Updating merges"
  mergeSubscriptionsToKill <- runEventM $ concat <$> mapM _someMergeUpdate_update mergeUpdates
  when debugPropagate $ putStrLn "Updating merges done"
  toReconnect <- readIORef toReconnectRef
  clearEventEnv env
  switchSubscriptionsToKill <- forM toReconnect $ \(SomeSwitchSubscribed subscribed) -> {-# SCC "switchSubscribed" #-} do
    oldSubscription <- readIORef $ switchSubscribedCurrentParent subscribed
    wi <- readIORef $ switchSubscribedOwnWeakInvalidator subscribed
    when debugInvalidate $ putStrLn $ "Finalizing invalidator for Switch" <> showNodeId subscribed
    finalize wi
    i <- evaluate $ switchSubscribedOwnInvalidator subscribed
    wi' <- mkWeakPtrWithDebug i "wi'"
    writeIORef (switchSubscribedOwnWeakInvalidator subscribed) $! wi'
    writeIORef (switchSubscribedBehaviorParents subscribed) []
    writeIORef (eventEnvHoldInits env) [] --TODO: Should we reuse this?
    e <- runBehaviorM (readBehaviorTracked (switchSubscribedParent subscribed)) (Just (wi', switchSubscribedBehaviorParents subscribed)) $ eventEnvHoldInits env
    runEventM $ runHoldInits (eventEnvHoldInits env) (eventEnvDynInits env) (eventEnvMergeInits env) --TODO: Is this actually OK? It seems like it should be, since we know that no events are firing at this point, but it still seems inelegant
    --TODO: Make sure we touch the pieces of the SwitchSubscribed at the appropriate times
    sub <- newSubscriberSwitch subscribed
    subscription <- unSpiderHost $ runFrame $ {-# SCC "subscribeSwitch" #-} subscribe e sub --TODO: Assert that the event isn't firing --TODO: This should not loop because none of the events should be firing, but still, it is inefficient
    {-
    stackTrace <- liftIO $ fmap renderStack $ ccsToStrings =<< (getCCSOf $! switchSubscribedParent subscribed)
    liftIO $ putStrLn $ (++stackTrace) $ "subd' subscribed to " ++ case e of
      EventRoot _ -> "EventRoot"
      EventNever -> "EventNever"
      _ -> "something else"
    -}
    writeIORef (switchSubscribedCurrentParent subscribed) $! subscription
    return oldSubscription
  liftIO $ mapM_ unsubscribe mergeSubscriptionsToKill
  liftIO $ mapM_ unsubscribe switchSubscriptionsToKill
  forM_ toReconnect $ \(SomeSwitchSubscribed subscribed) -> {-# SCC "switchSubscribed" #-} do
    EventSubscription _ subd' <- readIORef $ switchSubscribedCurrentParent subscribed
    parentHeight <- getEventSubscribedHeight subd'
    myHeight <- readIORef $ switchSubscribedHeight subscribed
    when (parentHeight /= myHeight) $ do
      writeIORef (switchSubscribedHeight subscribed) $! invalidHeight
      WeakBag.traverse (switchSubscribedSubscribers subscribed) $ invalidateSubscriberHeight myHeight
  mapM_ _someMergeUpdate_invalidateHeight mergeUpdates --TODO: In addition to when the patch is completely empty, we should also not run this if it has some Nothing values, but none of them have actually had any effect; potentially, we could even check for Just values with no effect (e.g. by comparing their IORefs and ignoring them if they are unchanged); actually, we could just check if the new height is different
  forM_ coincidenceInfos $ \(SomeResetCoincidence subscription mcs) -> do
    unsubscribe subscription
    mapM_ invalidateCoincidenceHeight mcs
  forM_ coincidenceInfos $ \(SomeResetCoincidence _ mcs) -> mapM_ recalculateCoincidenceHeight mcs
  mapM_ _someMergeUpdate_recalculateHeight mergeUpdates
  forM_ toReconnect $ \(SomeSwitchSubscribed subscribed) -> do
    height <- calculateSwitchHeight subscribed
    updateSwitchHeight height subscribed
  return result

{-# inline zeroHeight #-}
zeroHeight :: Height
zeroHeight = Height 0

{-# inline invalidHeight #-}
invalidHeight :: Height
invalidHeight = Height (-1000)

#ifdef DEBUG_CYCLES
-- | An invalid height that is currently being traversed, e.g. by walkInvalidHeightParents
{-# inline invalidHeightBeingTraversed #-}
invalidHeightBeingTraversed :: Height
invalidHeightBeingTraversed = Height (-1001)
#endif

{-# inline succHeight #-}
succHeight :: Height -> Height
succHeight h@(Height a) =
  if h == invalidHeight
  then invalidHeight
  else Height $ succ a

invalidateCoincidenceHeight :: CoincidenceSubscribed a -> IO ()
invalidateCoincidenceHeight subscribed = do
  oldHeight <- readIORef $ coincidenceSubscribedHeight subscribed
  when (oldHeight /= invalidHeight) $ do
    writeIORef (coincidenceSubscribedHeight subscribed) $! invalidHeight
    WeakBag.traverse (coincidenceSubscribedSubscribers subscribed) $ invalidateSubscriberHeight oldHeight

updateSwitchHeight :: Height -> SwitchSubscribed a -> IO ()
updateSwitchHeight new subscribed = do
  oldHeight <- readIORef $ switchSubscribedHeight subscribed
  when (oldHeight == invalidHeight) $ do --TODO: This 'when' should probably be an assertion
    when (new /= invalidHeight) $ do --TODO: This 'when' should probably be an assertion
      writeIORef (switchSubscribedHeight subscribed) $! new
      WeakBag.traverse (switchSubscribedSubscribers subscribed) $ recalculateSubscriberHeight new

recalculateCoincidenceHeight :: CoincidenceSubscribed a -> IO ()
recalculateCoincidenceHeight subscribed = do
  oldHeight <- readIORef $ coincidenceSubscribedHeight subscribed
  when (oldHeight == invalidHeight) $ do --TODO: This 'when' should probably be an assertion
    height <- calculateCoincidenceHeight subscribed
    when (height /= invalidHeight) $ do
      writeIORef (coincidenceSubscribedHeight subscribed) $! height
      WeakBag.traverse (coincidenceSubscribedSubscribers subscribed) $ recalculateSubscriberHeight height

calculateSwitchHeight :: SwitchSubscribed a -> IO Height
calculateSwitchHeight subscribed = getEventSubscribedHeight . _eventSubscription_subscribed =<< readIORef (switchSubscribedCurrentParent subscribed)

calculateCoincidenceHeight :: CoincidenceSubscribed a -> IO Height
calculateCoincidenceHeight subscribed = do
  outerHeight <- getEventSubscribedHeight $ _eventSubscription_subscribed $ coincidenceSubscribedOuterParent subscribed
  innerHeight <- maybe (return zeroHeight) getEventSubscribedHeight =<< readIORef (coincidenceSubscribedInnerParent subscribed)
  return $ if outerHeight == invalidHeight || innerHeight == invalidHeight then invalidHeight else max outerHeight innerHeight

data SomeSwitchSubscribed = forall a. SomeSwitchSubscribed {-# NOUNPACK #-} (SwitchSubscribed a)

invalidate :: IORef [SomeSwitchSubscribed] -> WeakList Invalidator -> IO (WeakList Invalidator)
invalidate toReconnectRef wis = do
  forM_ wis $ \wi -> do
    mi <- deRefWeak wi
    case mi of
      Nothing -> do
        traceInvalidate "invalidate Dead"
        return () --TODO: Should we clean this up here?
      Just i -> do
        finalize wi -- Once something's invalidated, it doesn't need to hang around; this will change when some things are strict
        case i of
          InvalidatorPull p -> do
            traceInvalidate $ "invalidate: Pull" <> showNodeId p
            mVal <- readIORef $ pullValue p
            forM_ mVal $ \val -> do
              writeIORef (pullValue p) Nothing
              writeIORef (pullSubscribedInvalidators val) =<< evaluate =<< invalidate toReconnectRef =<< readIORef (pullSubscribedInvalidators val)
          InvalidatorSwitch subscribed -> do
            traceInvalidate $ "invalidate: Switch" <> showNodeId subscribed
            modifyIORef' toReconnectRef (SomeSwitchSubscribed subscribed :)
  return [] -- Since we always finalize everything, always return an empty list --TODO: There are some things that will need to be re-subscribed every time; we should try to avoid finalizing them

--------------------------------------------------------------------------------
-- Reflex integration
--------------------------------------------------------------------------------

class Monad m => MonadSample m where
  sample :: Behavior a -> m a

{-# inline [1] liftSample #-}
liftSample :: (MonadSample m, MonadTrans t) => Behavior a -> t m a
liftSample = lift . sample

instance MonadSample EventM where
  sample b = readBehaviorUntrackedE b
  {-# inline sample #-}

instance MonadSample PullM where
  sample = coerce . readBehaviorTracked
  {-# inline sample #-}

instance MonadSample PushM where
  sample = PushM . readBehaviorUntrackedE
  {-# inline sample #-}

instance MonadSample m => MonadSample (StateT s m) where
  sample = liftSample
  {-# inline sample #-}

instance MonadSample m => MonadSample (ReaderT r m) where
  sample = liftSample
  {-# inline sample #-}

instance MonadSample m => MonadSample (ExceptT e m) where
  sample = liftSample
  {-# inline sample #-}

instance (MonadSample m, Monoid w) => MonadSample (WriterT w m) where
  sample = liftSample
  {-# inline sample #-}

instance (MonadSample m, Monoid w) => MonadSample (RWST r w s m) where
  sample = liftSample
  {-# inline sample #-}

instance MonadSample m => MonadSample (ContT r m) where
  sample = liftSample
  {-# inline sample #-}

liftHold :: (MonadHold m, MonadTrans t) => a -> Event a -> t m (Behavior a)
liftHold a0 = lift . hold a0
{-# inline [1] liftHold #-}

liftHoldDyn :: (MonadHold m, MonadTrans t) => a -> Event a -> t m (Dynamic a)
liftHoldDyn a0 = lift . holdDyn a0
{-# inline [1] liftHoldDyn #-}

liftHoldIncremental :: (MonadHold m, MonadTrans t, Patch p) => PatchTarget p -> Event p -> t m (Incremental p)
liftHoldIncremental a0 = lift . holdIncremental a0
{-# inline [1] liftHoldIncremental #-}

liftBuildDynamic:: (MonadHold m, MonadTrans t) => PushM a -> Event a -> t m (Dynamic a)
liftBuildDynamic a0 = lift . buildDynamic a0
{-# inline [1] liftBuildDynamic #-}

liftHeadE :: (MonadHold m, MonadTrans t) => Event a -> t m (Event a)
liftHeadE = lift . headE
{-# inline [1] liftHeadE #-}

class MonadSample m => MonadHold m where
  hold :: a -> Event a -> m (Behavior a)
  holdDyn :: a -> Event a -> m (Dynamic a)
  holdIncremental :: Patch p => PatchTarget p -> Event p -> m (Incremental p)
  buildDynamic :: PushM a -> Event a -> m (Dynamic a)
  headE :: Event a -> m (Event a)

instance MonadHold m => MonadHold (ReaderT r m) where
  hold = liftHold
  holdDyn = liftHoldDyn
  holdIncremental = liftHoldIncremental
  buildDynamic = liftBuildDynamic
  headE = liftHeadE
  {-# inline hold #-}
  {-# inline holdDyn #-}
  {-# inline holdIncremental #-}
  {-# inline buildDynamic #-}
  {-# inline headE #-}

instance (MonadHold m, Monoid w) => MonadHold (WriterT w m) where
  hold = liftHold
  holdDyn = liftHoldDyn
  holdIncremental = liftHoldIncremental
  buildDynamic = liftBuildDynamic
  headE = liftHeadE
  {-# inline hold #-}
  {-# inline holdDyn #-}
  {-# inline holdIncremental #-}
  {-# inline buildDynamic #-}
  {-# inline headE #-}

instance MonadHold m => MonadHold (StateT s m) where
  hold = liftHold
  holdDyn = liftHoldDyn
  holdIncremental = liftHoldIncremental
  buildDynamic = liftBuildDynamic
  headE = liftHeadE
  {-# inline hold #-}
  {-# inline holdDyn #-}
  {-# inline holdIncremental #-}
  {-# inline buildDynamic #-}
  {-# inline headE #-}

instance MonadHold m => MonadHold (ExceptT e m) where
  hold = liftHold
  holdDyn = liftHoldDyn
  holdIncremental = liftHoldIncremental
  buildDynamic = liftBuildDynamic
  headE = liftHeadE
  {-# inline hold #-}
  {-# inline holdDyn #-}
  {-# inline holdIncremental #-}
  {-# inline buildDynamic #-}
  {-# inline headE #-}

instance (MonadHold m, Monoid w) => MonadHold (RWST r w s m) where
  hold = liftHold
  holdDyn = liftHoldDyn
  holdIncremental = liftHoldIncremental
  buildDynamic = liftBuildDynamic
  headE = liftHeadE
  {-# inline hold #-}
  {-# inline holdDyn #-}
  {-# inline holdIncremental #-}
  {-# inline buildDynamic #-}
  {-# inline headE #-}

instance MonadHold m => MonadHold (ContT r m) where
  hold = liftHold
  holdDyn = liftHoldDyn
  holdIncremental = liftHoldIncremental
  buildDynamic = liftBuildDynamic
  headE = liftHeadE
  {-# inline hold #-}
  {-# inline holdDyn #-}
  {-# inline holdIncremental #-}
  {-# inline buildDynamic #-}
  {-# inline headE #-}

instance MonadHold EventM where
  hold = holdEventM
  holdDyn = holdDynEventM
  holdIncremental = holdIncrementalEventM
  buildDynamic = buildDynamicEventM
  headE = headE

{-# inlinable newJoinDyn #-}
newJoinDyn :: Dynamic' (Identity (Dynamic' (Identity a))) -> Dyn (Identity a)
newJoinDyn d =
  let readV0 = readBehaviorTracked . dynamicCurrent =<< readBehaviorTracked (dynamicCurrent d)
      eOuter = push' (fmap (Just . Identity) . readBehaviorUntrackedE . dynamicCurrent . runIdentity) $ dynamicUpdated d
      eInner = switch $ dynamicUpdated <$> dynamicCurrent d
      eBoth = coincidence $ dynamicUpdated . runIdentity <$> dynamicUpdated d
      v' = leftmost $ [eBoth, eOuter, eInner]
      in unsafeBuildDynamic' readV0 v'

instance Semigroup a => Semigroup (Dynamic a) where
  (<>) = zipDynWith (<>)
  stimes n = fmap $ stimes n

instance Monoid a => Monoid (Dynamic a) where
  mempty = constDyn mempty
  mappend = zipDynWith mappend
-- mconcat = distributeListOverDynWith mconcat

instance Functor Dynamic where
  fmap = mapDynamic
  {-# inline fmap #-} 
  x <$ d = unsafeBuildDynamic (pure x) $ x <$ updated d

mapDynamic :: (a -> b) -> Dynamic a -> Dynamic b
mapDynamic f = Dynamic . newMapDyn f . unDynamic
{-# inline [1] mapDynamic #-}

-- {-# RULES "mapDynamic/coerce" [1] mapDynamic coerce = coerce #-}
-- This rule triggers a warning which cannot be silenced.

instance Applicative Dynamic where
  pure = Dynamic . dynamicConst'
  liftA2 f a b = zipDynWith f a b
  a <*> b = zipDynWith ($) a b
  a *> b = unsafeBuildDynamic (sample $ current b) $ leftmost [updated b, tag (current b) $ updated a]
  (<*) = flip (*>) -- There are no effects, so order doesn't matter

instance Monad Dynamic where
  return = pure
  x >>= f = Dynamic $ dynamicDynIdentity' $ newJoinDyn $ newMapDyn (unDynamic . f) $ unDynamic x
  (>>) = (*>)

holdEventM :: a -> Event a -> EventM (Behavior a)
holdEventM v0 e = fmap behaviorHoldIdentity $ holdE v0 $ coerce e

holdDynEventM :: a -> Event a -> EventM (Dynamic a)
holdDynEventM v0 e = fmap (Dynamic . dynamicHoldIdentity') $ holdE v0 $ coerce e

holdIncrementalEventM :: Patch p => PatchTarget p -> Event p -> EventM (Incremental p)
holdIncrementalEventM v0 e = fmap (Incremental . dynamicHold')
  $ holdE v0
  $ e

buildDynamicEventM :: PushM a -> Event a -> EventM (Dynamic a)
buildDynamicEventM getV0 e = fmap (Dynamic . dynamicDynIdentity') $ buildDynamic' (coerce getV0) $ coerce e

unsafeNewSpiderTimelineEnv :: IO (SpiderTimelineEnv x)
unsafeNewSpiderTimelineEnv = do
  lock <- newMVar ()
  env <- newEventEnv
#ifdef DEBUG
  depthRef <- newIORef 0
#endif
  return $ SpiderTimelineEnv
    { _spiderTimeline_lock = lock
    , _spiderTimeline_eventEnv = env
#ifdef DEBUG
    , _spiderTimeline_depth = depthRef
#endif
    }

-- | Create a new SpiderTimelineEnv
newSpiderTimeline :: IO (Some SpiderTimelineEnv)
newSpiderTimeline = withSpiderTimeline (pure . Some.This)

data LocalSpiderTimeline x s

localSpiderTimeline
  :: Proxy s
  -> SpiderTimelineEnv x
  -> SpiderTimelineEnv (LocalSpiderTimeline x s)
localSpiderTimeline _ = unsafeCoerce

-- | Pass a new timeline to the given function.
withSpiderTimeline :: (forall x. SpiderTimelineEnv x -> IO r) -> IO r
withSpiderTimeline k = do
  env <- unsafeNewSpiderTimelineEnv
  reify env $ \s -> k $ localSpiderTimeline s env

newtype PullM a = PullM (BehaviorM a) deriving (Functor, Applicative, Monad, MonadIO, MonadFix)

newtype PushM a = PushM (EventM a) deriving (Functor, Applicative, Monad, MonadIO, MonadFix,MonadHold)

newtype Incremental a = Incremental { unIncremental :: Dynamic' a }

never :: Event a
never = Event $ const $ pure (EventSubscription (pure ()) eventSubscribedNever, Nothing)

constant :: a -> Behavior a
constant = behaviorConst

push :: (a -> PushM (Maybe b)) -> Event a -> Event b
push f = push' (coerce f)

pushCheap :: (a -> PushM (Maybe b)) -> Event a -> Event b
pushCheap f = pushCheap' (coerce f)

pull :: PullM a -> Behavior a
pull = pull' . coerce

merge :: GCompare k => DMap k Event -> Event (DMap k Identity)
merge = merge' . dynamicConst'

fan :: GCompare k => Event (DMap k Identity) -> EventSelector k
fan e =
  let f = Fan
        { fanParent = e
        , fanSubscribed = unsafeNewIORef e Nothing
        }
  in EventSelector $ \k -> eventFan k f

{-# inlinable switch #-}
switch :: Behavior (Event a) -> Event a
switch a = eventSwitch $ Switch
  { switchParent = a
  , switchSubscribed = unsafeNewIORef a Nothing
  }

coincidence :: Event (Event a) -> Event a
coincidence a = eventCoincidence $ Coincidence
  { coincidenceParent = a
  , coincidenceSubscribed = unsafeNewIORef a Nothing
  }

current :: Dynamic a -> Behavior a
current = dynamicCurrent . coerce

updated :: Dynamic a -> Event a
updated = coerce . dynamicUpdated . unDynamic

unsafeBuildDynamic :: PullM a -> Event a -> Dynamic a
unsafeBuildDynamic readV0 v' = Dynamic $ dynamicDynIdentity' $ unsafeBuildDynamic' (coerce readV0) $ coerce v'

unsafeBuildIncremental :: Patch p => PullM (PatchTarget p) -> Event p -> Incremental p
unsafeBuildIncremental readV0 dv = Incremental $ dynamicDyn' $ unsafeBuildDynamic' (unsafeCoerce readV0) (coerce dv)

mergeIncremental :: GCompare k => Incremental (PatchDMap k Event) -> Event (DMap k Identity)
mergeIncremental = merge' . unIncremental

mergeIncrementalWithMove :: GCompare k => Incremental (PatchDMapWithMove k Event) -> Event (DMap k Identity)
mergeIncrementalWithMove = mergeWithMove . unIncremental

currentIncremental :: Incremental p -> Behavior (PatchTarget p)
currentIncremental = dynamicCurrent . unIncremental

updatedIncremental :: Incremental p -> Event p
updatedIncremental = dynamicUpdated . unIncremental

incrementalToDynamic :: Patch p => Incremental p -> Dynamic (PatchTarget p)
incrementalToDynamic (Incremental i) = Dynamic
  $ dynamicDynIdentity'
  $ unsafeBuildDynamic' (readBehaviorUntrackedB $ dynamicCurrent i)
  $ flip push (dynamicUpdated i) $ \p -> do
      c <- coerce $ readBehaviorUntrackedE $ dynamicCurrent i
      pure $ Identity <$> apply p c

behaviorCoercion :: Coercion a b -> Coercion (Behavior a) (Behavior b)
behaviorCoercion Coercion = Coercion

eventCoercion :: Coercion a b -> Coercion (Event a) (Event b)
eventCoercion Coercion = Coercion

dynamicCoercion :: Coercion a b -> Coercion (Dynamic a) (Dynamic b)
dynamicCoercion = unsafeCoerce

coerceBehavior :: Coercible a b => Behavior a -> Behavior b
coerceBehavior = coerceWith $ behaviorCoercion Coercion

coerceEvent :: Coercible a b => Event a -> Event b
coerceEvent = coerceWith $ eventCoercion Coercion

coerceDynamic :: Coercible a b => Dynamic a -> Dynamic b
coerceDynamic = coerceWith $ dynamicCoercion Coercion

mergeIntIncremental :: Incremental (PatchIntMap (Event a)) -> Event (IntMap a)
mergeIntIncremental = mergeInt' . unIncremental

fanInt :: Event (IntMap a) -> EventSelectorInt a
fanInt p =
  let self = unsafeNewFanInt p
  in EventSelectorInt $ \k -> Event $ \sub -> do
    isEmpty <- liftIO $ FastMutableIntMap.isEmpty (_fanInt_subscribers self)
    when isEmpty $ do -- This is the first subscriber, so we need to subscribe to our input
      (subscription, parentOcc) <- subscribeAndRead p $ Subscriber
        { subscriberPropagate = \m -> do
            liftIO $ writeIORef (_fanInt_occRef self) m
            scheduleIntClear $ _fanInt_occRef self
            FastMutableIntMap.forIntersectionWithImmutable_ (_fanInt_subscribers self) m $ \b v -> do --TODO: Do we need to know that no subscribers are being added as we traverse?
              FastWeakBag.traverse b $ \s -> do
                subscriberPropagate s v
        , subscriberInvalidateHeight = \old -> do
            FastMutableIntMap.for_ (_fanInt_subscribers self) $ \b -> do
              FastWeakBag.traverse b $ \s -> do
                subscriberInvalidateHeight s old
        , subscriberRecalculateHeight = \new -> do
            FastMutableIntMap.for_ (_fanInt_subscribers self) $ \b -> do
              FastWeakBag.traverse b $ \s -> do
                subscriberRecalculateHeight s new
        }
      liftIO $ do
        writeIORef (_fanInt_subscriptionRef self) subscription
        writeIORef (_fanInt_occRef self) $ fromMaybe IntMap.empty parentOcc
      scheduleIntClear $ _fanInt_occRef self
    liftIO $ do
      b <- FastMutableIntMap.lookup (_fanInt_subscribers self) k >>= \case
        Nothing -> do
          b <- FastWeakBag.empty
          FastMutableIntMap.insert (_fanInt_subscribers self) k b
          return b
        Just b -> return b
      t <- liftIO $ FastWeakBag.insert sub b
      currentOcc <- readIORef (_fanInt_occRef self)
      (EventSubscription _ (EventSubscribed !heightRef _)) <- readIORef (_fanInt_subscriptionRef self)
      return (EventSubscription (FastWeakBag.remove t) $! EventSubscribed heightRef $! toAny (_fanInt_subscriptionRef self, t), IntMap.lookup k currentOcc)

pull' :: BehaviorM a -> Behavior a
pull' a = behaviorPull $ Pull
  { pullCompute = a
  , pullValue = unsafeNewIORef a Nothing
#ifdef DEBUG_NODEIDS
  , pullNodeId = unsafeNodeId a
#endif
  }

newtype EventSelector k = EventSelector { select :: forall x. k x -> Event x }

data EventTrigger a = forall k. GCompare k => EventTrigger (WeakBag (Subscriber a), IORef (DMap k Identity), k a)

data EventHandle a = EventHandle
  { eventHandleSubscription :: EventSubscription
  , eventHandleValue :: IORef (Maybe a)
  }

instance MonadRef EventM where
  type Ref (EventM) = Ref IO
  {-# inlinable newRef #-}
  {-# inlinable readRef #-}
  {-# inlinable writeRef #-}
  newRef = liftIO . newRef
  readRef = liftIO . readRef
  writeRef r a = liftIO $ writeRef r a

instance MonadAtomicRef (EventM) where
  {-# inlinable atomicModifyRef #-}
  atomicModifyRef r f = liftIO $ atomicModifyRef r f

-- | The monad for actions that manipulate a Spider timeline identified by @x@
newtype SpiderHost a = SpiderHost { unSpiderHost :: IO a }
  deriving (Functor, Applicative, MonadFix, MonadIO, MonadException, MonadAsyncException)

newtype SpiderHostFrame a = SpiderHostFrame { runSpiderHostFrame :: EventM a }
  deriving (Functor,Applicative,MonadFix,MonadIO,MonadException,MonadAsyncException)

instance Monad SpiderHostFrame where
  SpiderHostFrame x >>= f = SpiderHostFrame $ x >>= runSpiderHostFrame . f
  SpiderHostFrame x >> SpiderHostFrame y = SpiderHostFrame $ x >> y
  return = pure

instance Monad SpiderHost where
  {-# inlinable (>>=) #-}
  SpiderHost x >>= f = SpiderHost $ x >>= unSpiderHost . f
  {-# inlinable (>>) #-}
  SpiderHost x >> SpiderHost y = SpiderHost $ x >> y
  {-# inlinable return #-}
  return x = SpiderHost $ return x
  {-# inlinable fail #-}
  fail s = SpiderHost $ fail s

-- | Run an action affecting the global Spider timeline; this will be guarded by
-- a mutex for that timeline
runSpiderHost :: SpiderHost a -> IO a
runSpiderHost (SpiderHost a) = a

-- | Run an action affecting a given Spider timeline; this will be guarded by a
-- mutex for that timeline
runSpiderHostForTimeline :: SpiderHost a -> SpiderTimelineEnv x -> IO a
runSpiderHostForTimeline (SpiderHost a) _ = a

newEventWithTriggerIO :: (EventTrigger a -> IO (IO ())) -> IO (Event a)
newEventWithTriggerIO f = do
  es <- newFanEventWithTriggerIO $ \Refl -> f
  return $ select es Refl

newFanEventWithTriggerIO :: GCompare k => (forall a. k a -> EventTrigger a -> IO (IO ())) -> IO (EventSelector k)
newFanEventWithTriggerIO f = do
  occRef <- newIORef DMap.empty
  subscribedRef <- newIORef DMap.empty
  let !r = Root
        { rootOccurrence = occRef
        , rootSubscribed = subscribedRef
        , rootInit = f
        }
  return $ EventSelector $ \k -> eventRoot k r

instance MonadRef SpiderHost where
  type Ref (SpiderHost) = Ref IO
  newRef = SpiderHost . newRef
  readRef = SpiderHost . readRef
  writeRef r = SpiderHost . writeRef r

instance MonadAtomicRef SpiderHost where
  atomicModifyRef r = SpiderHost . atomicModifyRef r

instance Default a => Default (Dynamic a) where
  def = pure def

pushAlways :: (a -> PushM b) -> Event a -> Event b
pushAlways f = push (fmap Just . f)

mergeInt :: IntMap (Event a) -> Event (IntMap a)
mergeInt m = mergeIntIncremental $ unsafeBuildIncremental (pure m) never

mergeWith' :: (a -> b) -> (b -> b -> b) -> [Event a] -> Event b
mergeWith' f g es = fmap (foldl1 g . fmap f)
  . mergeInt
  . IntMap.fromDistinctAscList
  $ zip [0 :: Int ..] es

mergeWith :: (a -> a -> a) -> [Event a] -> Event a
mergeWith = mergeWith' id

leftmost :: [Event a] -> Event a
leftmost = mergeWith const

mergeList :: [Event a] -> Event (NonEmpty a)
mergeList = \case
  [] -> never
  es -> mergeWithFoldCheap' id es

mergeWithFoldCheap' :: (NonEmpty a -> b) -> [Event a] -> Event b
mergeWithFoldCheap' f es =
  fmapCheap (f . (\(h : t) -> h :| t) . IntMap.elems)
  . mergeInt
  . IntMap.fromDistinctAscList
  $ zip [0 :: Int .. ] es

splitF :: Functor f => f (a,b) -> (f a, f b)
splitF e = (fmap fst e, fmap snd e)

splitE :: Event (a,b) -> (Event a, Event b)
splitE = splitF

ffor :: Functor f => f a -> (a -> b) -> f b
ffor = flip fmap

fmapCheap :: (a -> b) -> Event a -> Event b
fmapCheap f = pushCheap $ pure . Just . f

fforCheap :: Event a -> (a -> b) -> Event b
fforCheap = flip fmapCheap

tagCheap :: Behavior b -> Event a -> Event b
tagCheap b = pushAlwaysCheap $ const (sample b)

pushAlwaysCheap :: (a -> PushM b) -> Event a -> Event b
pushAlwaysCheap f = pushCheap (fmap Just . f)

constDyn :: a -> Dynamic a
constDyn = pure

unsafeDynamic :: Behavior a -> Event a -> Dynamic a
unsafeDynamic = unsafeBuildDynamic . sample

traceEvent :: Show a => String -> Event a -> Event a
traceEvent s = traceEventWith $ \x -> s <> ": " <> show x

traceEventWith :: (a -> String) -> Event a -> Event a
traceEventWith f = push $ \x -> trace (f x) $ pure $ Just x

switcher :: MonadHold m => Behavior a -> Event (Behavior a) -> m (Behavior a)
switcher b eb = pull . (sample <=< sample) <$> hold b eb

gate :: Behavior Bool -> Event a -> Event a
gate = attachWithMaybe $ \allow a -> if allow then Just a else Nothing

distributeDMapOverDynPure :: forall k. (GCompare k) => DMap k Dynamic -> Dynamic (DMap k Identity)
distributeDMapOverDynPure dm = case DMap.toList dm of
  [] -> constDyn DMap.empty
  [k :=> v] -> fmap (DMap.singleton k . Identity) v
  _ ->
    let getInitial = DMap.traverseWithKey (const (fmap Identity . sample . current)) dm
        edmPre = merge $ DMap.map updated dm
        result = unsafeBuildDynamic getInitial $ flip pushAlways edmPre $ \news -> do
          olds <- sample $ current result
          pure $ DMap.unionWithKey (\_ _ new -> new) olds news
    in result

distributeListOverDyn :: [Dynamic a] -> Dynamic [a]
distributeListOverDyn = distributeListOverDynWith id

distributeListOverDynWith :: ([a] -> b) -> [Dynamic a] -> Dynamic b
distributeListOverDynWith f = fmap (f . map (\(Const2 _ :=> Identity v) -> v) . DMap.toList) . distributeDMapOverDynPure . DMap.fromList . map (\(k,v) -> Const2 k :=> v) . zip [0 :: Int ..]

alignEventWithMaybe :: (These a b -> Maybe c) -> Event a -> Event b -> Event c
alignEventWithMaybe f ea eb = fmapMaybe (f <=< dmapToThese)
  $ merge
  $ DMap.fromList [LeftTag :=> ea, RightTag :=> eb]

difference :: Event a -> Event b -> Event a
difference = alignEventWithMaybe $ \case { This a -> Just a; _ -> Nothing }

mergeMap :: Ord k => Map k (Event a) -> Event (Map k a)
mergeMap = fmap dmapToMap . merge . mapWithFunctorToDMap

mergeIntMap :: IntMap (Event a) -> Event (IntMap a)
mergeIntMap = fmap dmapToIntMap . merge . intMapWithFunctorToDMap

mergeMapIncremental :: Ord k => Incremental (PatchMap k (Event a)) -> Event (Map k a)
mergeMapIncremental = fmap dmapToMap . mergeIncremental . unsafeMapIncremental mapWithFunctorToDMap (const2PatchDMapWith id)

mergeIntMapIncremental :: Incremental (PatchIntMap (Event a)) -> Event (IntMap a)
mergeIntMapIncremental = fmap dmapToIntMap . mergeIncremental . unsafeMapIncremental intMapWithFunctorToDMap (const2IntPatchDMapWith id)

unsafeMapIncremental :: (Patch p, Patch p') => (PatchTarget p -> PatchTarget p') -> (p -> p') -> Incremental p -> Incremental p'
unsafeMapIncremental f g a = unsafeBuildIncremental (fmap f $ sample $ currentIncremental a) $ g <$> updatedIncremental a

mergeMapIncrementalWithMove :: Ord k => Incremental (PatchMapWithMove k (Event a)) -> Event (Map k a)
mergeMapIncrementalWithMove = fmap dmapToMap . mergeIncrementalWithMove . unsafeMapIncremental mapWithFunctorToDMap (const2PatchDMapWithMoveWith id)

fanEither :: Event (Either a b) -> (Event a, Event b)
fanEither e =
  let justLeft = either Just (const Nothing)
      justRight = either (const Nothing) Just
  in (fmapMaybe justLeft e, fmapMaybe justRight e)

fanThese :: Event (These a b) -> (Event a, Event b)
fanThese e =
  let this = \case
        This x -> Just x
        These x _ -> Just x
        _ -> Nothing
      that = \case
        That y -> Just y
        These _ y -> Just y
        _ -> Nothing
  in (fmapMaybe this e, fmapMaybe that e)

fanMap :: Ord k => Event (Map k a) -> EventSelector (Const2 k a)
fanMap = fan . fmap mapToDMap

switchHold :: MonadHold m => Event a -> Event (Event a) -> m (Event a)
switchHold ea0 eea = switch <$> hold ea0 eea

switchHoldPromptly :: MonadHold m => Event a -> Event (Event a) -> m (Event a)
switchHoldPromptly ea0 eea = do
  bea <- hold ea0 eea
  let eLag = switch bea
      eCoincidences = coincidence eea
  pure $ leftmost [eCoincidences, eLag]

switchHoldPromptOnly :: MonadHold m => Event a -> Event (Event a) -> m (Event a)
switchHoldPromptOnly e0 e' = do
  eLag <- switch <$> hold e0 e'
  pure $ coincidence $ leftmost [e', eLag <$ eLag]

coincidencePatchMap :: Ord k => Event (PatchMap k (Event v)) -> Event (PatchMap k v)
coincidencePatchMap e = fmapCheap PatchMap $ coincidence $ ffor e $ \(PatchMap m) -> mergeMap $ ffor m $ \case
  Nothing -> fmapCheap (const Nothing) e
  Just ev -> leftmost [fmapCheap Just ev, fmapCheap (const Nothing) e]

coincidencePatchIntMap :: Event (PatchIntMap (Event v)) -> Event (PatchIntMap v)
coincidencePatchIntMap e = fmapCheap PatchIntMap $ coincidence $ ffor e $ \(PatchIntMap m) -> mergeIntMap $ ffor m $ \case
  Nothing -> fmapCheap (const Nothing) e
  Just ev -> leftmost [fmapCheap Just ev, fmapCheap (const Nothing) e]

coincidencePatchMapWithMove :: Ord k => Event (PatchMapWithMove k (Event v)) -> Event (PatchMapWithMove k v)
coincidencePatchMapWithMove e = fmapCheap PatchMapWithMove.unsafePatchMapWithMove
  $ coincidence
  $ ffor e
  $ \p -> mergeMap
  $ ffor (PatchMapWithMove.unPatchMapWithMove p)
  $ \ni -> case PatchMapWithMove._nodeInfo_from ni of
    PatchMapWithMove.From_Delete -> fforCheap e $ const $
      ni { PatchMapWithMove._nodeInfo_from = PatchMapWithMove.From_Delete }
    PatchMapWithMove.From_Move k -> fforCheap e $ const $
      ni { PatchMapWithMove._nodeInfo_from = PatchMapWithMove.From_Move k }
    PatchMapWithMove.From_Insert ev -> leftmost
      [ fforCheap ev $ \v ->
          ni { PatchMapWithMove._nodeInfo_from = PatchMapWithMove.From_Insert v }
      , fforCheap e $ const $
          ni { PatchMapWithMove._nodeInfo_from = PatchMapWithMove.From_Delete }
      ]

switchHoldPromptOnlyIncremental :: forall m p pt w.
  ( MonadHold m
  , Patch (p (Event w))
  , PatchTarget (p (Event w)) ~ pt (Event w)
  , Patch (p w)
  , PatchTarget (p w) ~ pt w
  , Monoid (pt w)
  )
  => (Incremental (p (Event w)) -> Event (pt w))
  -> (Event (p (Event w)) -> Event (p w))
  -> pt (Event w)
  -> Event (p (Event w))
  -> m (Event (pt w))
switchHoldPromptOnlyIncremental mergePatchIncremental coincidencePatch e0 e' = do
  lag <- mergePatchIncremental <$> holdIncremental e0 e'
  pure $ ffor (align lag (coincidencePatch e')) $ \case
    This old -> old
    That new -> new `applyAlways` mempty
    These old new -> new `applyAlways` old

takeWhileJustE :: forall m a b.
  ( MonadFix m
  , MonadHold m
  )
  => (a -> Maybe b)
  -> Event a
  -> m (Event b)
takeWhileJustE f e = do
  rec let (eBad,eTrue) = fanEither $ ffor e' $ \a -> case f a of
            Nothing -> Left never
            Just b -> Right b
      eFirstBad <- headE eBad
      e' <- switchHold e eFirstBad
  pure eTrue

filterEventKey :: forall m k v a.
  ( MonadFix m
  , MonadHold m
  , GEq k
  )
  => k a
  -> Event (DSum k v)
  -> m (Event (v a))
filterEventKey k kv' = do
  let f :: DSum k v -> Maybe (v a)
      f (newK :=> newV) = case newK `geq` k of
        Just Refl -> Just newV
        Nothing -> Nothing
  takeWhileJustE f kv'
 
factorEvent :: forall m k v a.
  ( MonadFix m
  , MonadHold m
  , GEq k
  )
  => k a
  -> Event (DSum k v)
  -> m (Event (v a), Event (DSum k (Product v (Compose Event v))))
factorEvent k0 kv' = do
  key :: Behavior (Some k) <- hold (Some.This k0) $ fmapCheap (\(k :=> _) -> Some.This k) kv'
  let update = flip push kv' $ \(newKey :=> newVal) -> sample key >>= \case
        Some.This oldKey -> case newKey `geq` oldKey of
          Just Refl -> pure Nothing
          Nothing -> do
            newInner <- filterEventKey newKey kv'
            pure $ Just $ newKey :=> Pair newVal (Compose newInner)
  eInitial <- filterEventKey k0 kv'
  pure (eInitial,update)

class Accumulator f where
  {-# minimal (accumMaybeM, mapAccumMaybeM) #-}
  accum :: (MonadHold m, MonadFix m) => (a -> b -> a) -> a -> Event b -> m (f a)
  accum f = accumMaybe $ \v o -> Just $ f v o
  accumM :: (MonadHold m, MonadFix m) => (a -> b -> PushM a) -> a -> Event b -> m (f a)
  accumM f = accumMaybeM $ \v o -> Just <$> f v o
  accumMaybe :: (MonadHold m, MonadFix m) => (a -> b -> Maybe a) -> a -> Event b -> m (f a)
  accumMaybe f = accumMaybeM $ \v o -> pure $ f v o
  accumMaybeM :: (MonadHold m, MonadFix m) => (a -> b -> PushM (Maybe a)) -> a -> Event b -> m (f a)
  mapAccum :: (MonadHold m, MonadFix m) => (a -> b -> (a,c)) -> a -> Event b -> m (f a, Event c)
  mapAccum f = mapAccumMaybe $ \v o -> bimap Just Just $ f v o
  mapAccumM :: (MonadHold m, MonadFix m) => (a -> b -> PushM (a, c)) -> a -> Event b -> m (f a, Event c)
  mapAccumM f = mapAccumMaybeM $ \v o -> bimap Just Just <$> f v o
  mapAccumMaybe :: (MonadHold m, MonadFix m) => (a -> b -> (Maybe a, Maybe c)) -> a -> Event b -> m (f a, Event c)
  mapAccumMaybe f = mapAccumMaybeM $ \v o -> pure $ f v o
  mapAccumMaybeM :: (MonadHold m, MonadFix m) => (a -> b -> PushM (Maybe a, Maybe c)) -> a -> Event b -> m (f a, Event c)

accumDyn :: (MonadHold m, MonadFix m) => (a -> b -> a) -> a -> Event b -> m (Dynamic a)
accumDyn f = accumMaybeDyn $ \v o -> Just $ f v o

accumMDyn :: (MonadHold m, MonadFix m) => (a -> b -> PushM a) -> a -> Event b -> m (Dynamic a)
accumMDyn f = accumMaybeMDyn $ \v o -> Just <$> f v o

accumMaybeDyn :: (MonadHold m, MonadFix m) => (a -> b -> Maybe a) -> a -> Event b -> m (Dynamic a)
accumMaybeDyn f = accumMaybeMDyn $ \v o -> pure $ f v o

accumMaybeMDyn :: (MonadHold m, MonadFix m) => (a -> b -> PushM (Maybe a)) -> a -> Event b -> m (Dynamic a)
accumMaybeMDyn f z e = do
  rec let e' = flip push e $ \o -> do
            v <- sample $ current d'
            f v o
      d' <- holdDyn z e'
  pure d'

mapAccumDyn :: (MonadHold m, MonadFix m) => (a -> b -> (a,c)) -> a -> Event b -> m (Dynamic a, Event c)
mapAccumDyn f = mapAccumMaybeDyn $ \v o -> bimap Just Just $ f v o

mapAccumMDyn :: (MonadHold m, MonadFix m) => (a -> b -> PushM (a,c)) -> a -> Event b -> m (Dynamic a, Event c)
mapAccumMDyn f = mapAccumMaybeMDyn $ \v o -> bimap Just Just <$> f v o

mapAccumMaybeDyn :: (MonadHold m, MonadFix m) => (a -> b -> (Maybe a, Maybe c)) -> a -> Event b -> m (Dynamic a, Event c)
mapAccumMaybeDyn f = mapAccumMaybeMDyn $ \v o -> pure $ f v o

mapAccumMaybeMDyn :: (MonadHold m, MonadFix m) => (a -> b -> PushM (Maybe a, Maybe c)) -> a -> Event b -> m (Dynamic a, Event c)
mapAccumMaybeMDyn f z e = do
  rec let e' = flip push e $ \o -> do
            v <- sample $ current d'
            result <- f v o
            pure $ case result of
              (Nothing, Nothing) -> Nothing
              _ -> Just result
      d' <- holdDyn z $ fmapMaybe fst e'
  pure (d', fmapMaybe snd e')

accumB :: (MonadHold m, MonadFix m) => (a -> b -> a) -> a -> Event b -> m (Behavior a)
accumB f = accumMaybeB $ \v o -> Just $ f v o

accumMB :: (MonadHold m, MonadFix m) => (a -> b -> PushM a) -> a -> Event b -> m (Behavior a)
accumMB f = accumMaybeMB $ \v o -> Just <$> f v o

accumMaybeB :: (MonadHold m, MonadFix m) => (a -> b -> Maybe a) -> a -> Event b -> m (Behavior a)
accumMaybeB f = accumMaybeMB $ \v o -> pure $ f v o

accumMaybeMB :: (MonadHold m, MonadFix m) => (a -> b -> PushM (Maybe a)) -> a -> Event b -> m (Behavior a)
accumMaybeMB f z e = do
  rec let e' = flip push e $ \o -> do
            v <- sample d'
            f v o
      d' <- hold z e'
  pure d'

mapAccumB :: (MonadHold m, MonadFix m) => (a -> b -> (a,c)) -> a -> Event b -> m (Behavior a, Event c)
mapAccumB f = mapAccumMaybeB $ \v o -> bimap Just Just $ f v o

mapAccumMB :: (MonadHold m, MonadFix m) => (a -> b -> PushM (a,c)) -> a -> Event b -> m (Behavior a, Event c)
mapAccumMB f = mapAccumMaybeMB $ \v o -> bimap Just Just <$> f v o

mapAccumMaybeB :: (MonadHold m, MonadFix m) => (a -> b -> (Maybe a, Maybe c)) -> a -> Event b -> m (Behavior a, Event c)
mapAccumMaybeB f = mapAccumMaybeMB $ \v o -> pure $ f v o

mapAccumMaybeMB :: (MonadHold m, MonadFix m) => (a -> b -> PushM (Maybe a, Maybe c)) -> a -> Event b -> m (Behavior a, Event c)
mapAccumMaybeMB f z e = do
  rec let e' = flip push e $ \o -> do
            v <- sample d'
            result <- f v o
            pure $ case result of
              (Nothing,Nothing) -> Nothing
              _ -> Just result
      d' <- hold z $ fmapMaybe fst e'
  pure (d', fmapMaybe snd e')

mapAccum_ :: (MonadHold m, MonadFix m) => (a -> b -> (a,c)) -> a -> Event b -> m (Event c)
mapAccum_ f z e = do
  (_, result) <- mapAccumB f z e
  pure result

mapAccumMaybe_ :: (MonadHold m, MonadFix m) => (a -> b -> (Maybe a, Maybe c)) -> a -> Event b -> m (Event c)
mapAccumMaybe_ f z e = do
  (_,result) <- mapAccumMaybeB f z e
  pure result

mapAccumM_ :: (MonadHold m, MonadFix m) => (a -> b -> PushM (a,c)) -> a -> Event b -> m (Event c)
mapAccumM_ f z e = do
  (_,result) <- mapAccumMB f z e
  pure result

mapAccumMaybeM_ :: (MonadHold m, MonadFix m) => (a -> b -> PushM (Maybe a, Maybe c)) -> a -> Event b -> m (Event c)
mapAccumMaybeM_ f z e = do
  (_,result) <- mapAccumMaybeMB f z e
  pure result

instance Accumulator Dynamic where
  accumMaybeM = accumMaybeMDyn
  mapAccumMaybeM = mapAccumMaybeMDyn

instance Accumulator Behavior where
  accumMaybeM = accumMaybeMB
  mapAccumMaybeM = mapAccumMaybeMB

instance Accumulator Event where
  accumMaybeM f z e = updated <$> accumMaybeM f z e
  mapAccumMaybeM f z e = first updated <$> mapAccumMaybeM f z e

zipListWithEvent :: (MonadHold m, MonadFix m) => (a -> b -> c) -> [a] -> Event b -> m (Event c)
zipListWithEvent f l e = do
  let f' a b = case a of
        (h:t) -> (Just t, Just $ f h b)
        _ -> (Nothing,Nothing) -- TODO: Unsubscribe the event?
  mapAccumMaybe_ f' l e

numberOccurrences :: (MonadHold m, MonadFix m, Num b) => Event a -> m (Event (b,a))
numberOccurrences = numberOccurrencesFrom 0

numberOccurrencesFrom :: (MonadHold m, MonadFix m, Num b) => b -> Event a -> m (Event (b,a))
numberOccurrencesFrom = mapAccum_ (\n a -> let !next = n + 1 in (next, (n, a)))

numberOccurrencesFrom_ :: (MonadHold m, MonadFix m, Num b) => b -> Event a -> m (Event b)
numberOccurrencesFrom_ = mapAccum_ (\n _ -> let !next = n + 1 in (next, n))

infixl 4 <@>
(<@>) :: Behavior (a -> b) -> Event a -> Event b
(<@>) b = push $ \x -> do
  f <- sample b
  pure . Just . f $ x

infixl 4 <@
(<@) :: Behavior b -> Event a -> Event b
(<@) = tag

tailE :: MonadHold m => Event a -> m (Event a)
tailE e = snd <$> headTailE e

headTailE :: MonadHold m => Event a -> m (Event a, Event a)
headTailE e = do
  eHead <- headE e
  be <- hold never $ fmap (const e) eHead
  pure (eHead, switch be)

takeWhileE :: (MonadFix m, MonadHold m) => (a -> Bool) -> Event a -> m (Event a)
takeWhileE f = takeWhileJustE $ \v -> guard (f v) $> v

takeDropWhileJustE :: (MonadFix m, MonadHold m) => (a -> Maybe b) -> Event a -> m (Event b, Event a)
takeDropWhileJustE f e = do
  rec let (eBad,eGood) = fanEither $ ffor e' $ \a -> case f a of
            Nothing -> Left ()
            Just b -> Right b
      eFirstBad <- headE eBad
      e' <- switchHold e (never <$ eFirstBad)
  eRest <- switchHoldPromptOnly never (e <$ eFirstBad)
  pure (eGood,eRest)

dropWhileE :: (MonadFix m, MonadHold m) => (a -> Bool) -> Event a -> m (Event a)
dropWhileE f e = snd <$> takeDropWhileJustE (\v -> guard (f v) $> v) e

newtype UniqDynamic a = UniqDynamic { unUniqDynamic :: Dynamic a }

instance Functor UniqDynamic where
  fmap f = uniqDynamic . fmap f . unUniqDynamic

instance Applicative UniqDynamic where
  pure = UniqDynamic . constDyn
  UniqDynamic a <*> UniqDynamic b = uniqDynamic $ a <*> b
  _ *> b = b
  a <* _ = a

instance Monad UniqDynamic where
  UniqDynamic x >>= f = uniqDynamic $ x >>= unUniqDynamic . f
  _ >> b = b
  return = pure

uniqDynamic :: Dynamic a -> UniqDynamic a
uniqDynamic d = UniqDynamic $ unsafeBuildDynamic (sample $ current d) $ flip pushCheap (updated d) $ \new -> do
  old <- sample $ current d
  pure $ unsafeJustChanged old new

unsafePtrEq :: a -> a -> Bool
unsafePtrEq !a !b = case reallyUnsafePtrEquality# a b of
  0# -> False
  _ -> True

unsafeJustChanged :: a -> a -> Maybe a
unsafeJustChanged old new = if old `unsafePtrEq` new
  then Nothing
  else Just new

alreadyUniqDynamic :: Dynamic a -> UniqDynamic a
alreadyUniqDynamic = UniqDynamic

instance Accumulator UniqDynamic where
  accumMaybeM f z e = do
    let f' old change = do
          mNew <- f old change
          pure $ unsafeJustChanged old =<< mNew
    d <- accumMaybeMDyn f' z e
    pure $ UniqDynamic d
  mapAccumMaybeM f z e = do
    let f' old change = do
          (mNew,output) <- f old change
          pure (unsafeJustChanged old =<< mNew, output)
    (d,out) <- mapAccumMaybeMDyn f' z e
    pure (UniqDynamic d, out)

class Monad m => MonadSubscribeEvent m where
  subscribeEvent :: Event a -> m (EventHandle a)

instance MonadSubscribeEvent SpiderHost where
  subscribeEvent = runFrame . runSpiderHostFrame . subscribeEvent

instance MonadSubscribeEvent SpiderHostFrame where
  subscribeEvent e = SpiderHostFrame $ do
    val <- liftIO $ newIORef Nothing
    subscription <- subscribe e $ Subscriber
      { subscriberPropagate = \a -> do
          liftIO $ writeIORef val $ Just a
          scheduleClear val
      , subscriberInvalidateHeight = const (pure ())
      , subscriberRecalculateHeight = const (pure ())
      }
    pure $ EventHandle
      { eventHandleSubscription = subscription
      , eventHandleValue = val
      }

class Monad m => MonadReflexCreateTrigger m where
  newEventWithTrigger :: (EventTrigger a -> IO (IO ())) -> m (Event a)
  newFanEventWithTrigger :: GCompare k => (forall x. k x -> EventTrigger x -> IO (IO ())) -> m (EventSelector k)

instance MonadReflexCreateTrigger SpiderHost where
  newEventWithTrigger = SpiderHost . newEventWithTriggerIO
  newFanEventWithTrigger f = SpiderHost $ do
    es <- newFanEventWithTriggerIO f
    pure $ EventSelector $ select es

instance MonadReflexCreateTrigger SpiderHostFrame where
  newEventWithTrigger = SpiderHostFrame . EventM . liftIO . newEventWithTriggerIO
  newFanEventWithTrigger f = SpiderHostFrame $ EventM $ liftIO $ do
    es <- newFanEventWithTriggerIO f
    pure $ EventSelector $ select es

class (MonadReflexCreateTrigger m, MonadSubscribeEvent m) => MonadReflexHost m where
  fireEventsAndRead :: [DSum EventTrigger Identity] -> ReadPhase a -> m a
  runHostFrame :: SpiderHostFrame a -> m a

instance MonadReflexHost SpiderHost where
  fireEventsAndRead es (ReadPhase a) = run es a
  runHostFrame = runFrame . runSpiderHostFrame

fireEvents :: MonadReflexHost m => [DSum EventTrigger Identity] -> m ()
fireEvents dm = fireEventsAndRead dm $ pure ()

newEventWithTriggerRef :: (MonadReflexCreateTrigger m, MonadRef m, Ref m ~ Ref IO) => m (Event a, Ref m (Maybe (EventTrigger a)))
newEventWithTriggerRef = do
  rt <- newRef Nothing
  e <- newEventWithTrigger $ \t -> do
    writeRef rt $ Just t
    pure $ writeRef rt Nothing
  pure (e, rt)

fireEventRef :: (MonadReflexHost m, MonadRef m, Ref m ~ Ref IO) => Ref m (Maybe (EventTrigger a)) -> a -> m ()
fireEventRef mtRef input = readRef mtRef >>= \case
  Nothing -> pure ()
  Just trigger -> fireEvents [trigger :=> Identity input]  

fireEventRefAndRead :: (MonadReflexHost m, MonadRef m, Ref m ~ Ref IO) => Ref m (Maybe (EventTrigger a)) -> a -> EventHandle b -> m (Maybe b)
fireEventRefAndRead mtRef input e = readRef mtRef >>= \case
  Nothing -> pure Nothing -- since we aren't firing the input, the output can't fire
  Just trigger -> fireEventsAndRead [trigger :=> Identity input] $ readEvent e >>= \case
    Nothing -> pure Nothing
    Just getValue -> fmap Just getValue

newtype ReadPhase a = ReadPhase (EventM a)
  deriving (Functor,Applicative,Monad,MonadFix,MonadHold,MonadSample)

{-# noinline readEvent #-}
readEvent :: EventHandle a -> ReadPhase (Maybe (ReadPhase a))
readEvent h = ReadPhase $ fmap (fmap pure) $ liftIO $ do
  result <- readIORef $ eventHandleValue h
  touch h
  pure result

class Monad m => NotReady m where
  notReadyUntil :: Event a -> m ()
  notReady :: m ()

class Monad m => Adjustable m where
  runWithReplace ::
       m a
    -> Event (m b)
    -> m (a, Event b)
  traverseIntMapWithKeyAdjust ::
       (IntMap.Key -> v -> m v')
    -> IntMap v
    -> Event (PatchIntMap v)
    -> m (IntMap v', Event (PatchIntMap v'))
  traverseDMapWithKeyWithAdjust :: GCompare k
    => (forall x. k x -> v x -> m (v' x))
    -> DMap k v
    -> Event (PatchDMap k v)
    -> m (DMap k v', Event (PatchDMap k v'))
  traverseDMapWithKeyWithAdjustWithMove :: GCompare k
    => (forall x. k x -> v x -> m (v' x))
    -> DMap k v
    -> Event (PatchDMapWithMove k v)
    -> m (DMap k v', Event (PatchDMapWithMove k v'))

class Monad m => PostBuild m where
  getPostBuild :: m (Event ())

instance PostBuild m => PostBuild (ReaderT r m) where
  getPostBuild = lift getPostBuild

instance PostBuild m => PostBuild (StateT s m) where
  getPostBuild = lift getPostBuild

instance PostBuild m => PostBuild (StrictStateT.StateT s m) where
  getPostBuild = lift getPostBuild

networkView :: (NotReady m, Adjustable m, PostBuild m) => Dynamic (m a) -> m (Event a)
networkView child = do
  postBuild <- getPostBuild
  let newChild = leftmost [updated child, tagCheap (current child) postBuild]
  snd <$> runWithReplace notReady newChild

networkHold :: (Adjustable m, MonadHold m) => m a -> Event (m a) -> m (Dynamic a)
networkHold child0 newChild = do
  (result0, newResult) <- runWithReplace child0 newChild
  holdDyn result0 newResult

untilReady :: (Adjustable m, PostBuild m) => m a -> m b -> m (a, Event b)
untilReady a b = do
  postBuild <- getPostBuild
  runWithReplace a $ b <$ postBuild

newtype PostBuildT m a = PostBuildT { unPostBuild :: ReaderT (Event ()) m a }
  deriving (Functor,Applicative,Monad,MonadFix,MonadIO,MonadTrans,MonadException,MonadAsyncException)

runPostBuildT :: PostBuildT m a -> Event () -> m a
runPostBuildT (PostBuildT a) = runReaderT a

