import PlayingCard from './PlayingCard';

/**
 * CardFan - Displays cards in a fan/arc layout
 * Cards are rotated around a central pivot point with CSS transforms
 *
 * @param {number[]} cards - Array of card IDs
 * @param {number[]} selectedCards - Array of selected card IDs
 * @param {Function} onCardClick - Click handler for card selection
 * @param {boolean} disabled - Whether card selection is disabled
 * @param {number} cardWidth - Width of each card in pixels (default 80)
 * @param {number} maxSpreadAngle - Maximum spread angle in degrees (default 60)
 * @param {number} radius - Arc radius in pixels (default 300)
 */
function CardFan({
  cards = [],
  selectedCards = [],
  onCardClick,
  disabled = false,
  cardWidth = 80,
  maxSpreadAngle = 60,
  radius = 300,
}) {
  const cardCount = cards.length;

  if (cardCount === 0) {
    return null;
  }

  // Calculate spread angle based on card count (more cards = wider spread, up to max)
  const spreadAngle = Math.min(maxSpreadAngle, cardCount * 8);
  const startAngle = -spreadAngle / 2;
  const angleStep = cardCount > 1 ? spreadAngle / (cardCount - 1) : 0;

  return (
    <div className="card-fan" style={{ height: `${radius * 0.6}px` }}>
      {cards.map((cardId, index) => {
        const angle = startAngle + index * angleStep;
        const isSelected = selectedCards.includes(cardId);

        // Calculate position offset for fan effect
        // Cards rotate around bottom center, creating an arc
        const radians = (angle * Math.PI) / 180;
        const translateY = isSelected ? -30 : 0; // Lift selected cards

        return (
          <div
            key={`${cardId}-${index}`}
            className={`card-fan-item ${isSelected ? 'selected' : ''}`}
            style={{
              transform: `rotate(${angle}deg) translateY(${translateY}px)`,
              zIndex: index,
              '--card-angle': `${angle}deg`,
            }}
          >
            <PlayingCard
              cardId={cardId}
              selected={isSelected}
              onClick={() => onCardClick && onCardClick(cardId)}
              disabled={disabled}
              width={cardWidth}
            />
          </div>
        );
      })}
    </div>
  );
}

export default CardFan;
