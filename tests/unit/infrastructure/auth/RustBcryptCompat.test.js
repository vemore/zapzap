/**
 * A password hash the Rust backend writes verifies on the Node backend.
 *
 * While Node is the rollback of the Rust backend, a user who registered or logged in on
 * Rust must still log in on Node. `rustHash` in the fixture was written by the Rust
 * `PasswordService::hash`; the Rust unit tests in
 * zapzap-rust/src/infrastructure/auth/password.rs verify the same fixture.
 */

const fixture = require('../../../../zapzap-rust/tests/fixtures/bcrypt_node_compat.json');
const User = require('../../../../src/domain/entities/User');

describe('Rust bcrypt hashes on the Node backend', () => {
    const userWith = (passwordHash) =>
        new User({ id: 'u1', username: 'rustuser', passwordHash });

    it('verifies the password against a hash Rust wrote', async () => {
        expect(fixture.rustHash).toMatch(/^\$2b\$10\$/);
        await expect(userWith(fixture.rustHash).verifyPassword(fixture.password)).resolves.toBe(true);
    });

    it('rejects a wrong password against a hash Rust wrote', async () => {
        await expect(userWith(fixture.rustHash).verifyPassword('wrong')).resolves.toBe(false);
    });

    it('verifies the Node fixture hash the Rust tests check', async () => {
        await expect(userWith(fixture.nodeHash).verifyPassword(fixture.password)).resolves.toBe(true);
    });
});
