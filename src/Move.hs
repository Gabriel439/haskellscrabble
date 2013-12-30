module Move (makeBoardMove, passMove, finaliseGame) where

  import ScrabbleError
  import FormedWord
  import Control.Monad
  import Data.Maybe
  import Game
  import Player
  import Data.Map as Map
  import Pos
  import Tile
  import LetterBag
  import Board
  import Dictionary

  makeBoardMove :: Game -> Player -> Map Pos Tile -> Either ScrabbleError (Player, Player, Game, FormedWords, GameStatus)
  makeBoardMove game player placed 
    | (not $ gameStatus game == InProgress) = Left GameNotInProgress
    | otherwise = 
        do
          formed <- formedWords
          (overallScore, _) <- scoresIfWordsLegal dict formed
          board <- newBoard currentBoard placed 
          player <- removeLettersandGiveScore player playedTiles overallScore

          if hasEmptyRack player && (bagSize letterBag == 0)
           then
            do
              let (newPlayer, updatedGame) = updateGame game player board letterBag
              return (player, newPlayer, updatedGame {gameStatus = ToFinalise}, formed, ToFinalise)
            else
              do
                let (newPlayer, newBag) = updatePlayerRackAndBag player letterBag
                let (nextPlayer, updatedGame) = updateGame game newPlayer board newBag
                return (newPlayer, nextPlayer, updatedGame, formed, InProgress)

      where
        playedTiles = Prelude.map snd $ Map.toList placed
        currentBoard = board game
        moveNo = moveNumber game
        dict = dictionary game
        letterBag = bag game

        formedWords = if (moveNo == 1)
         then wordFormedFirstMove currentBoard placed 
         else wordsFormedMidGame currentBoard placed

  passMove :: Game -> (Player, Game, GameStatus)
  passMove game = let (player, game) = pass game in (player, game, newStatus)
    where
      numPasses = passes game
      newStatus = if numPasses == ((numberOfPlayers game) * 2) then ToFinalise else InProgress

  finaliseGame :: Game -> Game
  finaliseGame game
    | (gameStatus game == Finished) = game
    | otherwise = game {player1 = play1, player2 = play2, optionalPlayers = optional, gameStatus = Finished}
      where
        unplayedValues = Prelude.sum $ Prelude.map tileValues allPlayers
        allPlayers = getPlayers game

        play1 = finalisePlayer (player1 game)
        play2 = finalisePlayer (player2 game)
        optional = optionalPlayers game >>= (\(player3, maybePlayer4) ->
            Just (finalisePlayer player3, maybePlayer4 >>= (\play4 -> Just $ finalisePlayer play4) ) )

        finalisePlayer player = if hasEmptyRack player then updateScore player unplayedValues
          else reduceScore player (tileValues player) 

  updatePlayerRackAndBag :: Player -> LetterBag -> (Player, LetterBag)
  updatePlayerRackAndBag player letterBag =
    if tilesInBag == 0 
      then (player, letterBag)
      else
        if (tilesInBag >= 7)
          then maybe (player, letterBag) (\(taken, newBag) -> 
            (giveTiles player taken, newBag)) $ takeLetters letterBag 7
            else maybe (player, letterBag) (\(taken, newBag) -> 
              (giveTiles player taken, newBag)) $ takeLetters letterBag tilesInBag
    
    where
      tilesInBag = bagSize letterBag

  newBoard :: Board -> Map Pos Tile -> Either ScrabbleError Board
  newBoard board placed = 
    let tryNewBoard = foldM (\board (pos, tile) -> placeTile board tile pos) board $ Map.toList placed
    in maybe (Left PlacedTileOnOccupiedSquare) (\board -> Right board) tryNewBoard

  
  removeLettersandGiveScore :: Player -> [Tile] -> Int -> Either ScrabbleError Player
  removeLettersandGiveScore player tiles justScored = 
    let newPlayer = removePlayedTiles player tiles 
    in case newPlayer of
      Nothing -> Left $ PlayerCannotPlace (rack player) tiles
      Just (playerUpdatedRack) -> Right $ updateScore playerUpdatedRack justScored
    

  scoresIfWordsLegal :: Dictionary -> FormedWords -> Either ScrabbleError (Int, [(String, Int)])
  scoresIfWordsLegal dict formedWords = 
    let strings = wordStrings formedWords
    in case invalidWords dict strings of
      (x:xs) -> Left $ WordsNotInDictionary (x:xs)
      otherwise -> Right $ wordsWithScores formedWords