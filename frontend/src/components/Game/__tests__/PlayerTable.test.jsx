import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import PlayerTable from '../PlayerTable';

// One row per player: "[icon] <name> [You] - <score> : <card backs> (<count>)".
// Every row carries a left border (`border-l-4`), green on the current turn.
const rowOf = (name) => screen.getByText(name).closest('.border-l-4');
const rowNames = (container) =>
  Array.from(container.querySelectorAll('.border-l-4')).map(
    (row) => row.querySelector('span.font-semibold').textContent
  );

describe('Phase 5: PlayerTable Component Tests', () => {
  const mockPlayers = [
    { userId: '1', playerIndex: 0, username: 'Alice', cardCount: 5, score: 0 },
    { userId: '2', playerIndex: 1, username: 'Bob', cardCount: 7, score: 10 },
    { userId: '3', playerIndex: 2, username: 'Charlie', cardCount: 3, score: 25 },
  ];

  describe('Player Display', () => {
    it('should render all players', () => {
      render(<PlayerTable players={mockPlayers} currentTurn={0} currentUserId="1" />);

      expect(screen.getByText('Alice')).toBeInTheDocument();
      expect(screen.getByText('Bob')).toBeInTheDocument();
      expect(screen.getByText('Charlie')).toBeInTheDocument();
    });

    it('should show card counts', () => {
      render(<PlayerTable players={mockPlayers} currentTurn={0} currentUserId="1" />);

      expect(rowOf('Alice')).toHaveTextContent('(5)');
      expect(rowOf('Bob')).toHaveTextContent('(7)');
      expect(rowOf('Charlie')).toHaveTextContent('(3)');
    });

    it('should show scores', () => {
      render(<PlayerTable players={mockPlayers} currentTurn={0} currentUserId="1" />);

      expect(rowOf('Alice')).toHaveTextContent(/-\s*0\s*:/);
      expect(rowOf('Bob')).toHaveTextContent(/-\s*10\s*:/);
      expect(rowOf('Charlie')).toHaveTextContent(/-\s*25\s*:/);
    });

    it('should handle empty players list', () => {
      const { container } = render(<PlayerTable players={[]} currentTurn={0} currentUserId="1" />);

      expect(container.textContent).toMatch(/no players|waiting/i);
    });
  });

  describe('Current Player Highlight', () => {
    it('should highlight current user', () => {
      render(<PlayerTable players={mockPlayers} currentTurn={1} currentUserId="1" />);

      // Alice is the current user, but not the current turn
      expect(rowOf('Alice').className).toMatch(/bg-amber-900/);
      expect(rowOf('Charlie').className).not.toMatch(/bg-amber-900/);
    });

    it('should show "You" indicator for current user', () => {
      render(<PlayerTable players={mockPlayers} currentTurn={1} currentUserId="1" />);

      expect(screen.getAllByText('You')).toHaveLength(1);
      expect(rowOf('Alice')).toHaveTextContent('You');
    });
  });

  describe('Turn Indicator', () => {
    it('should highlight current turn player', () => {
      render(<PlayerTable players={mockPlayers} currentTurn={1} currentUserId="1" />);

      // Bob (playerIndex 1) has the turn
      expect(rowOf('Bob').className).toMatch(/border-green-400/);
      expect(rowOf('Alice').className).not.toMatch(/border-green-400/);
      expect(rowOf('Charlie').className).not.toMatch(/border-green-400/);
    });

    it('should show turn indicator icon', () => {
      render(<PlayerTable players={mockPlayers} currentTurn={1} currentUserId="1" />);

      // A play icon marks the row whose turn it is, and only that one
      expect(rowOf('Bob').querySelector('.lucide-play')).not.toBeNull();
      expect(rowOf('Alice').querySelector('.lucide-play')).toBeNull();
      expect(rowOf('Charlie').querySelector('.lucide-play')).toBeNull();
    });

    it('should not give the turn to an eliminated player', () => {
      const players = mockPlayers.map((p) =>
        p.playerIndex === 1 ? { ...p, isEliminated: true } : p
      );
      render(<PlayerTable players={players} currentTurn={1} currentUserId="1" />);

      expect(rowOf('Bob').className).not.toMatch(/border-green-400/);
      expect(rowOf('Bob').querySelector('.lucide-play')).toBeNull();
    });
  });

  describe('Player Ordering', () => {
    it('should display players in order', () => {
      const { container } = render(
        <PlayerTable players={mockPlayers} currentTurn={0} currentUserId="1" />
      );

      expect(rowNames(container)).toEqual(['Alice', 'Bob', 'Charlie']);
    });

    it('should start the order at the round starting player', () => {
      const { container } = render(
        <PlayerTable players={mockPlayers} currentTurn={1} currentUserId="1" startingPlayer={1} />
      );

      expect(rowNames(container)).toEqual(['Bob', 'Charlie', 'Alice']);
    });

    it('should handle current user at different positions', () => {
      render(<PlayerTable players={mockPlayers} currentTurn={2} currentUserId="3" />);

      // Charlie should be marked as "You"
      expect(rowOf('Charlie')).toHaveTextContent('You');
      expect(rowOf('Alice')).not.toHaveTextContent('You');
    });
  });

  describe('Card Count Display', () => {
    it('should show the count for 1 card', () => {
      const singleCardPlayers = [
        { userId: '1', playerIndex: 0, username: 'Solo', cardCount: 1, score: 0 },
      ];
      render(<PlayerTable players={singleCardPlayers} currentTurn={0} currentUserId="1" />);

      expect(rowOf('Solo')).toHaveTextContent('(1)');
    });

    it('should show one card back per card', () => {
      render(<PlayerTable players={mockPlayers} currentTurn={0} currentUserId="1" />);

      expect(rowOf('Alice').querySelectorAll('.card-back')).toHaveLength(5);
      expect(rowOf('Charlie').querySelectorAll('.card-back')).toHaveLength(3);
    });

    it('should show 0 cards when hand is empty', () => {
      const emptyHandPlayers = [
        { userId: '1', playerIndex: 0, username: 'Empty', cardCount: 0, score: 0 },
      ];
      render(<PlayerTable players={emptyHandPlayers} currentTurn={0} currentUserId="1" />);

      expect(rowOf('Empty')).toHaveTextContent('(0)');
      expect(rowOf('Empty').querySelectorAll('.card-back')).toHaveLength(0);
    });

    it('should hide the hand of an eliminated player', () => {
      const players = [
        { userId: '1', playerIndex: 0, username: 'Out', cardCount: 4, score: 105, isEliminated: true },
      ];
      render(<PlayerTable players={players} currentTurn={0} currentUserId="2" />);

      expect(rowOf('Out')).toHaveTextContent('--');
      expect(rowOf('Out').querySelectorAll('.card-back')).toHaveLength(0);
    });
  });

  describe('Visual Styling', () => {
    it('should have different styles for current user and current turn', () => {
      render(<PlayerTable players={mockPlayers} currentTurn={1} currentUserId="1" />);

      // Both should have different styling classes
      expect(rowOf('Alice').className).not.toBe(rowOf('Bob').className);
    });
  });
});
