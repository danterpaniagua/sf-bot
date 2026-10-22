// GITIN-2257: export Meet "call_ended" events (per participant network quality) from the Reports API
// to a Sheet, so it can be downloaded as CSV. Reads from the Reports API; writes only a new sheet.
// Setup: script.google.com as the Workspace admin; set the scopes in appsscript.json (see listMeetCalls_).
var DAYS_BACK = 7;
var SHEET_NAME = 'meet_call_ended';

// Calls the Reports API over REST with the script's own OAuth token (no advanced service needed).
// Needs these scopes in appsscript.json (Project Settings > "Show appsscript.json"):
//   "oauthScopes": ["https://www.googleapis.com/auth/admin.reports.audit.readonly",
//                   "https://www.googleapis.com/auth/script.external_request",
//                   "https://www.googleapis.com/auth/spreadsheets"]
function listMeetCalls_(start, pageToken) {
  var url = 'https://admin.googleapis.com/admin/reports/v1/activity/users/all/applications/meet' +
    '?eventName=call_ended&maxResults=1000&startTime=' + encodeURIComponent(start) +
    (pageToken ? '&pageToken=' + encodeURIComponent(pageToken) : '');
  var resp = UrlFetchApp.fetch(url, {
    headers: { Authorization: 'Bearer ' + ScriptApp.getOAuthToken() },
    muteHttpExceptions: true
  });
  if (resp.getResponseCode() !== 200) {
    throw new Error('Reports API ' + resp.getResponseCode() + ': ' + resp.getContentText().slice(0, 500));
  }
  return JSON.parse(resp.getContentText());
}

function exportMeetCalls() {
  var start = new Date(Date.now() - DAYS_BACK * 86400000).toISOString();
  var rows = [];
  var keys = {};
  var pageToken;

  do {
    var res = listMeetCalls_(start, pageToken);
    (res.items || []).forEach(function (item) {
      (item.events || []).forEach(function (ev) {
        var row = {
          time: item.id.time,
          actor: item.actor ? item.actor.email : '',
          ipAddress: item.ipAddress || ''
        };
        (ev.parameters || []).forEach(function (p) {
          var v = p.value;
          if (v === undefined) v = p.intValue;
          if (v === undefined) v = p.boolValue;
          if (v === undefined) v = (p.multiValue || []).join('|');
          row[p.name] = v;
          keys[p.name] = true;
        });
        rows.push(row);
      });
    });
    pageToken = res.nextPageToken;
  } while (pageToken);

  var header = ['time', 'actor', 'ipAddress'].concat(Object.keys(keys).sort());
  var values = [header].concat(rows.map(function (r) {
    return header.map(function (h) { return r[h] === undefined ? '' : r[h]; });
  }));

  var ss = SpreadsheetApp.getActiveSpreadsheet() || SpreadsheetApp.create('GITIN-2257 meet call_ended');
  var sheet = ss.getSheetByName(SHEET_NAME) || ss.insertSheet(SHEET_NAME);
  sheet.clear();
  sheet.getRange(1, 1, values.length, header.length).setValues(values);
  Logger.log('rows: ' + rows.length + ', columns: ' + header.length);
}
