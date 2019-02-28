-- | This module defines the 'EventWriter' class.
{-# LANGUAGE CPP #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE UndecidableInstances #-}
#ifdef USE_REFLEX_OPTIMIZER
{-# OPTIONS_GHC -fplugin=Reflex.Optimizer #-}
#endif
module Reflex.EventWriter.Class
  ( EventWriter (..)
  ) where

import Control.Monad.Reader (ReaderT, lift)
import Data.Semigroup (Semigroup)

import Reflex (Event)


-- | 'EventWriter' efficiently collects 'Event' values using 'tellEvent'
-- and combines them via 'Semigroup' to provide an 'Event' result.
class (Monad m, Semigroup w) => EventWriter w m where
  tellEvent :: Event w -> m ()


instance EventWriter w m => EventWriter w (ReaderT r m) where
  tellEvent = lift . tellEvent
