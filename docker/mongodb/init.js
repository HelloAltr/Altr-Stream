// MongoDB Test Environment Initialization Script
// Initializes test database, authentication user, and basic collection for lifecycle verification.

db = db.getSiblingDB('admin');

db.createUser({
  user: 'altr_test_user',
  pwd: 'altr_test_pass',
  roles: [
    { role: 'readWrite', db: 'altr_test_db' },
    { role: 'dbAdmin', db: 'altr_test_db' }
  ]
});

db = db.getSiblingDB('altr_test_db');

db.createCollection('init_test');
db.init_test.insertOne({
  message: 'MongoDB test instance initialized for Altr Stream',
  initialized_at: new Date()
});
