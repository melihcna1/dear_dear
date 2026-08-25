/** Dear Dear Asset Importer — Google Sheets webhook backend. */

const SCHEMA_VERSION = 1;
const DEFAULT_SHEET_NAME = 'Asset Catalog';
const HEADERS = [
  'record_id', 'item_id', 'item_name', 'asset_name', 'sprite_name',
  'main_category', 'sub_category', 'gender', 'is_buyable', 'is_sellable',
  'id_in_filename', 'model_path', 'market_image_path', 'source_sha256',
  'created_at_utc', 'updated_at_utc', 'status',
];
const CATEGORY_RANGES = {
  seeds: [110000, 119999],
  crops: [120000, 129999],
  food: [130000, 139999],
  furniture: [210000, 299999],
  cloth: [310000, 399999],
  beauty: [410000, 419999],
  utility: [420000, 429999],
  chat_effects: [430000, 439999],
  recipe_craft: [610000, 699999],
  market_shop: [710000, 999999],
};


function doGet() {
  return jsonOutput({ok: true, data: {service: 'dear-dear-asset-importer', schema_version: SCHEMA_VERSION}});
}


function doPost(e) {
  try {
    const payload = JSON.parse((e && e.postData && e.postData.contents) || '{}');
    authenticate(payload.token);
    switch (String(payload.action || '')) {
      case 'health':
        return jsonOutput(handleHealth());
      case 'snapshot':
        return jsonOutput(handleSnapshot());
      case 'reserve':
        return jsonOutput(handleReserve(payload));
      case 'upsert':
        return jsonOutput(handleUpsert(payload));
      default:
        throw apiError('unknown_action', 'Unknown action. Use health, snapshot, reserve, or upsert.');
    }
  } catch (error) {
    const code = error && error.apiCode ? error.apiCode : 'internal_error';
    const message = error && error.message ? error.message : String(error);
    return jsonOutput({ok: false, error: {code: code, message: message}});
  }
}


function handleHealth() {
  const sheet = getCatalogSheet();
  return {
    ok: true,
    data: {
      service: 'dear-dear-asset-importer',
      schema_version: SCHEMA_VERSION,
      sheet_name: sheet.getName(),
    },
  };
}


function handleSnapshot() {
  const sheet = getCatalogSheet();
  const rows = readRows(sheet);
  const usedIds = rows
    .map(row => String(row.item_id || ''))
    .filter(itemId => /^\d{6}$/.test(itemId));
  const lastByCategory = {};
  Object.keys(CATEGORY_RANGES).forEach(categoryKey => {
    const range = CATEGORY_RANGES[categoryKey];
    const matching = usedIds.map(Number).filter(value => value >= range[0] && value <= range[1]);
    lastByCategory[categoryKey] = matching.length ? Math.max.apply(null, matching) : null;
  });
  return {ok: true, data: {used_ids: usedIds, last_by_category: lastByCategory}};
}


function handleReserve(payload) {
  const recordId = requireText(payload.record_id, 'record_id');
  const categoryKey = requireText(payload.category_key, 'category_key');
  const range = CATEGORY_RANGES[categoryKey];
  if (!range) {
    throw apiError('invalid_category', 'Unknown or inactive category: ' + categoryKey);
  }
  const requestedId = String(payload.requested_id || '').trim();
  const blockedIds = Array.isArray(payload.blocked_ids) ? payload.blocked_ids.map(String) : [];
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(20000)) {
    throw apiError('lock_timeout', 'Could not acquire the ID allocation lock. Retry the request.');
  }
  try {
    const sheet = getCatalogSheet();
    const rows = readRows(sheet);
    const existing = rows.find(row => String(row.record_id) === recordId);
    if (existing) {
      const existingId = String(existing.item_id || '');
      if (!idInRange(existingId, range)) {
        throw apiError('existing_record_invalid', 'The existing reservation has an invalid category ID.');
      }
      return {ok: true, data: {record_id: recordId, item_id: existingId, status: String(existing.status || 'reserved')}};
    }

    const used = new Set(blockedIds);
    rows.forEach(row => {
      const itemId = String(row.item_id || '');
      if (itemId) used.add(itemId);
    });
    let allocation;
    if (requestedId) {
      if (!idInRange(requestedId, range)) {
        throw apiError('invalid_id', 'Requested ID is not six digits in the active category range.');
      }
      if (used.has(requestedId)) {
        throw apiError('id_conflict', 'Requested ID is already used or blocked: ' + requestedId);
      }
      allocation = Number(requestedId);
    } else {
      let maximum = range[0] - 1;
      used.forEach(itemId => {
        if (/^\d{6}$/.test(itemId)) {
          const value = Number(itemId);
          if (value >= range[0] && value <= range[1]) maximum = Math.max(maximum, value);
        }
      });
      allocation = maximum + 1;
      if (allocation > range[1]) {
        throw apiError('range_exhausted', 'No IDs remain in the active category range.');
      }
    }

    const timestamp = new Date().toISOString();
    const row = emptyCanonicalRow();
    row.record_id = recordId;
    row.item_id = String(allocation).padStart(6, '0');
    row.main_category = categoryKey;
    row.created_at_utc = timestamp;
    row.updated_at_utc = timestamp;
    row.status = 'reserved';
    appendCanonicalRow(sheet, row);
    SpreadsheetApp.flush();
    return {ok: true, data: {record_id: recordId, item_id: row.item_id, status: 'reserved'}};
  } finally {
    lock.releaseLock();
  }
}


