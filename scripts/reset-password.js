const bcrypt = require('bcryptjs');
const Database = require('better-sqlite3');

async function resetPassword() {
    const hash = await bcrypt.hash('vemore', 10);
    const db = new Database('./data/zapzap.db');
    db.prepare("UPDATE users SET password_hash = ? WHERE username = 'vemore'").run(hash);
    db.close();
    console.log('Password reset successfully for user vemore');
    console.log('New hash:', hash);
}

resetPassword();
