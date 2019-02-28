-- | This module defines 'PostBuild', which indicates that an action will be
-- notified when it, and any action it's a part of, has finished executing.
{-# LANGUAGE CPP #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}
#ifdef USE_REFLEX_OPTIMIZER
{-# OPTIONS_GHC -fplugin=Reflex.Optimizer #-}
#endif
module Reflex.PostBuild.Class
  ( PostBuild (..)
  ) where

import Reflex

import Control.Monad.Reader
import Control.Monad.State
import qualified Control.Monad.State.Strict as Strict

-- | 'PostBuild' represents an action that is notified via an 'Event' when it
-- has finished executing.  Note that the specific definition of "finished" is
-- determined by the instance of 'PostBuild', but the intent is to allow
-- 'Behavior's and 'Dynamic's to be safely sampled, regardless of where they
-- were created, when the post-build 'Event' fires.  The post-build 'Event' will
-- fire exactly once for an given action.
class (Monad m) => PostBuild m where
  -- | Retrieve the post-build 'Event' for this action.
  getPostBuild :: m (Event ())

instance PostBuild m => PostBuild (ReaderT r m) where
  getPostBuild = lift getPostBuild

instance PostBuild m => PostBuild (StateT s m) where
  getPostBuild = lift getPostBuild

instance PostBuild m => PostBuild (Strict.StateT s m) where
  getPostBuild = lift getPostBuild