function handleUpsert(payload) {
  if (!Array.isArray(payload.rows) || payload.rows.length === 0) {
    throw apiError('invalid_rows', 'upsert requires a non-empty rows array.');
  }
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(20000)) {
    throw apiError('lock_timeout', 'Could not acquire the catalog update lock. Retry the request.');
  }
  try {
    const sheet = getCatalogSheet();
    let rows = readRows(sheet);
    const result = [];
    payload.rows.forEach(input => {
      const canonical = canonicalizeInput(input);
      const range = CATEGORY_RANGES[canonical.main_category];
      if (!range || !idInRange(canonical.item_id, range)) {
        throw apiError('invalid_id', 'ID ' + canonical.item_id + ' is outside its active category range.');
      }
      const sameRecord = rows.find(row => String(row.record_id) === canonical.record_id);
      const idConflict = rows.find(row => String(row.item_id) === canonical.item_id && String(row.record_id) !== canonical.record_id);
      if (idConflict) {
        throw apiError('id_conflict', 'ID already belongs to another record: ' + canonical.item_id);
      }
      const nameConflict = rows.find(row => String(row.asset_name) === canonical.asset_name && String(row.record_id) !== canonical.record_id);
      if (nameConflict) {
        throw apiError('asset_name_conflict', 'Asset name already belongs to another record: ' + canonical.asset_name);
      }
      if (sameRecord && String(sameRecord.item_id) !== canonical.item_id) {
        throw apiError('immutable_id', 'A reserved record cannot be reassigned to another ID.');
      }
      canonical.created_at_utc = sameRecord && sameRecord.created_at_utc
        ? String(sameRecord.created_at_utc)
        : (canonical.created_at_utc || new Date().toISOString());
      canonical.updated_at_utc = new Date().toISOString();
      canonical.status = 'ready';
      if (sameRecord) {
        writeCanonicalRow(sheet, sameRecord._sheet_row, canonical);
        rows = rows.map(row => String(row.record_id) === canonical.record_id
          ? Object.assign({_sheet_row: sameRecord._sheet_row}, canonical)
          : row);
      } else {
        const rowNumber = appendCanonicalRow(sheet, canonical);
        rows.push(Object.assign({_sheet_row: rowNumber}, canonical));
      }
      result.push({record_id: canonical.record_id, item_id: canonical.item_id, status: 'ready'});
    });
    SpreadsheetApp.flush();
    return {ok: true, data: {rows: result}};
  } finally {
    lock.releaseLock();
  }
}


function getCatalogSheet() {
  const properties = PropertiesService.getScriptProperties();
  const spreadsheetId = String(properties.getProperty('SPREADSHEET_ID') || '').trim();
  const sheetName = String(properties.getProperty('SHEET_NAME') || DEFAULT_SHEET_NAME).trim();
  const spreadsheet = spreadsheetId
    ? SpreadsheetApp.openById(spreadsheetId)
    : SpreadsheetApp.getActiveSpreadsheet();
  if (!spreadsheet) {
    throw apiError('spreadsheet_not_configured', 'Set SPREADSHEET_ID in Apps Script properties or bind the script to a Sheet.');
  }
  let sheet = spreadsheet.getSheetByName(sheetName);
  if (!sheet) sheet = spreadsheet.insertSheet(sheetName);
  ensureHeaders(sheet);
  return sheet;
}


