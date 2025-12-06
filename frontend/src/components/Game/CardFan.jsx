import { useState, useEffect } from 'react';
import PlayingCard from './PlayingCard';

/**
 * CardFan - Displays cards in a fan/arc layout
 * Cards are rotated around a central pivot point with CSS transforms
 * Responsive: uses smaller cards and tighter layout on mobile
 *
 * @param {number[]} cards - Array of card IDs
 * @param {number[]} selectedCards - Array of selected card IDs
 * @param {Function} onCardClick - Click handler for card selection
 * @param {boolean} disabled - Whether card selection is disabled
 * @param {number} cardWidth - Width of each card in pixels for desktop (default 70)
 * @param {number} mobileCardWidth - Width of each card in pixels for mobile (default 50)
 * @param {number} maxSpreadAngle - Maximum spread angle in degrees (default 60)
 */
function CardFan({
  cards = [],
  selectedCards = [],
  onCardClick,
  disabled = false,
  cardWidth = 70,
  mobileCardWidth = 50,
  maxSpreadAngle = 75,
}) {
  const [isMobile, setIsMobile] = useState(false);

  // Detect mobile viewport
  useEffect(() => {
    const checkMobile = () => setIsMobile(window.innerWidth < 640);
    checkMobile();
    window.addEventListener('resize', checkMobile);
    return () => window.removeEventListener('resize', checkMobile);
  }, []);

  const cardCount = cards.length;

  if (cardCount === 0) {
    return null;
  }

  // Use responsive values
  const effectiveCardWidth = isMobile ? mobileCardWidth : cardWidth;
  const effectiveMaxAngle = isMobile ? Math.min(maxSpreadAngle, 50) : maxSpreadAngle;

  // Calculate spread angle based on card count (more cards = wider spread, up to max)
  // Using smaller angle per card on mobile
  const anglePerCard = isMobile ? 8 : 12;
  const spreadAngle = Math.min(effectiveMaxAngle, cardCount * anglePerCard);
  const startAngle = -spreadAngle / 2;
  const angleStep = cardCount > 1 ? spreadAngle / (cardCount - 1) : 0;

  // Calculate horizontal spacing based on card count
  // Tighter spacing on mobile
  const baseSpacing = isMobile ? 30 : 50;
  const spacingReduction = isMobile ? 3 : 4;
  const minSpacing = isMobile ? 18 : 25;
  const horizontalSpacing = Math.max(minSpacing, baseSpacing - cardCount * spacingReduction);

  // Dynamic height based on device
  const fanHeight = isMobile ? 100 : 150;

  return (
    <div
      className="card-fan relative flex items-end justify-center"
      style={{ height: `${fanHeight}px`, minHeight: `${fanHeight}px` }}
    >
      {cards.map((cardId, index) => {
        const angle = startAngle + index * angleStep;
        const isSelected = selectedCards.includes(cardId);

        // Calculate horizontal offset from center
        const centerIndex = (cardCount - 1) / 2;
        const offsetFromCenter = index - centerIndex;
        const translateX = offsetFromCenter * horizontalSpacing;
        const translateY = isSelected ? (isMobile ? -15 : -25) : 0; // Lift selected cards

        return (
          <div
            key={`${cardId}-${index}`}
            className={`card-fan-item absolute bottom-0 ${isSelected ? 'selected' : ''}`}
            style={{
              transform: `translateX(${translateX}px) rotate(${angle}deg) translateY(${translateY}px)`,
              zIndex: isSelected ? 100 : index,
              transformOrigin: 'bottom center',
              '--card-angle': `${angle}deg`,
              '--card-translateX': `${translateX}px`,
            }}
          >
            <PlayingCard
              cardId={cardId}
              selected={isSelected}
              onClick={() => onCardClick && onCardClick(cardId)}
              disabled={disabled}
              width={effectiveCardWidth}
            />
          </div>
        );
      })}
    </div>
  );
}

export default CardFan;
