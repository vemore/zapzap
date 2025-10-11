// player.test.js
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
    it('should add a card to the player\'s hand', () => {
      const player = new Player('John Doe', 1);
      const card = { suit: 'Hearts', rank: 'Ace' };
      player.draw(card);

      expect(player.hand).toEqual([card]);
    });

    it('should throw an error if no player is created', () => {
      expect(() => player.draw(card)).toThrowError();
    });
  });

  describe('#play()', () => {
    it('should remove a card from the player\'s hand', () => {
      const player = new Player('John Doe', 1);
      const card1 = { suit: 'Hearts', rank: 'Ace' };
      player.draw(card1);
      player.play([card1]);

      expect(player.hand).toEqual([]);
    });

    it('should not remove a card from the player\'s hand if it does not exist', () => {
      const player = new Player('John Doe', 1);
      const card1 = { suit: 'Hearts', rank: 'Ace' };
      const card2 = { suit: 'Diamonds', rank: 'Ace' };
      player.draw(card1);
      player.play([card2]);

      expect(player.hand).toEqual([card1]);
    });
    it('should not remove more cards than the player has in hand', () => {
      const player = new Player('John Doe', 1);
      const card1 = { suit: 'Hearts', rank: 'Ace' };
      player.draw(card1);
      player.play([card1]);

      expect(player.hand).toEqual([]);
    });

    it('should log an error if the card to be played is not in the player\'s hand', () => {
      const player = new Player('John Doe', 1);
      const card1 = { suit: 'Hearts', rank: 'Ace' };
      player.draw(card1);

      jest.spyOn(console, 'log').mockImplementation(() => {
        console.log('ERROR : play card ...');
      });

      expect(() => player.play([card2])).toThrowError();
    });
  });

  describe('#hand_points()', () => {
    it('should calculate points for all cards in the player\'s hand', () => {
      const player = new Player('John Doe', 1);
      const card1 = { suit: 'Hearts', rank: 'Ace' };
      const card2 = { suit: 'Diamonds', rank: 'King' };

      

      player.draw(card1);
      player.draw(card2);

      expect(player.hand_points).toBe(14); // assuming get_card_points returns 1 for Ace and 13 for King
    });

    it('should throw an error if no cards are in the player\'s hand', () => {
      const player = new Player('John Doe', 1);
      expect(() => player.hand_points()).toThrowError();
    });
  });

  describe('#hand_points_with_joker()', () => {
    it('should calculate points for all cards in the player\'s hand, including a joker card', () => {
      const player = new Player('John Doe', 1);
      const card1 = { suit: 'Hearts', rank: 'Ace' };
      const card2 = { suit: 'Diamonds', rank: 'King' };

      player.draw(card1);
      player.draw({ ...card2, type: 'joker' }); // assuming a joker card has a specific type

      expect(player.hand_points_with_joker()).toBe(30); // assuming get_card_points returns 15 for Ace and 15 for King
    });

    it('should throw an error if no cards are in the player\'s hand', () => {
      const player = new Player('John Doe', 1);
      expect(() => player.hand_points_with_joker()).toThrowError();
    });
  });
});

describe('#sethand()', () => {
  it('should update the player\'s hand with a new array of cards', () => {
    const player = new Player('John Doe', 1);
    const card1 = { suit: 'Hearts', rank: 'Ace' };
    const card2 = { suit: 'Diamonds', rank: 'King' };

    player.draw(card1);
    player.sethand([card2]);

    expect(player.hand).toEqual([card1, card2]);
  });

  it('should throw an error if no player is created', () => {
    expect(() => player.sethand([card1])).toThrowError();
  });
});

describe('#zapzap()', () => {
  // TODO: implement this method
});