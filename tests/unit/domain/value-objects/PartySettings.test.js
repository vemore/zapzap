/**
 * Unit tests for PartySettings Value Object
 *
 * The hand size is no longer a party setting: the starting player picks it at the
 * start of each round (GAME_RULES.md, src/use-cases/game/SelectHandSize.js).
 */

const PartySettings = require('../../../../src/domain/value-objects/PartySettings');

describe('PartySettings Value Object', () => {
    describe('Constructor', () => {
        it('should create settings with valid properties', () => {
            const settings = new PartySettings({
                playerCount: 5,
                allowSpectators: true,
                roundTimeLimit: 300
            });

            expect(settings.playerCount).toBe(5);
            expect(settings.allowSpectators).toBe(true);
            expect(settings.roundTimeLimit).toBe(300);
        });

        it('should use default values for optional properties', () => {
            const settings = new PartySettings({
                playerCount: 5
            });

            expect(settings.allowSpectators).toBe(false);
            expect(settings.roundTimeLimit).toBe(0);
        });

        it('should be immutable', () => {
            const settings = new PartySettings({
                playerCount: 5
            });

            expect(Object.isFrozen(settings)).toBe(true);
        });

        it('should throw error for invalid player count (too low)', () => {
            expect(() => {
                new PartySettings({
                    playerCount: 2
                });
            }).toThrow('Player count must be between 3 and 8');
        });

        it('should throw error for invalid player count (too high)', () => {
            expect(() => {
                new PartySettings({
                    playerCount: 9
                });
            }).toThrow('Player count must be between 3 and 8');
        });

        it('should not keep a hand size (chosen per round, not per party)', () => {
            const settings = new PartySettings({
                playerCount: 5,
                handSize: 7
            });

            expect(settings.handSize).toBeUndefined();
            expect(settings.toObject()).not.toHaveProperty('handSize');
            expect(JSON.parse(settings.toJSON())).not.toHaveProperty('handSize');
        });

        it('should throw error for negative time limit', () => {
            expect(() => {
                new PartySettings({
                    playerCount: 5,
                    roundTimeLimit: -1
                });
            }).toThrow('Round time limit must be a non-negative number');
        });
    });

    describe('createDefault()', () => {
        it('should create default settings', () => {
            const settings = PartySettings.createDefault();

            expect(settings.playerCount).toBe(5);
            expect(settings.allowSpectators).toBe(false);
            expect(settings.roundTimeLimit).toBe(0);
        });
    });

    describe('toJSON() / fromJSON()', () => {
        it('should serialize to JSON and deserialize back', () => {
            const original = new PartySettings({
                playerCount: 6,
                allowSpectators: true,
                roundTimeLimit: 600
            });

            const json = original.toJSON();
            const restored = PartySettings.fromJSON(json);

            expect(restored.playerCount).toBe(original.playerCount);
            expect(restored.allowSpectators).toBe(original.allowSpectators);
            expect(restored.roundTimeLimit).toBe(original.roundTimeLimit);
        });

        it('should read settings stored with a legacy hand size', () => {
            const restored = PartySettings.fromJSON(
                JSON.stringify({ playerCount: 4, handSize: 7, allowSpectators: false, roundTimeLimit: 0 })
            );

            expect(restored.playerCount).toBe(4);
            expect(restored.handSize).toBeUndefined();
        });
    });

    describe('toObject()', () => {
        it('should convert to plain object', () => {
            const settings = new PartySettings({
                playerCount: 5,
                allowSpectators: false,
                roundTimeLimit: 0
            });

            expect(settings.toObject()).toEqual({
                playerCount: 5,
                allowSpectators: false,
                roundTimeLimit: 0
            });
        });
    });

    describe('equals()', () => {
        it('should return true for equal settings', () => {
            const settings1 = new PartySettings({
                playerCount: 5,
                allowSpectators: false,
                roundTimeLimit: 300
            });

            const settings2 = new PartySettings({
                playerCount: 5,
                allowSpectators: false,
                roundTimeLimit: 300
            });

            expect(settings1.equals(settings2)).toBe(true);
        });

        it('should return false for different player count', () => {
            const settings1 = new PartySettings({
                playerCount: 5
            });

            const settings2 = new PartySettings({
                playerCount: 6
            });

            expect(settings1.equals(settings2)).toBe(false);
        });

        it('should return false for different spectator setting', () => {
            const settings1 = new PartySettings({
                playerCount: 5,
                allowSpectators: false
            });

            const settings2 = new PartySettings({
                playerCount: 5,
                allowSpectators: true
            });

            expect(settings1.equals(settings2)).toBe(false);
        });

        it('should return false for different round time limit', () => {
            const settings1 = new PartySettings({
                playerCount: 5,
                roundTimeLimit: 0
            });

            const settings2 = new PartySettings({
                playerCount: 5,
                roundTimeLimit: 60
            });

            expect(settings1.equals(settings2)).toBe(false);
        });

        it('should return false for non-PartySettings object', () => {
            const settings = new PartySettings({
                playerCount: 5
            });

            expect(settings.equals({ playerCount: 5, allowSpectators: false, roundTimeLimit: 0 })).toBe(false);
        });
    });

    describe('with()', () => {
        it('should create new instance with changed properties', () => {
            const original = new PartySettings({
                playerCount: 5,
                allowSpectators: false,
                roundTimeLimit: 0
            });

            const modified = original.with({ playerCount: 6 });

            expect(modified.playerCount).toBe(6);
            expect(modified.allowSpectators).toBe(false);
            expect(modified.roundTimeLimit).toBe(0);

            // Original should be unchanged
            expect(original.playerCount).toBe(5);
        });

        it('should create new instance with multiple changes', () => {
            const original = PartySettings.createDefault();

            const modified = original.with({
                playerCount: 8,
                allowSpectators: true,
                roundTimeLimit: 120
            });

            expect(modified.playerCount).toBe(8);
            expect(modified.allowSpectators).toBe(true);
            expect(modified.roundTimeLimit).toBe(120);
        });

        it('should throw error for invalid changes', () => {
            const settings = PartySettings.createDefault();

            expect(() => {
                settings.with({ playerCount: 2 });
            }).toThrow('Player count must be between 3 and 8');
        });
    });
});
