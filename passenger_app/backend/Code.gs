const SHEETS = {
  users: ['id', 'firstName', 'lastName', 'email', 'phone', 'passwordHash', 'salt', 'balance', 'createdAt', 'idNumber'],
  sessions: ['token', 'userId', 'expiresAt'],
  bookings: ['id', 'userId', 'pickup', 'destination', 'passengerCount', 'fare', 'status', 'createdAt', 'boardedAt', 'completedAt'],
  transactions: ['id', 'userId', 'title', 'amount', 'createdAt', 'bookingId'],
  buses: ['id', 'label', 'latitude', 'longitude', 'status', 'updatedAt'],
  topUpRequests: ['id', 'userId', 'amount', 'gcashNumber', 'screenshotFileId', 'screenshotUrl', 'status', 'submittedAt', 'reviewedAt', 'adminNote', 'creditedAt'],
  settings: ['key', 'value']
};

function setup() {
  Object.keys(SHEETS).forEach(function (name) { sheet_(name); });
  if (!findBy_('settings', 'key', 'GCASH_NUMBER')) append_('settings', { key: 'GCASH_NUMBER', value: '' });
  if (!findBy_('settings', 'key', 'ADMIN_EMAIL')) append_('settings', { key: 'ADMIN_EMAIL', value: '' });
}

function authorizeServices() {
  DriveApp.getRootFolder().getName();
  MailApp.getRemainingDailyQuota();
}

function doGet(e) {
  try {
    const action = String((e.parameter || {}).action || 'health');
    if (action === 'health') return reply_({ success: true, message: 'Ikot API is working' });
    if (action === 'profile') return reply_({ success: true, passenger: passenger_(authenticate_(e.parameter.token)) });
    if (action === 'transactions') return reply_({ success: true, transactions: transactions_(authenticate_(e.parameter.token).id) });
    if (action === 'notifications') return reply_({ success: true, notifications: notifications_(authenticate_(e.parameter.token).id) });
    if (action === 'buses') { authenticate_(e.parameter.token); return reply_({ success: true, buses: buses_() }); }
    if (action === 'paymentConfig') { authenticate_(e.parameter.token); return reply_({ success: true, gcashNumber: setting_('GCASH_NUMBER') }); }
    if (action === 'topUpRequests') return reply_({ success: true, requests: topUpRequests_(authenticate_(e.parameter.token).id) });
    throw new Error('Unknown action.');
  } catch (error) {
    return reply_({ success: false, message: error.message });
  }
}

function doPost(e) {
  try {
    const body = JSON.parse((e.postData && e.postData.contents) || '{}');
    const action = String(body.action || '');
    const handlers = { register: register_, login: login_, createTopUpRequest: createTopUpRequest_, createBooking: createBooking_, boardRide: boardRide_, completeRide: completeRide_ };
    if (!handlers[action]) throw new Error('Unknown action.');
    return reply_(handlers[action](body));
  } catch (error) {
    return reply_({ success: false, message: error.message });
  }
}

function register_(body) {
  return locked_(function () {
    const idNumber = required_(body.idNumber, 'ID number');
    const password = required_(body.password, 'Password');
    if (password.length < 8) throw new Error('Password must contain at least 8 characters.');
    if (findBy_('users', 'idNumber', idNumber)) throw new Error('That ID number is already registered.');
    const salt = Utilities.getUuid();
    const user = {
      id: Utilities.getUuid(), firstName: required_(body.firstName, 'First name'),
      lastName: required_(body.lastName, 'Last name'), idNumber: idNumber,
      phone: required_(body.phone, 'Phone'), passwordHash: hash_(password, salt),
      salt: salt, balance: 0, createdAt: new Date().toISOString()
    };
    append_('users', user);
    const token = createSession_(user.id);
    return { success: true, token: token, passenger: passenger_(user) };
  });
}

function login_(body) {
  const idNumber = required_(body.idNumber, 'ID number');
  const user = findBy_('users', 'idNumber', idNumber);
  if (!user || user.passwordHash !== hash_(String(body.password || ''), user.salt)) throw new Error('Incorrect ID number or password.');
  return { success: true, token: createSession_(user.id), passenger: passenger_(user) };
}

function createTopUpRequest_(body) {
  const user = authenticate_(body.token);
  const amount = Number(body.amount);
  if (!isFinite(amount) || amount <= 0 || amount > 10000) throw new Error('Invalid top-up amount.');
  const gcashNumber = setting_('GCASH_NUMBER');
  if (!gcashNumber) throw new Error('The admin has not configured the GCash number.');
  const encoded = required_(body.screenshotBase64, 'Payment screenshot');
  if (encoded.length > 4500000) throw new Error('Payment screenshot is too large.');
  const id = Utilities.getUuid();
  const safeName = String(body.fileName || 'payment.jpg').replace(/[^a-zA-Z0-9._-]/g, '_');
  const blob = Utilities.newBlob(Utilities.base64Decode(encoded), String(body.mimeType || 'image/jpeg'), id + '_' + safeName);
  const folder = uploadFolder_();
  const file = folder.createFile(blob);
  file.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW);
  const screenshotUrl = 'https://drive.google.com/thumbnail?id=' + file.getId() + '&sz=w400';
  append_('topUpRequests', { id: id, userId: user.id, amount: amount, gcashNumber: gcashNumber, screenshotFileId: file.getId(), screenshotUrl: screenshotUrl, status: 'pending', submittedAt: new Date().toISOString(), reviewedAt: '', adminNote: '', creditedAt: '' });
  const adminEmail = setting_('ADMIN_EMAIL');
  if (adminEmail) {
    try { MailApp.sendEmail(adminEmail, 'New Ikot top-up request', 'Passenger ' + user.idNumber + ' submitted PHP ' + amount.toFixed(2) + '. Review request ' + id + ' in the spreadsheet.'); } catch (_) {}
  }
  return { success: true, requestId: id };
}

