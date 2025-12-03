import { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { Dice6, Loader } from 'lucide-react';
import { apiClient } from '../../services/api';
import { useAuth } from '../../contexts/AuthContext';
import PlayerTable from './PlayerTable';
import PlayerHand from './PlayerHand';
import ActionButtons from './ActionButtons';
import DeckPile from './DeckPile';
import DiscardPile from './DiscardPile';
import { isValidPlay, analyzePlay } from '../../utils/validation';
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

  // Fetch game state
  useEffect(() => {
    if (user) {
      fetchGameState();
    }
    // TODO: Set up SSE for real-time game updates
  }, [partyId, user]);

  const fetchGameState = async () => {
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

      // Transform API data to component format
      const transformedData = {
        partyId: data.party.id,
        partyName: data.party.name,
        players: data.players.map(p => ({
          userId: p.userId,
          playerIndex: p.playerIndex,
        })),
        currentTurnId: data.players[data.gameState.currentTurn]?.userId,
        currentAction: data.gameState.currentAction,
        myHand: data.gameState.playerHand || [],
        myUserId: user.id,
        deckSize: data.gameState.deckSize,
        lastCardsPlayed: data.gameState.lastCardsPlayed || [],
        cardsPlayed: data.gameState.cardsPlayed || [],
        otherPlayersHandSizes: data.gameState.otherPlayersHandSizes || {},
        round: data.round,
      };

      setGameData(transformedData);
      setError('');
    } catch (err) {
      console.error('Failed to load game state:', err);
      setError('Failed to load game state');
    } finally {
      setLoading(false);
    }
  };

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
    currentTurnId,
    currentAction = 'play',
    myHand = [],
    myUserId,
    deckSize = 0,
    lastCardsPlayed = [],
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

  return (
    <div className="min-h-screen bg-gradient-to-br from-slate-900 via-slate-800 to-slate-900">
      {/* Header */}
      <div className="bg-gradient-to-r from-slate-800 to-slate-700 border-b border-slate-600 shadow-lg">
        <div className="max-w-7xl mx-auto px-4 py-4 sm:px-6 lg:px-8">
          <div className="flex items-center justify-between">
            {/* Logo */}
            <div className="flex items-center">
              <Dice6 className="w-8 h-8 text-amber-400 mr-2" />
              <h1 className="text-2xl font-bold text-white">ZapZap Game</h1>
            </div>

            {/* Party info */}
            <div className="flex items-center">
              <span className="text-gray-300">
                Party: <span className="font-semibold text-white">{partyName || partyId}</span>
              </span>
            </div>
          </div>
        </div>
      </div>

      {/* Main game layout */}
      <div className="max-w-7xl mx-auto px-4 py-6 sm:px-6 lg:px-8">
        <div className="grid grid-cols-1 lg:grid-cols-4 gap-6">
          {/* Players sidebar */}
          <aside className="lg:col-span-1">
            <PlayerTable
              players={players}
              currentTurnId={currentTurnId}
              currentUserId={myUserId}
            />
          </aside>

          {/* Play area */}
          <main className="lg:col-span-3 space-y-6">
            {/* Deck and Discard pile section */}
            <section className="bg-slate-800 rounded-lg shadow-xl p-6 border border-slate-700">
              <div className="flex flex-col md:flex-row items-center justify-center gap-8">
                {/* Deck */}
                <DeckPile
                  cardsRemaining={deckSize}
                  onClick={onDrawFromDeck}
                  disabled={!isMyTurn || currentAction !== 'draw'}
                />

                {/* Divider */}
                <div className="hidden md:block w-px h-24 bg-slate-600" />
                <div className="md:hidden h-px w-24 bg-slate-600" />

                {/* Discard pile */}
                <DiscardPile
                  cards={lastCardsPlayed}
                  selectedCard={selectedDiscardCard}
                  onCardSelect={setSelectedDiscardCard}
                  disabled={!isMyTurn || currentAction !== 'draw'}
                />
              </div>
            </section>

            {/* My hand section */}
            <section>
              <PlayerHand
                hand={myHand}
                onCardsSelected={setSelectedCards}
                disabled={!isMyTurn}
              />
            </section>

            {/* Action buttons section */}
            <section>
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
          </main>
        </div>
      </div>
    </div>
  );
}

export default GameBoard;
