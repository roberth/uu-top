-----------------------------------------------------------------------------
-- |
-- Maintainer  :  bastiaan@cs.uu.nl
-- Stability   :  experimental
-- Portability :  unknown
--
-----------------------------------------------------------------------------

module Top.Solvers.SolveConstraints where

import Top.Types
import Top.Constraints.Constraints
import Top.Qualifiers.Qualifiers
import Top.Constraints.TypeConstraintInfo
import Top.States.States
import Top.States.SubstState
import Top.States.BasicState
import Top.States.TIState
import Top.States.QualifierState
import Top.Solvers.BasicMonad
import Data.List
import Data.FiniteMap

type SolveX info qs sub ext = BasicX info (TIState info, (QualifierState qs info, (sub, ext)))
type Solve  info qs sub     = SolveX info qs sub ()

instance HasTI (SolveX info qs sub ext) info where
   tiGet   = do (x, _) <- getX; return x
   tiPut x = do (_, y) <- getX; putX (x, y)

instance HasQual (SolveX info qs sub ext) qs info where
   qualGet   = do (_, (y, _)) <- getX; return y
   qualPut y = do (x, (_, z)) <- getX; putX (x, (y, z))

solveConstraints :: 
   ( IsState ext
   , IsState sub
   , HasSubst (SolveX info qs sub ext) info
   , QualifierList (SolveX info qs sub ext) info qs qsInfo
   , Solvable constraint (SolveX info qs sub ext)
   ) => 
     SolveX info qs sub ext () ->           -- doFirst
     SolveX info qs sub ext result ->       -- doAtEnd
     [constraint] ->                        -- constraints
     SolveX info qs sub ext result          -- result
     
solveConstraints doFirst doAtEnd cs = 
   do doFirst
      pushAndSolveConstraints cs
      makeConsistent
      checkSkolems
      doAmbiguityCheck :: ( HasSubst (SolveX info qs sub ext) info
                          , QualifierList (SolveX info qs sub ext) info qs qsInfo
                          ) => 
                            SolveX info qs sub ext qsInfo
      doAtEnd

solveResult :: 
   ( HasBasic m info
   , HasTI m info
   , HasSubst m info
   , HasQual m qs info
   , Empty ext
   , TypeConstraintInfo info
   , QualifierList m info qs qsInfo
   ) => 
     m (SolveResult info qs ext)
                  
solveResult = 
   do uniqueAtEnd <- getUnique
      errs        <- getLabeledErrors
      qsInfo      <- getToProveUpdated
      (qs, infos) <- removeAnnotation' qsInfo
      let dummy = head infos `asTypeOf` fst (head errs) -- help type inference
      sub         <- fixpointSubst
      ts          <- allTypeSchemes     
      messages    <- getMessages     
      return (SolveResult uniqueAtEnd sub ts qs errs messages empty)

----------------------------------------------------------------------
-- Solve type constraints

type SolverX constraint info qs ext = ClassEnvironment -> OrderedTypeSynonyms -> Int -> [constraint] -> SolveResult info qs ext
type Solver  constraint info qs     = SolverX constraint info qs ()

data SolveResult info qs ext =  
   SolveResult { uniqueFromResult       :: Int
               , substitutionFromResult :: FixpointSubstitution
               , typeschemesFromResult  :: FiniteMap Int (Scheme qs)
               , qualifiersFromResult   :: qs
               , errorsFromResult       :: [(info, ErrorLabel)]
               , debugFromResult        :: String
               , extensionFromResult    :: ext
               }

instance (Empty qs, Empty ext) => Empty (SolveResult info qs ext) where 
   empty = emptyResult 0
   
instance (Plus qs, Plus ext) => Plus (SolveResult info qs ext) where 
   plus (SolveResult _ s1 ts1 qs1 er1 io1 ext1) (SolveResult unique s2 ts2 qs2 er2 io2 ext2) = 
      SolveResult unique (disjointFPS s1 s2) (ts1 `plusFM` ts2) (qs1 `plus` qs2) (er1++er2) (io1++io2) (ext1 `plus` ext2)

emptyResult :: (Empty qs, Empty ext) => Int -> SolveResult info qs ext
emptyResult unique = SolveResult unique emptyFPS emptyFM empty [] [] empty