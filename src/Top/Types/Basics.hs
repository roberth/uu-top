-----------------------------------------------------------------------------
-- |
-- Maintainer  :  bastiaan@cs.uu.nl
-- Stability   :  experimental
-- Portability :  unknown
--
-- This module contains a data type to represent (plain) types, some basic 
-- functionality for types, and an instance for Show.
--
-----------------------------------------------------------------------------

module Top.Types.Basics where

import Data.List (union)
import Data.Char (isDigit)

-----------------------------------------------------------------------------
-- * Data type definition

type Tps      = [Tp]
-- |A data type to represent monotypes. Note that 'Type' is already in use
-- in the Unified Haskell Architecture (UHA) which is used in the Helium compiler
data Tp       = TVar Int      -- ^The type variables are numbered.
              | TCon String   -- ^A type constant is represented by a string.
              | TApp Tp Tp    -- ^The application of two Top.Types. Not all types that can be
                              -- constructed are well-formed.
  deriving Eq

----------------------------------------------------------------------
-- * Common types

intType, charType, floatType, boolType, stringType :: Tp
intType    = TCon "Int"
charType   = TCon "Char"
floatType  = TCon "Float"
boolType   = TCon "Bool"
stringType = TCon "String"

infixr 5 .->.
-- |Constructs a function type from one type to another. This operator is
-- left associative.
(.->.) :: Tp -> Tp -> Tp
t1 .->. t2 = TApp (TApp (TCon "->") t1) t2

-- |For instance, @(listType intType)@ represents @[Int]@
listType :: Tp -> Tp
listType t1 = TApp (TCon "[]") t1

-- |For instance, @(ioType boolType)@ represents @(IO Bool)@
ioType :: Tp -> Tp
ioType t1 = TApp (TCon "IO") t1

-- |A cathesian product of zero or more Top.Types. For instance,
-- @(tupleType [])@ represents @()@, and @(tupleType [charType, stringType])@
-- represents @(Char,String)@
tupleType :: Tps -> Tp
tupleType tps = let name | null tps  = "()"
                         | otherwise = "("++replicate (length tps-1) ','++")"
                in foldl TApp (TCon name) tps

-- |The unit type. A special instance of of tuple type.
voidType :: Tp
voidType   = tupleType []

----------------------------------------------------------------------
-- * Basic functionality

-- |Returns the list of type variables of a type. (no duplicates)
variablesInType :: Tp -> [Int]
variablesInType tp = case tp of
   TVar i     -> [i]
   TCon _     -> []
   TApp t1 t2 -> variablesInType t1 `union` variablesInType t2

-- |Returns the list of type constants of a type. (no duplicates)
constantsInType :: Tp -> [String]
constantsInType tp = case tp of
   TVar _     -> []
   TCon s     -> [s]
   TApp t1 t2 -> constantsInType t1 `union` constantsInType t2

-- |Returns the left spine of a type. For instance, if type @t@
-- is @Either Bool [Int]@, then @leftSpine t@ is @(Either,[Bool,[Int]])@.
leftSpine :: Tp -> (Tp,Tps)
leftSpine = rec [] where
   rec tps (TApp t1 t2) = rec (t2:tps) t1
   rec tps tp           = (tp,tps)

-- |Returns the right spine of a function type. For instance,
-- if type @t@ is @Int -> (Bool -> String)@, then @functionSpine t@
-- is @([Int,Bool],String)@.
functionSpine :: Tp -> (Tps,Tp)
functionSpine = rec [] where
   rec tps (TApp (TApp (TCon "->") t1) t2) = rec (t1:tps) t2
   rec tps tp                              = (reverse tps,tp)

-- |Returns the right spine of a function type of a maximal length.
functionSpineOfLength :: Int -> Tp -> (Tps, Tp)
functionSpineOfLength i tp = 
   let (as, a ) = functionSpine tp
       (bs, cs) = splitAt i as
   in (bs, foldr (.->.) a cs)

-- |Returns the arity of a type, that is, the number of expected arguments.
arityOfTp :: Tp -> Int
arityOfTp = length . fst . functionSpine

-- |The priority of a type, primarily used for the insertion of parentheses 
-- in pretty printing.
priorityOfType :: Tp -> Int
priorityOfType tp = case leftSpine tp of
       (TCon "->",[_,_]  ) -> 0
       (_        ,[]     ) -> 2
       (TCon "[]",[_]    ) -> 2
       (TCon s   ,_      ) | isTupleConstructor s -> 2
       _                   -> 1

-- |All the type variables in a type are frozen by turning them into a type
-- constant. The integer numeral is prefixed with an underscore ('_').
freezeVariablesInType :: Tp -> Tp
freezeVariablesInType tp =
   case tp of
      TVar i   -> TCon ('_':show i)
      TCon s   -> TCon s
      TApp l r -> TApp (freezeVariablesInType l) (freezeVariablesInType r)

-- |Recover the type variables that are frozen in a type.
unfreezeVariablesInType :: Tp -> Tp
unfreezeVariablesInType tp =
   case tp of
      TVar i     -> TVar i
      TCon ('_':s) | all isDigit s && not (null s)
                 -> TVar (read s)
      TCon s     -> TCon s
      TApp l r   -> TApp (unfreezeVariablesInType l) (unfreezeVariablesInType r)

----------------------------------------------------------------------
-- * Predicates on types

isTVar :: Tp -> Bool
isTVar (TVar _) = True
isTVar _        = False

isTCon :: Tp -> Bool
isTCon (TCon _) = True
isTCon _        = False

isTApp :: Tp -> Bool
isTApp (TApp _ _) = True
isTApp _          = False

isTupleConstructor :: String -> Bool
isTupleConstructor ('(':[]) = False
isTupleConstructor ('(':cs) = all (','==) (init cs) && last cs == ')'
isTupleConstructor _        = False

isIOType :: Tp -> Bool
isIOType (TApp (TCon "IO") _) = True
isIOType _                    = False

----------------------------------------------------------------------
-- Show function

instance Show Tp where
   show tp = case leftSpine tp of 
       (TCon "->",[t1,t2]) -> rec (<1) t1 ++ " -> " ++ rec (const False) t2
       (TVar i   ,[]     ) -> 'v' : show i
       (TCon s   ,[]     ) -> s
       (TCon "[]",[t1]   ) -> "[" ++ rec (const False) t1 ++ "]"
       (TCon s   ,ts     ) | isTupleConstructor s -> let ts'  = map (rec (const False)) ts
                                                         f [] = ""
                                                         f xs = foldr1 (\x y -> x++", "++y) xs
                                                     in "(" ++ f ts' ++ ")"
       (t,ts) -> unwords (map (rec (<2)) (t:ts))

       where rec p t       = parIf (p (priorityOfType t)) (show t) 
             parIf True  s = "("++s++")"
             parIf False s = s
