import { useState, useEffect, useCallback } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { Dice6, Loader, Wifi, WifiOff } from 'lucide-react';
import { apiClient } from '../../services/api';
import { useAuth } from '../../contexts/AuthContext';
import useSSE from '../../hooks/useSSE';
import PlayerTable from './PlayerTable';
import PlayerHand from './PlayerHand';
import ActionButtons from './ActionButtons';
import DeckPile from './DeckPile';
import TableArea from './TableArea';
import RoundEnd from './RoundEnd';
import HandSizeSelector from './HandSizeSelector';
import { isValidPlay, analyzePlay } from '../../utils/validation';
// Note: DiscardPile is now integrated into TableArea
import { isZapZapEligible } from '../../utils/scoring';

/**
 * GameBoard component - main game interface
 */
function GameBoard() {
  const { partyId } = useParams();
  const navigate = useNavigate();
  const { user } = useAuth();
  const [selectedCards, setSelectedCards] = useState([]);
  const [selectedDiscardCard, setSelectedDiscardCard] = useState(null);
  const [gameData, setGameData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [roundEndData, setRoundEndData] = useState(null);
  const [showRoundEnd, setShowRoundEnd] = useState(false);

  // Fetch game state function wrapped in useCallback for SSE handler
  const fetchGameState = useCallback(async () => {
    try {
      if (!user) {
        setError('User not authenticated');
        setLoading(false);
        return;
      }

      const response = await apiClient.get(`/game/${partyId}/state`);
      const data = response.data;

      // Check if game has started
      if (!data.gameState) {
        setError('Game has not started yet');
        setLoading(false);
        return;
      }

      // Get eliminated players from game state
      const eliminatedPlayers = data.gameState.eliminatedPlayers || [];

      // Transform API data to component format
      const transformedData = {
        partyId: data.party.id,
        partyName: data.party.name,
        players: data.players.map(p => ({
          userId: p.userId,
          playerIndex: p.playerIndex,
          username: p.username || `Player ${p.playerIndex + 1}`,
          cardCount: p.playerIndex === data.players.find(pl => pl.userId === user.id)?.playerIndex
            ? (data.gameState.playerHand || []).length
            : (data.gameState.otherPlayersHandSizes?.[p.playerIndex] || 0),
          score: data.gameState.scores?.[p.playerIndex] || 0,
          isEliminated: eliminatedPlayers.includes(p.playerIndex),
        })),
        isGoldenScore: data.gameState.isGoldenScore || false,
        eliminatedPlayers: eliminatedPlayers,
        currentTurn: data.gameState.currentTurn,
        currentTurnId: data.players[data.gameState.currentTurn]?.userId,
        currentAction: data.gameState.currentAction,
        myHand: data.gameState.playerHand || [],
        myUserId: user.id,
        deckSize: data.gameState.deckSize,
        lastCardsPlayed: data.gameState.lastCardsPlayed || [],
        cardsPlayed: data.gameState.cardsPlayed || [],
        otherPlayersHandSizes: data.gameState.otherPlayersHandSizes || {},
        lastAction: data.gameState.lastAction || null,
        round: data.round,
        // Round end data (only populated when currentAction === 'finished')
        allHands: data.gameState.allHands || null,
        handPoints: data.gameState.handPoints || null,
        zapZapCaller: data.gameState.zapZapCaller,
        lowestHandPlayerIndex: data.gameState.lowestHandPlayerIndex,
        wasCounterActed: data.gameState.wasCounterActed || false,
        counterActedByPlayerIndex: data.gameState.counterActedByPlayerIndex,
        roundScores: data.gameState.roundScores || null,
        // Game end data
        gameFinished: data.gameState.gameFinished || false,
        winner: data.gameState.winner || null,
      };

      setGameData(transformedData);
      setError('');
    } catch (err) {
      console.error('Failed to load game state:', err);
      setError('Failed to load game state');
    } finally {
      setLoading(false);
    }
  }, [partyId, user]);

  // Handle SSE messages for real-time game updates
  const handleSSEMessage = useCallback((data) => {
    // Only process events for this party
    if (data.partyId !== partyId) return;

    switch (data.action) {
      case 'play':
      case 'draw':
      case 'selectHandSize':
        // Refresh game state when any player plays, draws, or selects hand size
        fetchGameState();
        break;
      case 'zapzap':
        // Fetch game state and show round end
        fetchGameState().then(() => {
          // Round end data will be shown based on currentAction === 'finished'
        });
        break;
      case 'roundStarted':
        // New round started, refresh and hide round end screen
        setShowRoundEnd(false);
        setRoundEndData(null);
        fetchGameState();
        break;
      case 'gameFinished':
        // Game ended, navigate to results or lobby
        fetchGameState();
        break;
      case 'partyDeleted':
        // Party was deleted, go back to parties list
        navigate('/parties');
        break;
      default:
        break;
    }
  }, [partyId, fetchGameState, navigate]);

  // Set up SSE connection for real-time updates
  // Use VITE_API_URL if set (dev), otherwise use current origin (production)
  const baseUrl = import.meta.env.VITE_API_URL?.replace('/api', '') || window.location.origin;
  const sseUrl = `${baseUrl}/suscribeupdate`;
  const { connected: sseConnected } = useSSE(sseUrl, {
    onMessage: handleSSEMessage
  });

  // Fetch initial game state
  useEffect(() => {
    if (user) {
      fetchGameState();
    }
  }, [user, fetchGameState]);

  // Handle play cards
  const handlePlay = async (cards) => {
    try {
      await apiClient.post(`/game/${partyId}/play`, { cardIds: cards });
      await fetchGameState();
    } catch (err) {
      console.error('Failed to play cards:', err);
      setError(err.response?.data?.error || 'Failed to play cards');
    }
  };

  // Handle draw card
  const handleDraw = async (source = 'deck', cardId = undefined) => {
    try {
      const body = { source };
      if (cardId !== undefined) {
        body.cardId = cardId;
      }
      await apiClient.post(`/game/${partyId}/draw`, body);
      setSelectedDiscardCard(null);
      await fetchGameState();
    } catch (err) {
      console.error('Failed to draw card:', err);
      setError(err.response?.data?.error || 'Failed to draw card');
    }
  };

  // Handle ZapZap
  const handleZapZap = async () => {
    try {
      await apiClient.post(`/game/${partyId}/zapzap`);
      await fetchGameState();
    } catch (err) {
      console.error('Failed to call ZapZap:', err);
      setError(err.response?.data?.error || 'Failed to call ZapZap');
    }
  };

  // Handle select hand size
  const handleSelectHandSize = async (handSize) => {
    try {
      await apiClient.post(`/game/${partyId}/selectHandSize`, { handSize });
      await fetchGameState();
    } catch (err) {
      console.error('Failed to select hand size:', err);
      setError(err.response?.data?.error || 'Failed to select hand size');
      throw err;
    }
  };

  if (loading) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-slate-900 via-slate-800 to-slate-900 flex items-center justify-center">
        <div className="flex items-center text-white">
          <Loader className="w-8 h-8 mr-3 animate-spin text-amber-400" />
          <span className="text-xl">Loading game...</span>
        </div>
      </div>
    );
  }

  if (error || !gameData) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-slate-900 via-slate-800 to-slate-900 flex items-center justify-center">
        <div className="bg-slate-800 rounded-lg shadow-2xl p-8 border border-slate-700 text-center max-w-md">
          <h2 className="text-2xl font-bold text-white mb-4">Error</h2>
          <p className="text-gray-400 mb-6">{error || 'Failed to load game'}</p>
          <button
            onClick={() => navigate(`/party/${partyId}`)}
            className="px-6 py-3 bg-amber-500 hover:bg-amber-600 text-white font-semibold rounded-lg transition-colors"
          >
            Back to Lobby
          </button>
        </div>
      </div>
    );
  }

  const {
    partyName,
    players = [],
    currentTurn,
    currentTurnId,
    currentAction = 'play',
    myHand = [],
    myUserId,
    deckSize = 0,
    lastCardsPlayed = [],
    cardsPlayed = [],
    lastAction = null,
    isGoldenScore = false,
  } = gameData;

  const isMyTurn = currentTurnId === myUserId;
  const zapZapEligible = isZapZapEligible(myHand);

  // Validate selected cards
  let invalidPlay = null;
  if (selectedCards.length > 0) {
    const analysis = analyzePlay(selectedCards);
    if (!analysis.valid) {
      invalidPlay = analysis.reason;
    }
  }

  // Action handlers with validation
  const onPlayCards = (cards) => {
    if (isValidPlay(cards)) {
      handlePlay(cards);
      setSelectedCards([]);
    }
  };

  const onDrawFromDeck = () => {
    handleDraw('deck');
    setSelectedCards([]);
  };

  const onDrawFromDiscard = () => {
    if (selectedDiscardCard !== null) {
      handleDraw('played', selectedDiscardCard);
      setSelectedCards([]);
    }
  };

  const onCallZapZap = () => {
    handleZapZap();
  };

  // Handle continue to next round
  const handleContinueRound = async () => {
    try {
      await apiClient.post(`/game/${partyId}/nextRound`);
      setShowRoundEnd(false);
      setRoundEndData(null);
      await fetchGameState();
    } catch (err) {
      console.error('Failed to start next round:', err);
      setError(err.response?.data?.error || 'Failed to start next round');
    }
  };

  // Check if round is finished and prepare round end data
  const isRoundFinished = currentAction === 'finished';
  const isSelectHandSizePhase = currentAction === 'selectHandSize';

  // Get current player's username for display
  const currentPlayerName = players.find(p => p.playerIndex === currentTurn)?.username || `Player ${currentTurn + 1}`;

  // Show HandSizeSelector component if in select hand size phase
  if (isSelectHandSizePhase) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-slate-900 via-slate-800 to-slate-900">
        {/* Header */}
        <div className="bg-gradient-to-r from-slate-800 to-slate-700 border-b border-slate-600 shadow-lg">
          <div className="max-w-7xl mx-auto px-4 py-4 sm:px-6 lg:px-8">
            <div className="flex items-center justify-between">
              <div className="flex items-center">
                <Dice6 className="w-8 h-8 text-amber-400 mr-2" />
                <h1 className="text-2xl font-bold text-white">ZapZap Game</h1>
              </div>
              <div className="flex items-center space-x-4">
                {isGoldenScore && (
                  <div className="flex items-center bg-yellow-500/20 border border-yellow-500/50 rounded px-2 py-1 animate-pulse">
                    <span className="text-yellow-400 font-bold text-sm">GOLDEN SCORE</span>
                  </div>
                )}
                <div className="flex items-center" title={sseConnected ? 'Real-time updates active' : 'Connecting...'}>
                  {sseConnected ? (
                    <Wifi className="w-4 h-4 text-green-400" />
                  ) : (
                    <WifiOff className="w-4 h-4 text-gray-500 animate-pulse" />
                  )}
                </div>
                <span className="text-gray-300">
                  Party: <span className="font-semibold text-white">{partyName || partyId}</span>
                </span>
              </div>
            </div>
          </div>
        </div>

        {/* Hand Size Selection Content */}
        <div className="max-w-md mx-auto px-4 py-8 sm:px-6 lg:px-8">
          <div className="text-center mb-6">
            <p className="text-gray-400 text-lg">
              Round {gameData.round?.roundNumber || 1} - Starting
            </p>
          </div>
          <HandSizeSelector
            isMyTurn={isMyTurn}
            currentPlayerName={currentPlayerName}
            isGoldenScore={isGoldenScore}
            onSelectHandSize={handleSelectHandSize}
            disabled={false}
          />
        </div>
      </div>
    );
  }

  // Show RoundEnd component if round is finished
  if (isRoundFinished) {
    // Convert zapZapCaller from playerIndex to userId
    const zapZapCallerUserId = gameData.zapZapCaller !== null && gameData.zapZapCaller !== undefined
      ? players.find(p => p.playerIndex === gameData.zapZapCaller)?.userId || null
      : null;

    // Convert lowestHandPlayerIndex to userId
    const lowestHandUserId = gameData.lowestHandPlayerIndex !== null && gameData.lowestHandPlayerIndex !== undefined
      ? players.find(p => p.playerIndex === gameData.lowestHandPlayerIndex)?.userId || null
      : null;

    // Prepare round end data for the component
    const roundEndDisplayData = {
      roundNumber: gameData.round?.roundNumber || 1,
      players: players.map(p => {
        const isLowestHand = p.playerIndex === gameData.lowestHandPlayerIndex;
        const handPointsValue = gameData.handPoints?.[p.playerIndex] || 0;
        // Use backend-calculated round scores if available (includes counter penalty)
        // Otherwise fallback to simple calculation
        const roundScore = gameData.roundScores?.[p.playerIndex] ?? (isLowestHand ? 0 : handPointsValue);

        return {
          id: p.userId,
          username: p.username,
          hand: gameData.allHands?.[p.playerIndex] || [],
          score: roundScore, // This round's score (0 for lowest hand, or penalty for counteracted caller)
          totalScore: p.score,
          handValue: handPointsValue, // Hand value for display (with Joker=25)
          isLowestHand: isLowestHand,
        };
      }),
      zapZapCaller: zapZapCallerUserId,
      lowestHandPlayer: lowestHandUserId,
      wasCounterActed: gameData.wasCounterActed || false,
      counterActedByPlayerIndex: gameData.counterActedByPlayerIndex,
      // Game end data
      gameFinished: gameData.gameFinished || false,
      winner: gameData.winner || null,
    };

    return (
      <div className="min-h-screen bg-gradient-to-br from-slate-900 via-slate-800 to-slate-900">
        {/* Header */}
        <div className="bg-gradient-to-r from-slate-800 to-slate-700 border-b border-slate-600 shadow-lg">
          <div className="max-w-7xl mx-auto px-4 py-4 sm:px-6 lg:px-8">
            <div className="flex items-center justify-between">
              <div className="flex items-center">
                <Dice6 className="w-8 h-8 text-amber-400 mr-2" />
                <h1 className="text-2xl font-bold text-white">ZapZap Game</h1>
              </div>
              <div className="flex items-center space-x-4">
                <div className="flex items-center" title={sseConnected ? 'Real-time updates active' : 'Connecting...'}>
                  {sseConnected ? (
                    <Wifi className="w-4 h-4 text-green-400" />
                  ) : (
                    <WifiOff className="w-4 h-4 text-gray-500 animate-pulse" />
                  )}
                </div>
                <span className="text-gray-300">
                  Party: <span className="font-semibold text-white">{partyName || partyId}</span>
                </span>
              </div>
            </div>
          </div>
        </div>

        {/* Round End Content */}
        <div className="max-w-4xl mx-auto px-4 py-8 sm:px-6 lg:px-8">
          <RoundEnd
            roundData={roundEndDisplayData}
            onContinue={handleContinueRound}
            disabled={false}
          />
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen sm:h-auto flex flex-col bg-gradient-to-br from-slate-900 via-slate-800 to-slate-900 mobile-game-container">
      {/* Header - compact on mobile */}
      <div className="bg-gradient-to-r from-slate-800 to-slate-700 border-b border-slate-600 shadow-lg flex-shrink-0">
        <div className="max-w-7xl mx-auto px-2 py-2 sm:px-4 sm:py-3">
          <div className="flex items-center justify-between">
            {/* Logo - smaller on mobile */}
            <div className="flex items-center">
              <Dice6 className="w-5 h-5 sm:w-8 sm:h-8 text-amber-400 mr-1 sm:mr-2" />
              <h1 className="text-lg sm:text-2xl font-bold text-white">ZapZap</h1>
            </div>

            {/* Party info and SSE indicator */}
            <div className="flex items-center space-x-2 sm:space-x-4">
              {/* Golden Score indicator */}
              {isGoldenScore && (
                <div className="flex items-center bg-yellow-500/20 border border-yellow-500/50 rounded px-2 py-0.5 animate-pulse">
                  <span className="text-yellow-400 font-bold text-xs sm:text-sm">GOLDEN</span>
                </div>
              )}
              {/* SSE connection indicator */}
              <div className="flex items-center" title={sseConnected ? 'Real-time updates active' : 'Connecting...'}>
                {sseConnected ? (
                  <Wifi className="w-3 h-3 sm:w-4 sm:h-4 text-green-400" />
                ) : (
                  <WifiOff className="w-3 h-3 sm:w-4 sm:h-4 text-gray-500 animate-pulse" />
                )}
              </div>
              <span className="text-gray-300 text-xs sm:text-base truncate max-w-[100px] sm:max-w-none">
                <span className="font-semibold text-white">{partyName || partyId}</span>
              </span>
            </div>
          </div>
        </div>
      </div>

      {/* Main game layout */}
      <div className="flex-1 flex flex-col max-w-7xl mx-auto w-full px-2 py-1 sm:px-4 sm:py-4 gap-1 sm:gap-4">
        {/* Players row at top - horizontal scrollable on mobile */}
        <section className="flex-shrink-0">
          <PlayerTable
            players={players}
            currentTurn={currentTurn}
            currentUserId={myUserId}
            isGoldenScore={isGoldenScore}
          />
        </section>

        {/* Table area (tapis) - compact on mobile */}
        <section className="flex-shrink-0">
          <TableArea
            cardsPlayed={cardsPlayed}
            lastCardsPlayed={lastCardsPlayed}
            lastAction={lastAction}
            players={players}
            currentTurn={currentTurn}
            onDiscardSelect={isMyTurn && currentAction === 'draw' ? setSelectedDiscardCard : undefined}
            selectedDiscardCard={selectedDiscardCard}
          />
        </section>

        {/* My hand with integrated deck */}
        <section className="flex-1 min-h-[120px] sm:min-h-[200px]">
          <PlayerHand
            hand={myHand}
            onCardsSelected={setSelectedCards}
            disabled={!isMyTurn}
            deckSize={deckSize}
            onDrawFromDeck={onDrawFromDeck}
            canDrawFromDeck={isMyTurn && currentAction === 'draw'}
          />
        </section>

        {/* Action buttons */}
        <section className="flex-shrink-0">
          <ActionButtons
            selectedCards={selectedCards}
            onPlay={onPlayCards}
            onDrawFromDeck={onDrawFromDeck}
            onDrawFromDiscard={onDrawFromDiscard}
            onZapZap={onCallZapZap}
            currentAction={currentAction}
            isMyTurn={isMyTurn}
            zapZapEligible={zapZapEligible}
            invalidPlay={invalidPlay}
            hasDiscardSelection={selectedDiscardCard !== null}
            hasDiscardCards={lastCardsPlayed.length > 0}
          />
        </section>
      </div>
    </div>
  );
}

export default GameBoard;
