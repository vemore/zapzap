/**
 * Unit tests for PartySettings Value Object
 */

const PartySettings = require('../../../../src/domain/value-objects/PartySettings');

describe('PartySettings Value Object', () => {
    describe('Constructor', () => {
        it('should create settings with valid properties', () => {
            const settings = new PartySettings({
                playerCount: 5,
                handSize: 7,
                allowSpectators: true,
                roundTimeLimit: 300
            });

            expect(settings.playerCount).toBe(5);
            expect(settings.handSize).toBe(7);
            expect(settings.allowSpectators).toBe(true);
            expect(settings.roundTimeLimit).toBe(300);
        });

        it('should use default values for optional properties', () => {
            const settings = new PartySettings({
                playerCount: 5,
                handSize: 7
            });

            expect(settings.allowSpectators).toBe(false);
            expect(settings.roundTimeLimit).toBe(0);
        });

        it('should be immutable', () => {
            const settings = new PartySettings({
                playerCount: 5,
                handSize: 7
            });

            expect(Object.isFrozen(settings)).toBe(true);
        });

        it('should throw error for invalid player count (too low)', () => {
            expect(() => {
                new PartySettings({
                    playerCount: 2,
                    handSize: 7
                });
            }).toThrow('Player count must be between 3 and 8');
        });

        it('should throw error for invalid player count (too high)', () => {
            expect(() => {
                new PartySettings({
                    playerCount: 9,
                    handSize: 7
                });
            }).toThrow('Player count must be between 3 and 8');
        });

        it('should throw error for invalid hand size (too low)', () => {
            expect(() => {
                new PartySettings({
                    playerCount: 5,
                    handSize: 4
                });
            }).toThrow('Hand size must be between 5 and 7');
        });

        it('should throw error for invalid hand size (too high)', () => {
            expect(() => {
                new PartySettings({
                    playerCount: 5,
                    handSize: 8
                });
            }).toThrow('Hand size must be between 5 and 7');
        });

        it('should throw error for negative time limit', () => {
            expect(() => {
                new PartySettings({
                    playerCount: 5,
                    handSize: 7,
                    roundTimeLimit: -1
                });
            }).toThrow('Round time limit must be a non-negative number');
        });
    });

    describe('createDefault()', () => {
        it('should create default settings', () => {
            const settings = PartySettings.createDefault();

            expect(settings.playerCount).toBe(5);
            expect(settings.handSize).toBe(7);
            expect(settings.allowSpectators).toBe(false);
            expect(settings.roundTimeLimit).toBe(0);
        });
    });

    describe('toJSON() / fromJSON()', () => {
        it('should serialize to JSON and deserialize back', () => {
            const original = new PartySettings({
                playerCount: 6,
                handSize: 5,
                allowSpectators: true,
                roundTimeLimit: 600
            });

            const json = original.toJSON();
            const restored = PartySettings.fromJSON(json);

            expect(restored.playerCount).toBe(original.playerCount);
            expect(restored.handSize).toBe(original.handSize);
            expect(restored.allowSpectators).toBe(original.allowSpectators);
            expect(restored.roundTimeLimit).toBe(original.roundTimeLimit);
        });
    });

    describe('toObject()', () => {
        it('should convert to plain object', () => {
            const settings = new PartySettings({
                playerCount: 5,
                handSize: 7,
                allowSpectators: false,
                roundTimeLimit: 0
            });

            const obj = settings.toObject();

            expect(obj.playerCount).toBe(5);
            expect(obj.handSize).toBe(7);
            expect(obj.allowSpectators).toBe(false);
            expect(obj.roundTimeLimit).toBe(0);
        });
    });

    describe('equals()', () => {
        it('should return true for equal settings', () => {
            const settings1 = new PartySettings({
                playerCount: 5,
                handSize: 7,
                allowSpectators: false,
                roundTimeLimit: 300
            });

            const settings2 = new PartySettings({
                playerCount: 5,
                handSize: 7,
                allowSpectators: false,
                roundTimeLimit: 300
            });

            expect(settings1.equals(settings2)).toBe(true);
        });

        it('should return false for different player count', () => {
            const settings1 = new PartySettings({
                playerCount: 5,
                handSize: 7
            });

            const settings2 = new PartySettings({
                playerCount: 6,
                handSize: 7
            });

            expect(settings1.equals(settings2)).toBe(false);
        });

        it('should return false for different hand size', () => {
            const settings1 = new PartySettings({
                playerCount: 5,
                handSize: 7
            });

            const settings2 = new PartySettings({
                playerCount: 5,
                handSize: 6
            });

            expect(settings1.equals(settings2)).toBe(false);
        });

        it('should return false for non-PartySettings object', () => {
            const settings = new PartySettings({
                playerCount: 5,
                handSize: 7
            });

            expect(settings.equals({ playerCount: 5, handSize: 7 })).toBe(false);
        });
    });

    describe('with()', () => {
        it('should create new instance with changed properties', () => {
            const original = new PartySettings({
                playerCount: 5,
                handSize: 7,
                allowSpectators: false,
                roundTimeLimit: 0
            });

            const modified = original.with({ playerCount: 6 });

            expect(modified.playerCount).toBe(6);
            expect(modified.handSize).toBe(7);
            expect(modified.allowSpectators).toBe(false);
            expect(modified.roundTimeLimit).toBe(0);

            // Original should be unchanged
            expect(original.playerCount).toBe(5);
        });

        it('should create new instance with multiple changes', () => {
            const original = PartySettings.createDefault();

            const modified = original.with({
                playerCount: 8,
                handSize: 5,
                allowSpectators: true
            });

            expect(modified.playerCount).toBe(8);
            expect(modified.handSize).toBe(5);
            expect(modified.allowSpectators).toBe(true);
            expect(modified.roundTimeLimit).toBe(0);
        });

        it('should throw error for invalid changes', () => {
            const settings = PartySettings.createDefault();

            expect(() => {
                settings.with({ playerCount: 2 });
            }).toThrow('Player count must be between 3 and 8');
        });
    });
});