function createBooking_(body) {
  const user = authenticate_(body.token);
  const count = Number(body.passengerCount);
  if (!Number.isInteger(count) || count < 1 || count > 6) throw new Error('Passenger count must be from 1 to 6.');
  const booking = { id: Utilities.getUuid(), userId: user.id, pickup: required_(body.pickup, 'Pickup'), destination: required_(body.destination, 'Destination'), passengerCount: count, fare: 15 * count, status: 'waiting', createdAt: new Date().toISOString(), boardedAt: '', completedAt: '' };
  append_('bookings', booking);
  return { success: true, booking: booking };
}

function boardRide_(body) {
  return locked_(function () {
    const user = authenticate_(body.token);
    const booking = findBy_('bookings', 'id', required_(body.bookingId, 'Booking ID'));
    if (!booking || booking.userId !== user.id) throw new Error('Booking not found.');
    if (booking.status !== 'waiting') throw new Error('This booking was already boarded.');
    const fare = Number(booking.fare);
    if (Number(user.balance) < fare) throw new Error('Insufficient credits. Please top up first.');
    user.balance = Number(user.balance) - fare;
    update_('users', user._row, 'balance', user.balance);
    update_('bookings', booking._row, 'status', 'boarded');
    update_('bookings', booking._row, 'boardedAt', new Date().toISOString());
    append_('transactions', { id: Utilities.getUuid(), userId: user.id, title: 'Ride to ' + booking.destination, amount: -fare, createdAt: new Date().toISOString(), bookingId: booking.id });
    return { success: true, passenger: passenger_(user) };
  });
}

function completeRide_(body) {
  const user = authenticate_(body.token);
  const booking = findBy_('bookings', 'id', required_(body.bookingId, 'Booking ID'));
  if (!booking || booking.userId !== user.id) throw new Error('Booking not found.');
  if (booking.status !== 'boarded') throw new Error('The ride must be boarded first.');
  update_('bookings', booking._row, 'status', 'completed');
  update_('bookings', booking._row, 'completedAt', new Date().toISOString());
  return { success: true };
}

function authenticate_(token) {
  const session = findBy_('sessions', 'token', required_(token, 'Session token'));
  if (!session || new Date(session.expiresAt).getTime() < Date.now()) throw new Error('Your session expired. Please sign in again.');
  const user = findBy_('users', 'id', session.userId);
  if (!user) throw new Error('Passenger account not found.');
  return user;
}

function createSession_(userId) {
  const token = Utilities.getUuid() + Utilities.getUuid();
  append_('sessions', { token: token, userId: userId, expiresAt: new Date(Date.now() + 7 * 86400000).toISOString() });
  return token;
}

function passenger_(user) {
  return { id: user.id, firstName: user.firstName, lastName: user.lastName, idNumber: user.idNumber, phone: user.phone, balance: Number(user.balance) };
}

function transactions_(userId) {
  return all_('transactions').filter(function (row) { return row.userId === userId; }).reverse().map(function (row) {
    const amount = Number(row.amount);
    return { title: row.title, date: new Date(row.createdAt).toLocaleString(), amount: (amount >= 0 ? '+ PHP ' : '- PHP ') + Math.abs(amount).toFixed(2) };
  });
}

function notifications_(userId) {
  const items = [];
  all_('transactions').filter(function (row) { return row.userId === userId; }).forEach(function (row) {
    const amount = Number(row.amount);
    items.push({
      type: amount >= 0 ? 'topUp' : 'boarded',
      title: amount >= 0 ? 'Credits added' : 'Ride payment recorded',
      message: row.title + ': ' + (amount >= 0 ? '+ PHP ' : '- PHP ') + Math.abs(amount).toFixed(2),
      createdAt: String(row.createdAt)
    });
  });
  all_('bookings').filter(function (row) { return row.userId === userId; }).forEach(function (row) {
    const status = String(row.status);
    items.push({
      type: status === 'completed' ? 'completed' : 'booking',
      title: status === 'completed' ? 'You have arrived' : status === 'boarded' ? 'You are onboard' : 'Booking created',
      message: row.pickup + ' to ' + row.destination + ' for ' + row.passengerCount + ' passenger' + (Number(row.passengerCount) > 1 ? 's' : ''),
      createdAt: String(status === 'completed' ? row.completedAt : status === 'boarded' ? row.boardedAt : row.createdAt)
    });
  });
  return items.sort(function (a, b) { return new Date(b.createdAt) - new Date(a.createdAt); }).map(function (item) {
    return { type: item.type, title: item.title, message: item.message, date: new Date(item.createdAt).toLocaleString() };
  });
}

