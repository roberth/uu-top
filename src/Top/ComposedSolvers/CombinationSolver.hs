-----------------------------------------------------------------------------
-- |
-- Maintainer  :  bastiaan@cs.uu.nl
-- Stability   :  experimental
-- Portability :  unknown
--
-----------------------------------------------------------------------------

module Top.ComposedSolvers.CombinationSolver where

import Top.Solvers.SolveConstraints

-- |The first solver is used to solve the constraint set. If this fails (at least one 
-- error is returned), then the second solver takes over.     
(|>>|) :: SolverX constraint info qs ext -> SolverX constraint info qs ext -> SolverX constraint info qs ext
s1 |>>| s2 = \classEnv synonyms unique constraints -> 
   let r1 = s1 classEnv synonyms unique constraints
       r2 = s2 classEnv synonyms unique constraints
   in if null (errorsFromResult r1) then r1 else r2
