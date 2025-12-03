import { useRef, useEffect } from 'react';

/**
 * CardBack - Shows the back of a playing card
 * Uses cardmeister web component with back cid
 *
 * @param {string} size - Size: 'sm', 'md', 'lg' (default: 'md')
 * @param {string} className - Additional CSS classes
 */
function CardBack({ size = 'md', className = '' }) {
  const cardRef = useRef(null);

  const sizes = {
    sm: 40,
    md: 60,
    lg: 80
  };

  const width = sizes[size] || sizes.md;

  useEffect(() => {
    if (cardRef.current) {
      cardRef.current.setAttribute('cid', 'back');
    }
  }, []);

  return (
    <div className={`card-back ${className}`}>
      <playing-card
        ref={cardRef}
        cid="back"
        style={{ width: `${width}px`, display: 'block' }}
      />
    </div>
  );
}

export default CardBack;
