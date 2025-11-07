import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import PlayerTable from '../PlayerTable';

describe('Phase 5: PlayerTable Component Tests', () => {
  const mockPlayers = [
    { id: '1', username: 'Alice', cardCount: 5, score: 0 },
    { id: '2', username: 'Bob', cardCount: 7, score: 10 },
    { id: '3', username: 'Charlie', cardCount: 3, score: 25 },
  ];

  describe('Player Display', () => {
    it('should render all players', () => {
      render(<PlayerTable players={mockPlayers} currentTurnId="1" currentUserId="1" />);

      expect(screen.getByText('Alice')).toBeInTheDocument();
      expect(screen.getByText('Bob')).toBeInTheDocument();
      expect(screen.getByText('Charlie')).toBeInTheDocument();
    });

    it('should show card counts', () => {
      render(<PlayerTable players={mockPlayers} currentTurnId="1" currentUserId="1" />);

      expect(screen.getByText(/5 cards?/i)).toBeInTheDocument();
      expect(screen.getByText(/7 cards?/i)).toBeInTheDocument();
      expect(screen.getByText(/3 cards?/i)).toBeInTheDocument();
    });

    it('should show scores', () => {
      const { container } = render(<PlayerTable players={mockPlayers} currentTurnId="1" currentUserId="1" />);

      const statValues = Array.from(container.querySelectorAll('.stat-value')).map(
        (el) => el.textContent.trim()
      );

      // Should include score values (0, 10, 25)
      expect(statValues).toContain('0');
      expect(statValues).toContain('10');
      expect(statValues).toContain('25');
    });

    it('should handle empty players list', () => {
      const { container } = render(<PlayerTable players={[]} currentTurnId="1" currentUserId="1" />);

      expect(container.textContent).toMatch(/no players|waiting/i);
    });
  });

  describe('Current Player Highlight', () => {
    it('should highlight current user', () => {
      const { container } = render(<PlayerTable players={mockPlayers} currentTurnId="2" currentUserId="1" />);

      // Alice should be highlighted as current user
      const players = container.querySelectorAll('.player-card');
      const aliceCard = Array.from(players).find(p => p.textContent.includes('Alice'));
      expect(aliceCard.className).toMatch(/current-user|you/i);
    });

    it('should show "You" indicator for current user', () => {
      render(<PlayerTable players={mockPlayers} currentTurnId="2" currentUserId="1" />);

      expect(screen.getByText(/you/i)).toBeInTheDocument();
    });
  });

  describe('Turn Indicator', () => {
    it('should highlight current turn player', () => {
      const { container } = render(<PlayerTable players={mockPlayers} currentTurnId="2" currentUserId="1" />);

      // Bob should be highlighted as current turn
      const players = container.querySelectorAll('.player-card');
      const bobCard = Array.from(players).find(p => p.textContent.includes('Bob'));
      expect(bobCard.className).toMatch(/current-turn|active/i);
    });

    it('should show turn indicator icon', () => {
      render(<PlayerTable players={mockPlayers} currentTurnId="2" currentUserId="1" />);

      // Should have a visual indicator for Bob's turn
      const bobSection = screen.getByText('Bob').closest('.player-card');
      expect(bobSection.textContent).toMatch(/turn|playing|▶/i);
    });
  });

  describe('Player Ordering', () => {
    it('should display players in order', () => {
      const { container } = render(<PlayerTable players={mockPlayers} currentTurnId="1" currentUserId="1" />);

      const players = container.querySelectorAll('.player-card');
      expect(players[0].textContent).toMatch(/Alice/i);
      expect(players[1].textContent).toMatch(/Bob/i);
      expect(players[2].textContent).toMatch(/Charlie/i);
    });

    it('should handle current user at different positions', () => {
      render(<PlayerTable players={mockPlayers} currentTurnId="3" currentUserId="3" />);

      // Charlie should be marked as "You"
      const charlieSection = screen.getByText('Charlie').closest('.player-card');
      expect(charlieSection.textContent).toMatch(/you/i);
    });
  });

  describe('Card Count Display', () => {
    it('should show singular "card" for 1 card', () => {
      const singleCardPlayers = [
        { id: '1', username: 'Solo', cardCount: 1, score: 0 },
      ];
      render(<PlayerTable players={singleCardPlayers} currentTurnId="1" currentUserId="1" />);

      expect(screen.getByText(/1 card(?!s)/i)).toBeInTheDocument();
    });

    it('should show plural "cards" for multiple cards', () => {
      render(<PlayerTable players={mockPlayers} currentTurnId="1" currentUserId="1" />);

      expect(screen.getByText(/5 cards/i)).toBeInTheDocument();
    });

    it('should show 0 cards when hand is empty', () => {
      const emptyHandPlayers = [
        { id: '1', username: 'Empty', cardCount: 0, score: 0 },
      ];
      render(<PlayerTable players={emptyHandPlayers} currentTurnId="1" currentUserId="1" />);

      expect(screen.getByText(/0 cards/i)).toBeInTheDocument();
    });
  });

  describe('Visual Styling', () => {
    it('should have different styles for current user and current turn', () => {
      const { container } = render(<PlayerTable players={mockPlayers} currentTurnId="2" currentUserId="1" />);

      const players = container.querySelectorAll('.player-card');
      const aliceCard = Array.from(players).find(p => p.textContent.includes('Alice'));
      const bobCard = Array.from(players).find(p => p.textContent.includes('Bob'));

      // Both should have different styling classes
      expect(aliceCard.className).not.toBe(bobCard.className);
    });
  });
});
