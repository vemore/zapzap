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
  cardWidth = 110,
  maxSpreadAngle = 90,
  radius = 350,
}) {
  const cardCount = cards.length;

  if (cardCount === 0) {
    return null;
  }

  // Calculate spread angle based on card count (more cards = wider spread, up to max)
  // Using 15° per card for better spacing and easier click targets
  const spreadAngle = Math.min(maxSpreadAngle, cardCount * 15);
  const startAngle = -spreadAngle / 2;
  const angleStep = cardCount > 1 ? spreadAngle / (cardCount - 1) : 0;

  // Calculate horizontal spacing based on card count
  // More cards = less spacing per card, but still readable
  const horizontalSpacing = Math.max(25, 60 - cardCount * 5);

  return (
    <div className="card-fan" style={{ height: `${radius * 0.6}px` }}>
      {cards.map((cardId, index) => {
        const angle = startAngle + index * angleStep;
        const isSelected = selectedCards.includes(cardId);

        // Calculate horizontal offset from center
        const centerIndex = (cardCount - 1) / 2;
        const offsetFromCenter = index - centerIndex;
        const translateX = offsetFromCenter * horizontalSpacing;
        const translateY = isSelected ? -30 : 0; // Lift selected cards

        return (
          <div
            key={`${cardId}-${index}`}
            className={`card-fan-item ${isSelected ? 'selected' : ''}`}
            style={{
              transform: `translateX(${translateX}px) rotate(${angle}deg) translateY(${translateY}px)`,
              zIndex: index,
              '--card-angle': `${angle}deg`,
              '--card-translateX': `${translateX}px`,
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
