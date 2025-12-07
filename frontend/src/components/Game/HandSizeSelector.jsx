import { useState } from 'react';
import { Loader, Hand } from 'lucide-react';

/**
 * HandSizeSelector component
 * Allows the starting player to select the number of cards to deal at the beginning of a round
 */
function HandSizeSelector({
  isMyTurn,
  currentPlayerName,
  isGoldenScore,
  onSelectHandSize,
  disabled
}) {
  // Golden Score (2 players): 4-10 cards
  // Normal (3+ players): 4-7 cards
  const minHandSize = 4;
  const maxHandSize = isGoldenScore ? 10 : 7;

  const [selectedSize, setSelectedSize] = useState(Math.floor((minHandSize + maxHandSize) / 2));
  const [loading, setLoading] = useState(false);

  const handleConfirm = async () => {
    if (loading || disabled) return;
    setLoading(true);
    try {
      await onSelectHandSize(selectedSize);
    } catch (error) {
      console.error('Failed to select hand size:', error);
    } finally {
      setLoading(false);
    }
  };

  // Generate array of valid hand sizes
  const handSizes = Array.from(
    { length: maxHandSize - minHandSize + 1 },
    (_, i) => minHandSize + i
  );

  if (!isMyTurn) {
    // Waiting for another player to select
    return (
      <div className="bg-slate-800/90 rounded-xl p-6 border border-slate-600 shadow-2xl text-center">
        <div className="flex items-center justify-center mb-4">
          <Loader className="w-8 h-8 text-amber-400 animate-spin mr-3" />
          <h2 className="text-xl font-bold text-white">Waiting...</h2>
        </div>
        <p className="text-gray-300">
          <span className="font-semibold text-amber-400">{currentPlayerName}</span> is selecting the number of cards
        </p>
      </div>
    );
  }

  return (
    <div className="bg-slate-800/90 rounded-xl p-6 border border-amber-400/50 shadow-2xl">
      {/* Header */}
      <div className="flex items-center justify-center mb-6">
        <Hand className="w-8 h-8 text-amber-400 mr-3" />
        <h2 className="text-xl font-bold text-white">Select Hand Size</h2>
      </div>

      {/* Info text */}
      <p className="text-gray-300 text-center mb-6">
        Choose how many cards each player will receive
        {isGoldenScore && (
          <span className="block text-yellow-400 text-sm mt-1">
            Golden Score mode: 4-10 cards available
          </span>
        )}
      </p>

      {/* Hand size buttons */}
      <div className="flex flex-wrap justify-center gap-2 mb-6">
        {handSizes.map((size) => (
          <button
            key={size}
            onClick={() => setSelectedSize(size)}
            disabled={loading || disabled}
            className={`
              w-12 h-12 rounded-lg font-bold text-lg transition-all
              ${selectedSize === size
                ? 'bg-amber-500 text-white ring-2 ring-amber-300 scale-110'
                : 'bg-slate-700 text-gray-300 hover:bg-slate-600 hover:text-white'
              }
              disabled:opacity-50 disabled:cursor-not-allowed
            `}
          >
            {size}
          </button>
        ))}
      </div>

      {/* Selected info */}
      <div className="text-center mb-6">
        <span className="text-gray-400">Selected: </span>
        <span className="text-2xl font-bold text-amber-400">{selectedSize}</span>
        <span className="text-gray-400"> cards per player</span>
      </div>

      {/* Confirm button */}
      <button
        onClick={handleConfirm}
        disabled={loading || disabled}
        className="w-full bg-amber-500 hover:bg-amber-600 text-white font-semibold py-3 rounded-lg transition-colors shadow-lg disabled:opacity-60 disabled:cursor-not-allowed flex items-center justify-center"
      >
        {loading ? (
          <>
            <Loader className="w-5 h-5 animate-spin mr-2" />
            Dealing cards...
          </>
        ) : (
          'Confirm & Deal Cards'
        )}
      </button>
    </div>
  );
}

export default HandSizeSelector;
