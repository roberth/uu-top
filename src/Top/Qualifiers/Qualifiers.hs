module Top.Qualifiers.Qualifiers where

import Top.States.States(Has(..), modify, Empty(..), Plus(..))
import Top.States.QualifierState
import Top.Types
import Top.Constraints.TypeConstraintInfo
import Top.Qualifiers.QualifierMap
import Control.Monad
import Data.List (union, (\\))
import Top.States.SubstState

---------------------------------------------------------------------
-- Type class for qualifiers

class ( ShowQualifiers q
      , Substitutable q
      , TypeConstraintInfo info
      , Has m (QualifierMap q info)
      ) => 
        Qualifier m info q | m -> info
   where
      -- constraint entailment
      entails            :: [(q, info)] ->  q  -> m Bool
      entailsList        :: [(q, info)] -> [q] -> m Bool
      -- constraint normalization
      normalizeFixpoint  :: [(q, info)] -> m ([(q, info)], Bool)
      normalize          :: [(q, info)] -> m  [(q, info)]
      normalizeOne       ::  (q, info)  -> m  [(q, info)]
      -- constraint generalization
      whatToGeneneralize :: [Int] -> [(q, info)] -> m ([(q, info)], [(q, info)]) -- first list is generalized, second list remains 
      generalizeOrNot    :: [Int] ->  (q, info)  -> m Bool
      -- constraint ambiguities
      ambiguous          :: [(q, info)] -> m ()
      ambiguousOne       ::  (q, info)  -> m ()
      
      -- default definitions
      entails as a = entailsList as [a]
      entailsList as bs = 
         do xs <- mapM (entails as) bs
            return (and xs)
         
      normalizeFixpoint xs = 
         do new <- normalize xs; return (new, False)
         
      normalize xs = 
         mapM normalizeOne xs >>= (return . concat)
         
      normalizeOne pair = 
         return [pair]
      
      whatToGeneneralize is = 
         let op (as, bs) tuple = 
                do b <- generalizeOrNot is tuple
                   return (if b then (tuple:as, bs) else (as, tuple:bs))
         in foldM op ([], [])
      generalizeOrNot is = return . any (`elem` is) . ftv . fst

      ambiguous      = mapM_ ambiguousOne
      ambiguousOne _ = return ()

---------------------------------------------------------------------
-- Type class for nested tuples of qualifiers

class ( ShowQualifiers qs
      , Substitutable qs
      , Empty qs
      , Plus qs
      , Monad m
      , TypeConstraintInfo info
      ) => 
        QualifierList m info qs qsInfo | info qs -> qsInfo, qsInfo -> info qs 
   where
      normalizeList     :: qsInfo -> m (qsInfo, Bool)
      whatToGenList     :: [Int] -> qsInfo -> m (qsInfo, qsInfo)
      ambiguousList     :: qsInfo -> m ()

      combineList       :: qsInfo -> qsInfo -> m qsInfo
      ftvList           :: qsInfo -> m [Int]
      annotate          :: info -> qs -> m qsInfo
      removeAnnotation  :: qsInfo -> m qs
   
      getToProveUpdated :: HasSubst m info => m qsInfo
      putToProve        :: qsInfo -> m ()
      addToProve        :: qsInfo -> m ()
      addToGeneralized  :: qsInfo -> m ()
      addToAssumptions  :: qsInfo -> m ()

instance ( QualifierList m info as asInfo
         , QualifierList m info bs bsInfo
         ) => 
           QualifierList m info (as, bs) (asInfo, bsInfo) 
   where
      whatToGenList is (as, bs) = 
         do (as1, as2) <- whatToGenList is as
            (bs1, bs2) <- whatToGenList is bs
            return ((as1, bs1), (as2, bs2))
            
      normalizeList (as, bs) = 
         do (asNew, b1) <- normalizeList as 
            (bsNew, b2) <- normalizeList bs
            return ((asNew, bsNew), b1 || b2)
      
      combineList (as1, bs1) (as2, bs2) = 
         do asNew <- combineList as1 as2
            bsNew <- combineList bs1 bs2
            return (asNew, bsNew)
            
      ftvList (as, bs) = 
         do xs <- ftvList as 
            ys <- ftvList bs
            return (xs `union` ys)
      
      ambiguousList (as, bs)    = ambiguousList as >> ambiguousList bs
      annotate info (as, bs)    = distribute (annotate info as) (annotate info bs)
      removeAnnotation (as, bs) = distribute (removeAnnotation as) (removeAnnotation bs)
      getToProveUpdated         = distribute getToProveUpdated getToProveUpdated
      putToProve (as, bs)       = putToProve as  >> putToProve bs
      addToProve (as, bs)       = addToProve as  >> addToProve bs
      addToGeneralized (as, bs) = addToGeneralized as  >> addToGeneralized bs
      addToAssumptions (as, bs) = addToAssumptions as >> addToAssumptions bs

instance (Qualifier m info p, HasQual m qs info) => QualifierList m info [p] [(p, info)]
   where
      normalizeList       = normalizeFixpoint
      whatToGenList       = whatToGeneneralize
      ambiguousList       = ambiguous
      combineList as bs   = return (as ++ bs)
      ftvList as          = return (ftv (map fst as))
      annotate info as    = return (zip as (repeat info))
      removeAnnotation    = return . map fst
      getToProveUpdated   = getToProveUpdatedHelper
      putToProve ps       = do n <- currentGroup ; modify (setQualifiersInGroup n ps)
      addToProve ps       = do n <- currentGroup ; modify (addQualifiersInGroup n ps)
      addToGeneralized ps = do n <- currentGroup ; modify (addGeneralizedQsInGroup n ps)
      addToAssumptions ps = do n <- currentGroup ; modify (addAssumptionsInGroup n ps)
      
getToProveUpdatedHelper :: (HasSubst m info, HasQual m qs info, Qualifier m info q) => m [(q, info)]
getToProveUpdatedHelper =
   do n <- currentGroup
      qmOld <- get
      qmNew <- applySubst qmOld
      newQs <- let p x = do b <- entails (getAssumptions qmNew) (fst x)
                            return (not b)
               in filterM p (getQualifiersInGroup n qmNew)
      modify (const (setQualifiersInGroup n newQs qmNew))
      return newQs
   
distribute :: Monad m => m a -> m b -> m (a, b)
distribute ma mb =
   do a <- ma; b <- mb; return (a, b)
      
doNormalization :: (HasSubst m info, QualifierList m info qs qsInfo) => m qsInfo
doNormalization =
   do makeConsistent
      old      <- getToProveUpdated
      (new, b) <- normalizeList old
      putToProve new
      if b then doNormalization else return new   
      

doGeneralization :: QualifierList m info qs qsInfo => [Int] -> [Int] -> qsInfo -> m ([Int], qsInfo, qsInfo)
doGeneralization monos alphas qs =
   do (psGen, psNew) <- whatToGenList alphas qs
      extraAlphas    <- ftvList psGen
      let newAlphas = (extraAlphas \\ alphas) \\ monos
          allAlphas = newAlphas ++ alphas
      if null newAlphas 
         then 
            return (allAlphas, psGen, psNew)
         else
            do (is, qs2, rest) <- doGeneralization monos allAlphas psNew
               allQs <- combineList psGen qs2
               return (allAlphas `union` is, allQs, rest)

doAmbiguityCheck :: (HasSubst m info, QualifierList m info qs qsInfo) => m qsInfo
doAmbiguityCheck =
   do new <- doNormalization
      ambiguousList new
      return new