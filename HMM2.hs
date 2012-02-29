module HMM2
    where

import Debug.Trace
import Data.Array
import Data.Number.LogFloat
import qualified Data.MemoCombinators as Memo

type Prob = LogFloat

   -- | The data type for our HMM

data HMM stateType eventType = HMM { states :: [stateType]
                                   , events :: [eventType]
                                   , initProbs :: (stateType -> Prob)
                                   , transMatrix :: (stateType -> stateType -> Prob)
                                   , outMatrix :: (stateType -> eventType -> Prob)
                                   }

instance (Show state, Show observation) => Show (HMM state observation) where
    show hmm = "HMM" ++ " states=" ++ (show $ states hmm) 
                     ++ " events=" ++ (show $ events hmm) 
                     ++ " initProbs=" ++ (show [(s,initProbs hmm s) | s <- states hmm])
                     ++ " transMatrix=" ++ (show [(s1,s2,transMatrix hmm s1 s2) | s1 <- states hmm, s2 <- states hmm])
                     ++ " outMatrix=" ++ (show [(s,e,outMatrix hmm s e) | s <- states hmm, e <- events hmm])

   -- | forward algorithm
      
forward :: (Eq eventType) => HMM stateType eventType -> [eventType] -> Prob
forward=forwardArray

forwardList :: (Eq eventType) => HMM stateType eventType -> [eventType] -> Prob
forwardList hmm obs = sum [alphaList hmm obs state | state <- states hmm]

alphaList :: (Eq eventType) => HMM stateType eventType -> [eventType] -> stateType -> Prob
alphaList hmm obs@(x:xs) state
    | xs==[]        = (outMatrix hmm state x)*(initProbs hmm state)
    | otherwise     = (outMatrix hmm state x)*(sum [(alphaList hmm xs state)*(transMatrix hmm state state2) | state2 <- states hmm
                                                   ])
                                                   
forwardArray :: (Eq eventType) => HMM stateType eventType -> [eventType] -> Prob
forwardArray hmm obs = sum [alphaArray hmm (listArray (1,bT) obs) bT state | state <- states hmm]
    where
          bT = length obs

alphaArray :: (Eq eventType) => HMM stateType eventType -> Array Int eventType -> Int -> stateType -> Prob
alphaArray hmm obs t state
    | t == 1        = (outMatrix hmm state $ obs!t)*(initProbs hmm state)
    | otherwise     = (outMatrix hmm state $ obs!t)*(sum [(alphaArray hmm obs (t-1) state2)*(transMatrix hmm state2 state) | state2 <- states hmm
                                                         ])
-- memoized_alphaArray :: (Eq eventType) => HMM stateType eventType -> Array Int eventType -> Int -> stateType -> Prob
memoized_alphaArray hmm obs t = (map aa (states hmm) !!)
    where aa state = if t==1
                        then (outMatrix hmm state $ obs!t)*(initProbs hmm state)
                        else (outMatrix hmm state $ obs!t)*(sum [(memoized_alphaArray hmm obs (t-1) state)*(transMatrix hmm state state2) | state2 <- states hmm])

memo_alphaArray :: (Eq eventType) => HMM Integer eventType -> Array Int eventType -> Int -> Integer -> Prob
memo_alphaArray hmm obs = Memo.memo2 Memo.integral Memo.integral aa
    where aa t state 
            | t == 1        = (outMatrix hmm state $ obs!t)*(initProbs hmm state)
            | otherwise     = (outMatrix hmm state $ obs!t)*(sum [(memo_alphaArray hmm obs (t-1) state)*(transMatrix hmm state state2) | state2 <- states hmm
                                                         ])
memoized_fib :: Int -> Integer
memoized_fib = (map fib [0 .. 10] !!)
   where fib 0 = 0
         fib 1 = 1
         fib n = memoized_fib (n-2) + memoized_fib (n-1)
   
   -- | backwards algorithm
   
backward :: (Eq eventType, Show eventType) => HMM stateType eventType -> [eventType] -> Prob
backward hmm obs = backwardArray hmm $ listArray (1,length obs) obs
    
backwardArray :: (Eq eventType,Show eventType) => HMM stateType eventType -> Array Int eventType -> Prob
backwardArray hmm obs = backwardArray' hmm obs
    where 
          backwardArray' hmm obs = sum [(initProbs hmm state)
                                       *(outMatrix hmm state $ obs!1)
                                       *(betaArray hmm obs 1 state)
                                       | state <- states hmm
                                       ]
    
betaArray :: (Eq eventType) => HMM stateType eventType -> Array Int eventType -> Int -> stateType -> Prob
betaArray hmm obs t state
    | t == bT       = 1
    | otherwise     = sum [(transMatrix hmm state state2)
                          *(outMatrix hmm state2 $ obs!(t+1))
                          *(betaArray hmm obs (t+1) state2) 
                          | state2 <- states hmm
                          ]
        where 
              bT = snd $ bounds obs


-- This implementation has a bug somewhere, but it is also not used in Baum-Welch