function buses_() {
  return all_('buses').filter(function (row) {
    return String(row.status || 'active').toLowerCase() === 'active' && isFinite(Number(row.latitude)) && isFinite(Number(row.longitude));
  }).map(function (row) {
    return { id: String(row.id), label: String(row.label || 'Bus'), latitude: Number(row.latitude), longitude: Number(row.longitude), status: 'active', updatedAt: String(row.updatedAt || '') };
  });
}

function topUpRequests_(userId) {
  return all_('topUpRequests').filter(function (row) { return row.userId === userId; }).reverse().map(function (row) {
    return { id: String(row.id), amount: Number(row.amount), status: String(row.status), submittedAt: new Date(row.submittedAt).toLocaleString(), screenshotUrl: String(row.screenshotUrl), adminNote: String(row.adminNote || '') };
  });
}

function setting_(key) {
  const row = findBy_('settings', 'key', key);
  return row ? String(row.value || '').trim() : '';
}

function uploadFolder_() {
  const properties = PropertiesService.getScriptProperties();
  const existingId = properties.getProperty('TOP_UP_FOLDER_ID');
  if (existingId) {
    try { return DriveApp.getFolderById(existingId); } catch (_) {}
  }
  const folder = DriveApp.createFolder('Ikot Top-up Screenshots');
  properties.setProperty('TOP_UP_FOLDER_ID', folder.getId());
  return folder;
}

function onEdit(e) {
  if (!e || !e.range) return;
  const sheet = e.range.getSheet();
  if (sheet.getName() !== 'topUpRequests' || e.range.getRow() < 2) return;
  const headers = SHEETS.topUpRequests;
  const statusColumn = headers.indexOf('status') + 1;
  if (e.range.getColumn() !== statusColumn) return;
  const status = String(e.value || '').toLowerCase().trim();
  if (status !== 'approved' && status !== 'rejected') return;
  locked_(function () {
    const rowNumber = e.range.getRow();
    const values = sheet.getRange(rowNumber, 1, 1, headers.length).getValues()[0];
    const request = { _row: rowNumber };
    headers.forEach(function (header, index) { request[header] = values[index]; });
    if (request.creditedAt) return;
    update_('topUpRequests', rowNumber, 'reviewedAt', new Date().toISOString());
    if (status === 'rejected') return;
    const user = findBy_('users', 'id', request.userId);
    if (!user) throw new Error('Passenger account not found for this request.');
    const amount = Number(request.amount);
    user.balance = Number(user.balance) + amount;
    update_('users', user._row, 'balance', user.balance);
    append_('transactions', { id: Utilities.getUuid(), userId: user.id, title: 'Approved GCash top up', amount: amount, createdAt: new Date().toISOString(), bookingId: request.id });
    update_('topUpRequests', rowNumber, 'creditedAt', new Date().toISOString());
  });
}

function sheet_(name) {
  const book = SpreadsheetApp.getActiveSpreadsheet();
  let sheet = book.getSheetByName(name);
  if (!sheet) sheet = book.insertSheet(name);
  const headers = SHEETS[name];
  if (sheet.getLastRow() === 0) sheet.appendRow(headers);
  else if (sheet.getLastColumn() < headers.length) sheet.getRange(1, 1, 1, headers.length).setValues([headers]);
  return sheet;
}

function all_(name) {
  const sheet = sheet_(name), headers = SHEETS[name];
  if (sheet.getLastRow() < 2) return [];
  return sheet.getRange(2, 1, sheet.getLastRow() - 1, headers.length).getValues().map(function (values, index) {
    const item = { _row: index + 2 };
    headers.forEach(function (header, column) { item[header] = values[column]; });
    return item;
  });
}

function findBy_(name, field, value) { return all_(name).find(function (row) { return String(row[field]) === String(value); }); }
function append_(name, item) { sheet_(name).appendRow(SHEETS[name].map(function (header) { return item[header] === undefined ? '' : item[header]; })); }
function update_(name, row, field, value) { sheet_(name).getRange(row, SHEETS[name].indexOf(field) + 1).setValue(value); }
function required_(value, name) { const result = String(value || '').trim(); if (!result) throw new Error(name + ' is required.'); return result; }
function hash_(password, salt) { return Utilities.computeDigest(Utilities.DigestAlgorithm.SHA_256, salt + password).map(function (byte) { return ('0' + ((byte + 256) % 256).toString(16)).slice(-2); }).join(''); }
function locked_(callback) { const lock = LockService.getScriptLock(); lock.waitLock(10000); try { return callback(); } finally { lock.releaseLock(); } }
function reply_(body) { return ContentService.createTextOutput(JSON.stringify(body)).setMimeType(ContentService.MimeType.JSON); }
