const admin = require('firebase-admin');
admin.initializeApp();
const db = admin.firestore();

async function seed() {
  await db.collection('config').doc('tiers').set({
    anonymous: { dailyLimit: 5 },
    free: { dailyLimit: 20 },
    premium: { monthlyLimit: 1000 },
  });
  console.log('Seeded config/tiers');
}
seed().then(() => process.exit(0));
