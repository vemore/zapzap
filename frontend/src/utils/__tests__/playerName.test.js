import { describe, it, expect } from 'vitest';
import { playerName } from '../playerName';

describe('playerName', () => {
  it('names a deleted player « Joueur supprimé »', () => {
    expect(playerName('deleted-1b2c', 'deleted-1b2c')).toBe('Joueur supprimé');
  });

  it('keeps anyone else’s username, even one that looks like a stand-in', () => {
    expect(playerName('u-1', 'alice')).toBe('alice');
    expect(playerName('u-2', 'deleted-fake')).toBe('deleted-fake');
    expect(playerName(undefined, 'bob')).toBe('bob');
  });
});