function ensureHeaders(sheet) {
  const current = sheet.getRange(1, 1, 1, HEADERS.length).getDisplayValues()[0];
  const empty = current.every(value => value === '');
  if (empty) {
    sheet.getRange(1, 1, 1, HEADERS.length).setValues([HEADERS]);
    sheet.setFrozenRows(1);
    return;
  }
  const mismatch = HEADERS.some((header, index) => current[index] !== header);
  if (mismatch) {
    throw apiError('schema_mismatch', 'Sheet headers do not match schema version ' + SCHEMA_VERSION + '.');
  }
}


function readRows(sheet) {
  const lastRow = sheet.getLastRow();
  if (lastRow < 2) return [];
  return sheet.getRange(2, 1, lastRow - 1, HEADERS.length).getValues().map((values, index) => {
    const row = {_sheet_row: index + 2};
    HEADERS.forEach((header, column) => row[header] = values[column]);
    return row;
  }).filter(row => String(row.record_id || '').trim() !== '');
}


function canonicalizeInput(input) {
  if (!input || typeof input !== 'object') throw apiError('invalid_row', 'Each row must be an object.');
  const row = emptyCanonicalRow();
  HEADERS.forEach(header => {
    if (header !== 'status' && Object.prototype.hasOwnProperty.call(input, header)) row[header] = input[header];
  });
  row.record_id = requireText(row.record_id, 'record_id');
  row.item_id = requireText(row.item_id, 'item_id');
  row.item_name = requireText(row.item_name, 'item_name');
  row.asset_name = requireText(row.asset_name, 'asset_name');
  row.sprite_name = requireText(row.sprite_name, 'sprite_name');
  row.main_category = requireText(row.main_category, 'main_category');
  row.sub_category = requireText(row.sub_category, 'sub_category');
  row.model_path = requireText(row.model_path, 'model_path');
  row.market_image_path = requireText(row.market_image_path, 'market_image_path');
  row.is_buyable = Boolean(row.is_buyable);
  row.is_sellable = Boolean(row.is_sellable);
  row.id_in_filename = Boolean(row.id_in_filename);
  return row;
}


function emptyCanonicalRow() {
  const row = {};
  HEADERS.forEach(header => row[header] = '');
  return row;
}


function appendCanonicalRow(sheet, row) {
  const rowNumber = Math.max(sheet.getLastRow() + 1, 2);
  writeCanonicalRow(sheet, rowNumber, row);
  return rowNumber;
}


function writeCanonicalRow(sheet, rowNumber, row) {
  const values = HEADERS.map(header => safeCell(row[header]));
  sheet.getRange(rowNumber, 1, 1, HEADERS.length).setValues([values]);
}


function safeCell(value) {
  if (typeof value !== 'string') return value;
  return /^[=+@]/.test(value) ? "'" + value : value;
}


function idInRange(itemId, range) {
  const text = String(itemId || '');
  if (!/^\d{6}$/.test(text)) return false;
  const value = Number(text);
  return value >= range[0] && value <= range[1];
}


function requireText(value, fieldName) {
  const text = String(value || '').trim();
  if (!text) throw apiError('missing_field', 'Missing required field: ' + fieldName);
  return text;
}


function authenticate(token) {
  const expected = String(PropertiesService.getScriptProperties().getProperty('SHARED_SECRET') || '');
  if (!expected) throw apiError('secret_not_configured', 'Set SHARED_SECRET in Apps Script properties.');
  if (String(token || '') !== expected) throw apiError('unauthorized', 'Invalid shared token.');
}


function apiError(code, message) {
  const error = new Error(message);
  error.apiCode = code;
  return error;
}


function jsonOutput(value) {
  return ContentService.createTextOutput(JSON.stringify(value)).setMimeType(ContentService.MimeType.JSON);
}


/** Run manually in Apps Script to sanity-check the immutable range contract. */
function runDearDearAssetImporterSelfTests() {
  Object.keys(CATEGORY_RANGES).forEach(key => {
    const range = CATEGORY_RANGES[key];
    if (!idInRange(String(range[0]), range) || !idInRange(String(range[1]), range)) {
      throw new Error('Range boundary failed for ' + key);
    }
    if (idInRange(String(range[0] - 1), range) || idInRange(String(range[1] + 1), range)) {
      throw new Error('Out-of-range validation failed for ' + key);
    }
  });
  console.log('Dear Dear Asset Importer backend self-tests: PASS');
}
