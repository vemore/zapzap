import { motion } from 'framer-motion';
import PlayingCard from './PlayingCard';
import CardBack from './CardBack';

/**
 * AnimatedCard - Wrapper for cards with framer-motion animations
 *
 * @param {number} cardId - Card ID to display (or undefined for back)
 * @param {string} animation - Animation type: 'play', 'draw', 'take', 'enter', 'exit'
 * @param {number} delay - Animation delay in seconds
 * @param {boolean} showBack - Show card back instead of face
 * @param {string} size - Size for card back: 'sm', 'md', 'lg'
 * @param {number} width - Width for PlayingCard
 * @param {Function} onClick - Click handler
 * @param {boolean} selected - Is card selected
 * @param {boolean} disabled - Is card disabled
 */
function AnimatedCard({
  cardId,
  animation = 'enter',
  delay = 0,
  showBack = false,
  size = 'md',
  width = 80,
  onClick,
  selected = false,
  disabled = false
}) {
  const animations = {
    // Card played from hand to table
    play: {
      initial: { y: 100, opacity: 0, scale: 0.5, rotate: -10 },
      animate: { y: 0, opacity: 1, scale: 1, rotate: 0 },
      transition: { type: 'spring', damping: 15, stiffness: 300, delay }
    },
    // Card drawn from deck
    draw: {
      initial: { x: -100, y: -50, opacity: 0, rotate: -15 },
      animate: { x: 0, y: 0, opacity: 1, rotate: 0 },
      transition: { duration: 0.4, ease: 'easeOut', delay }
    },
    // Card taken from discard
    take: {
      initial: { scale: 1.2, opacity: 1 },
      animate: { scale: 1, opacity: 1 },
      transition: { duration: 0.3, delay }
    },
    // Generic enter animation
    enter: {
      initial: { y: -50, opacity: 0, scale: 0.8 },
      animate: { y: 0, opacity: 1, scale: 1 },
      transition: { type: 'spring', damping: 20, stiffness: 300, delay }
    },
    // Card exit animation
    exit: {
      initial: { opacity: 1, scale: 1 },
      animate: { opacity: 0, scale: 0.5, y: 50 },
      transition: { duration: 0.3, delay }
    },
    // No animation
    none: {
      initial: {},
      animate: {},
      transition: {}
    }
  };

  const anim = animations[animation] || animations.enter;

  return (
    <motion.div
      initial={anim.initial}
      animate={anim.animate}
      transition={anim.transition}
      layout
    >
      {showBack ? (
        <CardBack size={size} />
      ) : (
        <PlayingCard
          cardId={cardId}
          width={width}
          onClick={onClick}
          selected={selected}
          disabled={disabled}
        />
      )}
    </motion.div>
  );
}

export default AnimatedCard;
