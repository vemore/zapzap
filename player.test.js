const { Player } = require('./player.js');

describe('Player', () => {
  describe('#constructor()', () => {
    it('should initialize player with name and id', () => {
      const player = new Player('John Doe', 1);
      expect(player.name).toBe('John Doe');
      expect(player.id).toBe(1);
    });

    it('should throw an error if name is empty or null', () => {
      expect(() => new Player('', 1)).toThrowError();
      expect(() => new Player(null, 1)).toThrowError();
    });
  });

  describe('#draw()', () => {
    it('should add a card to player hand', () => {
      const player = new Player('John Doe', 1);
      const card = { rank: { shortName: 'A' }, suit: { unicode: '♥' } };
      player.draw(card);
      expect(player.hand).toEqual([card]);
    });
  });

  describe('#play()', () => {
    it('should remove cards from player hand', () => {
      const player = new Player('John Doe', 1);
      const card1 = { rank: { shortName: 'A' }, suit: { unicode: '♥' } };
      const card2 = { rank: { shortName: 'K' }, suit: { unicode: '♦' } };
      
      player.draw(card1);
      player.draw(card2);
      player.play([card1]);

      expect(player.hand).toEqual([card2]);
    });
  });

  describe('#hand_points()', () => {
    it('should calculate correct points without jokers', () => {
      const player = new Player('John Doe', 1);
      const card1 = { rank: { shortName: 'A' }, suit: { unicode: '♥' } };
      const card2 = { rank: { shortName: 'K' }, suit: { unicode: '♦' } };
      
      player.draw(card1);
      player.draw(card2);

      expect(player.hand_points).toBe(14); // Ace = 1, King = 13
    });

    it('should return 0 if no cards in hand', () => {
      const player = new Player('John Doe', 1);
      expect(player.hand_points).toBe(0);
    });
  });

  describe('#hand_points_with_joker()', () => {
    it('should calculate points including jokers', () => {
      const player = new Player('John Doe', 1);
      const card1 = { rank: { shortName: 'A' }, suit: { unicode: '♥' } };
      const joker = { rank: { shortName: 'Joker' }, suit: { unicode: null } };

      player.draw(card1);
      player.draw(joker);

      expect(player.hand_points_with_joker).toBe(26); // Ace = 1, Joker = 25
    });

    it('should return 0 if no cards in hand', () => {
      const player = new Player('John Doe', 1);
      expect(player.hand_points_with_joker).toBe(0);
    });
  });

  describe('#sethand()', () => {
    it('should set player hand to given cards', () => {
      const player = new Player('John Doe', 1);
      const cards = [
        { rank: { shortName: 'A' }, suit: { unicode: '♥' } },
        { rank: { shortName: 'K' }, suit: { unicode: '♦' } }
      ];
      
      player.sethand(cards);
      expect(player.hand).toEqual(cards);
    });
  });
});