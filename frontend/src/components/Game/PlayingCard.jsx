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
  // Calculate border radius based on card width (~5% of width, minimum 2px)
  const borderRadius = Math.max(2, Math.round(width * 0.05));
  const joker = isJoker(cardId);
  const cid = joker ? null : cardIdToCid(cardId);

  // Update cardmeister attributes via ref (web components in React).
  // Called before the joker branch: a hook must run on every render, or a card
  // switching between joker and standard breaks React's hook order.
  useEffect(() => {
    if (cardRef.current && cid) {
      cardRef.current.setAttribute('cid', cid);
    }
  }, [cid]);

  // Handle Joker cards with custom SVG
  if (joker) {
    const jokerType = getJokerType(cardId);
    const jokerSrc = jokerType === 'red' ? '/joker-red.svg' : '/joker-black.svg';

    return (
      <div
        className={`joker-card ${selected ? 'selected' : ''} ${disabled ? 'disabled' : ''}`}
        style={{ width: `${width}px`, height: `${height}px`, borderRadius: `${borderRadius}px` }}
        onClick={disabled ? undefined : onClick}
        role="button"
        tabIndex={disabled ? -1 : 0}
        aria-label={`Joker ${jokerType}`}
        aria-selected={selected}
      >
        <img
          src={jokerSrc}
          alt={`Joker ${jokerType}`}
          style={{ width: '100%', height: '100%', borderRadius: `${borderRadius}px` }}
          draggable={false}
        />
      </div>
    );
  }

  // Handle standard cards with cardmeister web component
  return (
    <div
      className={`playing-card-wrapper ${selected ? 'selected' : ''} ${disabled ? 'disabled' : ''}`}
      style={{ borderRadius: `${borderRadius}px` }}
      onClick={disabled ? undefined : onClick}
      role="button"
      tabIndex={disabled ? -1 : 0}
      aria-label={`Card ${cid}`}
      aria-selected={selected}
    >
      <playing-card
        ref={cardRef}
        cid={cid}
        style={{ width: `${width}px`, display: 'block', '--card-border-radius': `${borderRadius}px` }}
      />
    </div>
  );
}

export default PlayingCard;