backwardList :: (Eq eventType,Show eventType) => HMM stateType eventType -> [eventType] -> Prob
backwardList hmm obs = backwardList' hmm $ reverse obs
    where 
          backwardList' hmm obsrev = sum [(initProbs hmm state)
                                         *(outMatrix hmm state $ head obsrev)
                                         *(betaArray hmm (listArray (1,length obsrev) obsrev) 1 state)
--                                          *(betaList hmm obsrev state)
                                         | state <- states hmm
                                         ]
   
betaList :: (Eq eventType) => HMM stateType eventType -> [eventType] -> stateType -> Prob
betaList hmm obs@(x:xs) state
    | xs == []      = 1
    | otherwise     = sum [(transMatrix hmm state state2)
                          *(outMatrix hmm state2 x)
                          *(betaList hmm xs state2) 
                          | state2 <- states hmm
                          ]


   -- | Baum-Welch
   
gammaArray :: (Eq eventType, Show eventType) => HMM stateType eventType
                                             -> Array Int eventType
                                             -> Int
                                             -> stateType
                                             -> Prob
gammaArray hmm obs t state = (alphaArray hmm obs t state)
                            *(betaArray hmm obs t state)
                            /(backwardArray hmm obs)
   
   -- xi i j = P(state (t-1) == i && state (t) == j | obs, lambda)
   
xiArray :: (Eq eventType, Show eventType) => HMM stateType eventType 
                                          -> Array Int eventType 
                                          -> Int 
                                          -> stateType 
                                          -> stateType 
                                          -> Prob
xiArray hmm obs t state1 state2 = (alphaArray hmm obs (t-1) state1)
                                 *(transMatrix hmm state1 state2)
                                 *(outMatrix hmm state2 $ obs!t)
                                 *(betaArray hmm obs t state2)
                                 /(backwardArray hmm obs)

baumWelch :: (Eq eventType, Show eventType) => HMM stateType eventType -> Array Int eventType -> Int -> HMM stateType eventType
baumWelch hmm obs count
    | count == 0    = hmm
    | otherwise     = baumWelch (baumWelchItr hmm obs) obs (count-1)

baumWelchItr :: (Eq eventType, Show eventType) => HMM stateType eventType -> Array Int eventType -> HMM stateType eventType
baumWelchItr hmm obs = HMM { states = states hmm
                           , events = events hmm
                           , initProbs = newInitProbs
                           , transMatrix = newTransMatrix
                           , outMatrix = newOutMatrix
                           }
                               where newInitProbs state = gammaArray hmm obs 1 state
                                     newTransMatrix state1 state2 = sum [xiArray hmm obs t state1 state2 | t <- [2..(snd $ bounds obs)]]
                                                                   /sum [gammaArray hmm obs t state1 | t <- [2..(snd $ bounds obs)]]
                                     newOutMatrix state event = sum [if (obs!t == event) 
                                                                        then gammaArray hmm obs t state 
                                                                        else 0
                                                                    | t <- [2..(snd $ bounds obs)]
                                                                    ]
                                                               /sum [gammaArray hmm obs t state | t <- [2..(snd $ bounds obs)]]
                              
   -- | utility functions
   --
   -- | takes the cross product of a list multiple times
   
listCPExp :: [a] -> Int -> [[a]]
listCPExp language order = listCPExp' order [[]]
    where
        listCPExp' order list
            | order == 0    = list
            | otherwise     = listCPExp' (order-1) [symbol:l | l <- list, symbol <- language]

   -- | tests
                                              
-- this should equal ~1 if our recurrence in alpha is correct
alphatest hmm x = sum [alphaList hmm e s | e <- listCPExp (events hmm) x, s <- states hmm]

forwardtest hmm x = sum [forward hmm e | e <- listCPExp (events hmm) x]

backwardtest hmm x = sum [backward hmm e | e <- listCPExp (events hmm) x]

fftest hmm events = "fwdLst: " ++ show (forwardList hmm events) ++ " fwdArr:" ++ show (forwardArray hmm events)
bbtest hmm events = "bckLst: " ++ show (backwardList hmm events) ++ " bckArr:" ++ show (backwardArray hmm $ listArray (1,length events) events)

fbtest hmm events = "fwd: " ++ show (forward hmm events) ++ " bkwd:" ++ show (backward hmm  events)

   -- | sample HMM used for testing
   
arr :: Array Int Char
arr = listArray (1,5) "AGTCA"
   
simpleHMM = HMM { states=[1,2]
                , events=['A','G','C','T']
                , initProbs = ipTest
                , transMatrix = tmTest
                , outMatrix = omTest
                }

-- ipTest :: Array Int Prob
-- ipTest = listArray (1,2) [0.1,0.9]

ipTest s
    | s == 1  = 0.1
    | s == 2  = 0.9

tmTest s1 s2
    | s1==1 && s2==1    = 0.9
    | s1==1 && s2==2    = 0.1
    | s1==2 && s2==1    = 0.5
    | s1==2 && s2==2    = 0.5

omTest s e
    | s==1 && e=='A'    = 0.4
    | s==1 && e=='G'    = 0.1
    | s==1 && e=='C'    = 0.1
    | s==1 && e=='T'    = 0.4
    | s==2 && e=='A'    = 0.1
    | s==2 && e=='G'    = 0.4
    | s==2 && e=='C'    = 0.4
    | s==2 && e=='T'    = 0.1
    