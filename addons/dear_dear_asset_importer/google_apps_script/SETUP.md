# Google Sheets webhook setup

The Asset Importer reserves IDs and upserts catalog rows through a small Google Apps Script web app. The shared secret and spreadsheet ID stay in Apps Script properties; they are not committed to the Godot project.

1. Create or choose the team spreadsheet. Do not add headers manually; the script creates the canonical **Asset Catalog** tab on its first request.
2. Open **Extensions → Apps Script** from the spreadsheet, replace the editor contents with `Code.gs`, and save.
3. In **Project Settings → Script properties**, add:
   - `SHARED_SECRET`: a long random value shared only with tool users.
   - `SPREADSHEET_ID`: the value between `/d/` and `/edit` in the spreadsheet URL. This is optional for a script bound to the target spreadsheet, but setting it is recommended.
   - `SHEET_NAME`: optional; defaults to `Asset Catalog`.
4. Run `runDearDearAssetImporterSelfTests` once and approve the requested spreadsheet permission.
5. Choose **Deploy → New deployment → Web app**. Execute as the script owner and allow access to anyone with the link. The shared secret still authenticates every POST body.
6. Copy the `/exec` URL. In Godot, open **Asset Importer → Sheets Settings** and enter that URL and `SHARED_SECRET`.
7. Click **Refresh IDs**. The toolbar should report `Sheets: connected`.

For machines where editor settings should not contain the values, set `DEAR_DEAR_ASSET_WEBHOOK_URL` and `DEAR_DEAR_ASSET_SHARED_TOKEN` environment variables instead. Environment variables override the editor settings.

## Contract

All requests are JSON POSTs containing `action`, `token`, and `request_id`. Supported actions are:

- `health`: validates configuration and schema.
- `snapshot`: returns every permanently claimed six-digit ID.
- `reserve`: atomically claims a manual ID or the next monotonic ID under an Apps Script lock. Repeating the same `record_id` returns its existing claim.
- `upsert`: validates and writes complete catalog records, matching immutable identities by `record_id`.

Responses always use `{ "ok": true, "data": ... }` or `{ "ok": false, "error": { "code": ..., "message": ... } }`.

IDs are never recycled. A reservation left incomplete remains visible with `status=reserved`; a later retry with the same draft finishes that row.
