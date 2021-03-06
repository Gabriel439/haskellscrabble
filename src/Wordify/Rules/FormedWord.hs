module Wordify.Rules.FormedWord
 (
 FormedWords,
 FormedWord,
 wordsFormedMidGame,
 wordFormedFirstMove,
 wordStrings,
 wordsWithScores,
 mainWord,
 adjacentWords,
 playerPlaced,
 bingoBonusApplied
 ) where

  import Wordify.Rules.Pos
  import Wordify.Rules.Square
  import Wordify.Rules.Tile
  import Wordify.Rules.Board
  import Wordify.Rules.ScrabbleError
  import Data.Sequence as Seq
  import Data.Map as Map
  import Control.Applicative
  import Control.Monad
  import Data.Foldable as Foldable
  import qualified Data.Maybe as M

  data FormedWords =  FirstWord FormedWord  | FormedWords {
                                              main :: FormedWord
                                              , otherWords :: [FormedWord]
                                              , placed :: Map Pos Square
                                            } deriving (Show, Eq)
                                  
  type FormedWord = Seq (Pos, Square)
  data Direction = Horizontal | Vertical deriving Eq

  {- |
     Returns the word formed by the first move on the board. The word must cover
     the star tile, and be linear. Any blank tiles must be labeled.
   -}
  wordFormedFirstMove :: Board -> Map Pos Tile -> Either ScrabbleError FormedWords
  wordFormedFirstMove board tiles = 
    if starPos `Map.notMember` tiles
      then Left DoesNotCoverTheStarTile
      else placedSquares board tiles >>= 
        \squares -> (FirstWord . main) <$> wordsFormed board squares

  {- |
    Returns the words formed by the tiles played on the board. A played word
    must be connected to a tile already on the board (or intersect tiles on the board), 
    and be formed linearly. Any blank tiles must be labeled.
  -}
  wordsFormedMidGame :: Board -> Map Pos Tile -> Either ScrabbleError FormedWords
  wordsFormedMidGame board tiles = placedSquares board tiles >>=
   \squares -> wordsFormed board squares >>= \formed ->
    let FormedWords x xs _  = formed
    -- Check it connects to at least one other word on the board
    in if Seq.length x > Map.size squares || not (Prelude.null xs)
           then Right $ FormedWords x xs squares
            else Left DoesNotConnectWithWord

  {- |
    Returns the main word formed by the played tiles. The main word is
    the linear stretch of tiles formed by the tiles placed.
  -}
  mainWord :: FormedWords -> FormedWord
  mainWord (FirstWord word) = word
  mainWord formed = main formed

  {- |
    Returns the list of words which were adjacent to the main word formed. 
  -}
  adjacentWords :: FormedWords -> [FormedWord]
  adjacentWords (FirstWord _) = []
  adjacentWords formed = otherWords formed

  {- | 
    Returns the list of positions mapped to the squares that the player placed their tiles on.
  -}
  playerPlaced :: FormedWords -> [(Pos, Square)]
  playerPlaced (FirstWord word) = Foldable.toList word
  playerPlaced formed = Map.toList $ placed formed

  {- |
    Scores the words formed by the tiles placed. The first item in the tuple is the overall
    score, while the second item is the list of scores for all the words formed.
  -}
  wordsWithScores :: FormedWords -> (Int, [(String, Int)])
  wordsWithScores (FirstWord firstWord) = 
      let score = scoreWord Seq.empty (fmap snd firstWord) 
      in (bingoBonus score (Seq.length firstWord), [(makeString firstWord, score)])
  wordsWithScores (FormedWords mainW others played) =
	  (bingoBonus (Prelude.sum scores) (Map.size played), Prelude.zip strings scores)
    where
      allWords = mainW : others
      strings = Prelude.map makeString allWords
      scores = Prelude.map (\formedWord -> let (notAlreadyPlaced, alreadyPlaced) = partitionPlaced formedWord 
                                           in scoreWord (fmap snd alreadyPlaced) (fmap snd notAlreadyPlaced) ) allWords
      partitionPlaced = Seq.partition (\(pos, _) -> Map.member pos played)
 

  {-
    It is a rule in scrabble that if the player manages to place all 7 letters, they receive a bonus of '50'
    to their score.
  -}
  bingoBonus :: Int -> Int -> Int
  bingoBonus score playedLetters = if playedLetters < 7 then score else score + 50

  {- |
    Returns true if the player placed all 7 of their letters while forming these words, incurring a + 50 score bonus.
  -}
  bingoBonusApplied :: FormedWords -> Bool
  bingoBonusApplied formed = Prelude.length (playerPlaced formed) == 7
  
  {- |
    Returns the words formed by the play as strings.
  -}
  wordStrings :: FormedWords -> [String]
  wordStrings (FirstWord word) = [makeString word]
  wordStrings formed = Prelude.map makeString $ main formed : otherWords formed

  makeString :: FormedWord -> String
  makeString word = M.mapMaybe (\(_, sq) -> tileIfOccupied sq >>= tileLetter) $ Foldable.toList word

  {-
    Checks that the tiles can be placed, and if so turns a map of the squares at the placed positions.
    A tile may be placed if the square is not already occupied, and if it is not an unlabeled blank tile.
  -}
  placedSquares :: Board -> Map Pos Tile -> Either ScrabbleError (Map Pos Square)
  placedSquares board tiles = squares
      where
        squares = Map.fromList <$> sequence ((\ (pos, tile) -> 
          posTileIfNotBlank (pos, tile) >>= squareIfUnoccupied) <$> mapAsList)

        posTileIfNotBlank (pos,tile) = 
          if tile == Blank Nothing then Left (CannotPlaceBlankWithoutLetter pos) else Right (pos, tile)
        squareIfUnoccupied (pos,tile) = maybe (Left (PlacedTileOnOccupiedSquare pos tile)) (\sq ->
         Right (pos, putTileOn sq tile)) $ unoccupiedSquareAt board pos
        mapAsList = Map.toList tiles

  wordsFormed :: Board -> Map Pos Square -> Either ScrabbleError FormedWords
  wordsFormed board tiles
    | Map.null tiles = Left NoTilesPlaced
    | otherwise = formedWords >>= \formed -> 
        case formed of
          x : xs -> Right $ FormedWords x xs tiles
          [] -> Left NoTilesPlaced
      where
        formedWords = maybe (Left $ MisplacedLetter maxPos) (\direction -> 
            middleFirstWord direction >>= (\middle -> 
                            let (midWord, _) = middle
                            in let mainLine = preceding direction minPos >< midWord >< after direction maxPos
                            in Right $ mainLine : adjacentToMain (swapDirection direction) ) ) getDirection

        preceding direction pos = case direction of
                                    Horizontal -> lettersLeft board pos
                                    Vertical -> lettersBelow board pos
        after direction pos =  case direction of
                                    Horizontal -> lettersRight board pos
                                    Vertical -> lettersAbove board pos

        (minPos, _) = Map.findMin tiles
        (maxPos, _) = Map.findMax tiles

        adjacentToMain direction = Prelude.filter (\word -> Seq.length word > 1) $ Prelude.map (\(pos, square) ->
         (preceding direction pos |> (pos, square)) >< after direction pos) placedList

        middleFirstWord direction =
         case placedList of 
              x:[] -> Right (Seq.singleton x, minPos)
              (x:xs) -> 
                foldM (\(word, lastPos) (pos, square) -> 
                  if not $ stillOnPath lastPos pos direction
                   then Left $ MisplacedLetter pos
                    else 
                      if isDirectlyAfter lastPos pos direction then Right (word |> (pos, square), pos) else
                        let between = after direction lastPos in
                        if expectedLettersInbetween direction lastPos pos between
                         then Right ( word >< ( between |> (pos,square) ), pos)
                          else Left $ MisplacedLetter pos
                ) (Seq.singleton x, minPos ) xs
              [] -> Left NoTilesPlaced

        placedList = Map.toAscList tiles

        stillOnPath lastPos thisPos direction = staticDirectionGetter direction thisPos == staticDirectionGetter direction lastPos
        expectedLettersInbetween direction lastPos currentPos between =
         Seq.length between + 1 == movingDirectionGetter direction currentPos - movingDirectionGetter direction lastPos

        swapDirection direction = if direction == Horizontal then Vertical else Horizontal

        getDirection
          -- If only one tile is placed, we look for the first tile it connects with if any. If it connects with none, we return 'Nothing'
          | (minPos == maxPos) && (not (Seq.null (lettersLeft board minPos)) || not (Seq.null (lettersRight board minPos))) = Just Horizontal
          | (minPos == maxPos) && (not (Seq.null (lettersBelow board minPos)) || not (Seq.null (lettersAbove board minPos))) = Just Vertical
          | xPos minPos == xPos maxPos = Just Vertical
          | yPos minPos == yPos maxPos = Just Horizontal
          | otherwise = Nothing

        staticDirectionGetter direction pos = if direction == Horizontal then yPos pos else xPos pos

        movingDirectionGetter direction pos = if direction == Horizontal then xPos pos else yPos pos

        isDirectlyAfter pos nextPos direction = movingDirectionGetter direction nextPos == movingDirectionGetter direction pos + 1
