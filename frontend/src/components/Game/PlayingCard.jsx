import { useRef, useEffect } from 'react';
import { cardIdToCid, isJoker, getJokerType } from '../../utils/cardAdapter';

/**
 * PlayingCard - Wrapper component for cardmeister web component
 * Handles both standard cards (via cardmeister) and Jokers (custom SVG)
 *
 * @param {number} cardId - ZapZap card ID (0-53)
 * @param {boolean} selected - Whether the card is selected
 * @param {Function} onClick - Click handler
 * @param {boolean} disabled - Whether the card is disabled
 * @param {number} width - Card width in pixels (default 80)
 */
function PlayingCard({ cardId, selected = false, onClick, disabled = false, width = 80 }) {
  const cardRef = useRef(null);
  const height = Math.round(width * 1.4); // Standard playing card ratio

  // Handle Joker cards with custom SVG
  if (isJoker(cardId)) {
    const jokerType = getJokerType(cardId);
    const jokerSrc = jokerType === 'red' ? '/joker-red.svg' : '/joker-black.svg';

    return (
      <div
        className={`joker-card ${selected ? 'selected' : ''} ${disabled ? 'disabled' : ''}`}
        style={{ width: `${width}px`, height: `${height}px` }}
        onClick={disabled ? undefined : onClick}
        role="button"
        tabIndex={disabled ? -1 : 0}
        aria-label={`Joker ${jokerType}`}
        aria-selected={selected}
      >
        <img
          src={jokerSrc}
          alt={`Joker ${jokerType}`}
          style={{ width: '100%', height: '100%' }}
          draggable={false}
        />
      </div>
    );
  }

  // Handle standard cards with cardmeister web component
  const cid = cardIdToCid(cardId);

  // Update cardmeister attributes via ref (web components in React)
  useEffect(() => {
    if (cardRef.current) {
      cardRef.current.setAttribute('cid', cid);
    }
  }, [cid]);

  return (
    <div
      className={`playing-card-wrapper ${selected ? 'selected' : ''} ${disabled ? 'disabled' : ''}`}
      onClick={disabled ? undefined : onClick}
      role="button"
      tabIndex={disabled ? -1 : 0}
      aria-label={`Card ${cid}`}
      aria-selected={selected}
    >
      <playing-card
        ref={cardRef}
        cid={cid}
        style={{ width: `${width}px`, display: 'block' }}
      />
    </div>
  );
}

export default PlayingCard;
