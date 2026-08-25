# Asset Importer User Manual

This manual explains how to import self-contained GLB models, create standardized market images, update the managed asset catalog, and synchronize records with Google Sheets.

The Asset Importer is a Godot editor tool. It does not change the project's playable main scene.

## 1. What the importer creates

For each completed asset, the importer can create:

- A standardized copy of the source `.glb` in the configured project folder.
- A transparent 1024×1024 market image named after the generated sprite name.
- A record in `data/asset_catalog.json`.
- A matching row in `data/asset_exports/asset_catalog.csv`.
- A synchronized row in the team's Google Sheet.

The original GLB remains unchanged in its original location.

## 2. Requirements

Before starting, make sure that:

- The project is open in Godot 4.6.
- The **Asset Importer** tab is visible in the main editor toolbar.
- Each source file is a self-contained binary `.glb` file.
- The source GLB does not depend on external textures, buffers, or other files.
- Google Sheets has been configured if you intend to make final project writes.

Previewing and **Temporary Capture Test** work without Google Sheets. Final GLB and PNG writes require a successful server-side ID reservation.

## 3. First-time Google Sheets setup

This section is normally completed once by the project owner or technical lead.

1. Create or select the team Google Sheet.
2. In the Sheet, open **Extensions → Apps Script**.
3. Replace the Apps Script editor contents with the contents of `addons/dear_dear_asset_importer/google_apps_script/Code.gs` and save.
4. Open **Project Settings → Script properties** in Apps Script and add:
   - `SHARED_SECRET`: a long random secret known only to tool users.
   - `SPREADSHEET_ID`: the value between `/d/` and `/edit` in the Sheet URL.
   - `SHEET_NAME`: optional; the default is `Asset Catalog`.
5. Run `runDearDearAssetImporterSelfTests` once and approve the requested permission.
6. Choose **Deploy → New deployment → Web app**.
7. Set the web app to execute as the script owner and allow access to anyone with the link.
8. Copy the deployment URL ending in `/exec`.
9. In Godot, open **Asset Importer → Sheets Settings**.
10. Enter the `/exec` URL and the same shared secret, then click **Save**.
11. Click **Refresh IDs**. The toolbar should show **Sheets: connected**.

The URL and secret are stored in the current user's Godot editor settings, not in project files. They can instead be supplied with these environment variables:

- `DEAR_DEAR_ASSET_WEBHOOK_URL`
- `DEAR_DEAR_ASSET_SHARED_TOKEN`

Environment variables take precedence over values entered in **Sheets Settings**.

## 4. Interface overview

Open the **Asset Importer** tab beside Godot's 2D, 3D, Script, Game, and AssetLib tabs.

The workspace contains these main areas:

- **3D Viewport & Capture Studio**: previews the selected model and controls its market-image composition.
- **Selection, Settings & Info**: edits metadata for the active queued file and shows its generated filenames and status.
- **File List & Output Actions**: holds the import queue and the capture, export, and synchronization actions.
- **Top toolbar**: refreshes local and remote IDs, opens Sheets settings, reports Sheet connectivity, reports local ID collisions, and displays operation messages.

## 5. Standard import workflow

### Step 1: Refresh IDs

Click **Refresh IDs** before starting a final import session.

This rescans project assets, refreshes permanently claimed IDs from Google Sheets, and updates the **Last** and **Next available** indicators. If the Sheet is unavailable, you can still prepare metadata and test captures, but you cannot perform final ID-based writes.

### Step 2: Add GLB files

1. Click **Add GLB Files…**.
2. Select one or more `.glb` files from any accessible folder.
3. Select a row in the queue to edit and preview it.

Each row is an independent draft. Changing one row's item name, ID, or metadata does not change the other rows.

The importer rejects unreadable files and GLBs with external dependencies. Convert or repack such a model as a self-contained GLB before trying again.

### Step 3: Enter metadata

For each queued file, complete the fields in **Selection, Settings & Info**:

| Field | How to use it |
|---|---|
| **Main category** | Select the asset's top-level category. This controls its ID range, naming prefix, gender rule, and destination folder. |
| **Subcategory** | Select the closest configured type. It also determines the saved camera profile. |
| **Gender** | Required only for categories configured to use gender, such as clothing. Choose Female, Male, or Unisex. |
| **Item name** | Enter a human-readable name, such as `Summer Sweater`. The importer converts it to a lowercase filename-safe slug. |
| **Item ID** | Leave **Auto** enabled for normal work. Disable **Auto** only when a specific valid six-digit ID has been assigned. |
| **Buyable** | Enable if the item may be purchased. |
| **Sellable** | Enable if the item may be sold. |
| **ID in filename** | Includes the ID in generated filenames. This is mandatory for Clothes and Furniture. It can be disabled only for configured optional categories. The database record still keeps its ID. |
| **Confirm update…** | Enable only when deliberately replacing files already owned by this same catalog record. It never permits overwriting another record's files. |

Review the read-only **Asset filename** and **Sprite name** fields. They update as you edit the record.

For a batch with the same classification:

1. Finish the shared category settings on one active row.
2. Multi-select the intended rows in the file list.
3. Click **Apply Category Settings to Selected**.

This copies category, subcategory, gender, buyable/sellable flags, and filename-ID policy. Per-file item names, IDs, paths, generated names, validation, and statuses remain independent.

### Step 4: Compose the preview

Use the preview controls to frame the selected model:

- **Left-drag**: orbit.
- **Shift + left-drag**: pan.
- **Middle-drag**: pan.
- **Mouse wheel**: zoom.

The importer normalizes model bounds for consistent framing. Camera angles are saved by main category and subcategory, so similar assets can reuse the same presentation. Switching files does not reset the profile.

Click **Reset Camera Angle** only when you want to reset the active category/subcategory profile. Other profiles are unaffected.

For a non-destructive check, click **Temporary Capture Test**. The importer renders a test image to Godot's user data directory without reserving an ID or writing project assets.

### Step 5: Validate the draft

Before capture, check that:

- The correct model is visible.
- Category and subcategory are correct.
- Required gender is selected.
- Item name is specific and spelled correctly.
- Generated filenames are correct.
- **Sheets: connected** is shown.
- No error is shown for the active record.

The local audit may report the project's known pre-existing duplicate ID `310148`. This warning does not modify existing assets and does not prevent unrelated valid imports.

### Step 6: Capture and save

1. Select one or more ready rows in the queue.
2. Click **Capture & Save Market PNG Image**.

For each selected record, the importer:

1. Validates its metadata and destinations.
2. Atomically reserves a permanent six-digit ID in Google Sheets.
3. Copies the source GLB to its configured project category folder.
4. Renders and saves a transparent 1024×1024 PNG.
5. Advances the record to **Captured**.

An ID reservation is permanent, even if the import is abandoned. IDs are intentionally never recycled. Retrying the same draft uses its existing `record_id` and reservation rather than creating another one.

### Step 7: Export the managed catalog

After capture, select the captured rows and click **Export CSV / JSON**.

This atomically upserts each record into:

- `data/asset_catalog.json`
- `data/asset_exports/asset_catalog.csv`

The CSV is regenerated deterministically from the managed JSON catalog. A successfully written record advances to **Exported**.

### Step 8: Synchronize Google Sheets

Select the exported rows and click **Sync Google Sheets**.

This completes or updates their remote rows, changes their Sheet status to `ready`, and advances each local draft to **Synced**. Repeating the operation is safe because synchronization matches the stable `record_id`.

### Step 9: Verify the result

For important assets, verify:

- The standardized GLB exists at the displayed project destination.
- The PNG is 1024×1024, transparent, correctly framed, and non-empty.
- The JSON and CSV rows contain the correct metadata and paths.
- The Google Sheet contains one ready row with the same record ID and item ID.

## 6. Status meanings

| Status | Meaning | Next normal action |
|---|---|---|
| **Draft** | The file and metadata are being prepared. No permanent ID is guaranteed yet. | Complete validation, then capture. |
| **Reserved** | Google Sheets permanently assigned the record's ID, but local capture did not finish. | Retry **Capture & Save Market PNG Image**. |
| **Captured** | The standardized GLB and PNG were written. | Run **Export CSV / JSON**. |
| **Exported** | The managed local JSON and CSV catalogs contain the record. | Run **Sync Google Sheets**. |
| **Synced** | The local outputs and remote ready row are complete. | Verify the result; no further action is required. |
| **Error** | The last operation failed or validation found a problem. | Read the displayed message, correct the cause, and retry the appropriate action. |

Drafts, operation progress, camera profiles, and absolute source paths are saved under `.godot/dear_dear_asset_importer/`. Because this state is journaled, reopening the project normally restores interrupted work.

## 7. Naming rules

Item names are converted to lowercase snake-case. Source-only suffixes such as `_Rig` are removed from newly standardized names.

Clothing uses:

```text
<gender_code>_cloth_<subcategory>_<item_slug>_<id>.glb
```

For example:

```text
f_cloth_top_summer_sweater_310149.glb
f_cloth_top_summer_sweater_310149_s.png
```

Other categories use:

```text
<category_prefix>_<subcategory_prefix>_<item_slug>_<id>.glb
```

The market image always uses the generated sprite name, which is the asset name followed by `_s`.

Gender codes are:

- Female: `f`
- Male: `m`
- Unisex: `u`

## 8. ID ranges

IDs are six-digit strings. Only configured ranges are available; unspecified and reserved blocks are rejected.

| Category | Available IDs |
|---|---:|
| Seeds | 110000–119999 |
| Crops | 120000–129999 |
| Food | 130000–139999 |
| Furniture | 210000–299999 |
| Cloth | 310000–399999 |
| Beauty | 410000–419999 |
| Utility | 420000–429999 |
| Chat / Effects | 430000–439999 |
| Recipe / Craft | 610000–699999 |
| Market / Shop | 710000–999999 |

Automatic allocation takes the highest permanently claimed ID in the relevant range and uses the next available valid value. It checks local assets, the managed catalog, queued records, and Google Sheets. Gaps are not reused.

Use a manual ID only when there is a specific team requirement. It must:

- Contain exactly six digits.
- Belong to the selected category's allowed range.
- Not be reserved.
- Not be used by a different local asset, catalog record, queued draft, or Sheet row.

## 9. Updating or recapturing a record

Use this procedure only when the existing output belongs to the same managed record:

1. Restore or select the original draft/record.
2. Confirm that its `record_id`, item ID, and destinations are the intended ones.
3. Enable **Confirm update of this record's existing output files**.
4. Adjust metadata or camera composition as needed.
5. Run **Capture & Save Market PNG Image** again.
6. Run **Export CSV / JSON**.
7. Run **Sync Google Sheets**.

The importer blocks a destination owned by a different record. Do not work around that protection by manually deleting or renaming managed files; resolve the conflicting metadata or destination instead.

## 10. Removing a draft

Select a queued draft and click **Remove Draft** when it should no longer appear in the working queue.

Removing a draft does not recycle an ID that has already been reserved. It also does not automatically delete completed project assets, catalog records, or Sheet rows.

## 11. Troubleshooting

### Asset Importer tab is missing

Open **Project → Project Settings → Plugins** and confirm that the Dear Dear Asset Importer plugin is enabled. If it was just enabled, reopen the editor workspace if necessary.

### Sheets: not configured

Open **Sheets Settings**, enter the Apps Script `/exec` URL and shared secret, save, and click **Refresh IDs**. If environment variables are set, remember that they override the editor fields.

### Sheets is configured but not connected

Check the operation message and verify:

- The URL is the deployed `/exec` URL, not the Apps Script editor URL.
- The shared secret exactly matches `SHARED_SECRET`.
- The deployment is active and accessible.
- `SPREADSHEET_ID` points to the intended Sheet.
- The computer can reach `script.google.com`.

After correcting the issue, click **Refresh IDs** again.

### Final capture is blocked while offline

This is expected. Final writes are blocked because the importer cannot guarantee a unique permanent ID without the server. Continue editing and use **Temporary Capture Test**, then reconnect and refresh IDs before final capture.

### GLB will not load

Confirm that the file:

- Has a `.glb` extension.
- Is readable and not corrupt.
- Contains its buffers and textures internally.
- Can be opened in a normal Godot 3D scene or another glTF viewer.

Re-export it as a self-contained binary glTF/GLB if necessary.

### ID is rejected

The ID may be outside the category range, in a reserved block, already claimed, or duplicated in the current queue. Click **Refresh IDs**, confirm the category, and normally return to **Auto** allocation.

### Existing destination is blocked

If the files belong to the same record, enable the explicit update confirmation. If they belong to another record, change the conflicting item metadata or investigate the ownership mismatch. The importer does not allow cross-record overwrites.

### Operation stopped after ID reservation

Keep the draft and retry **Capture & Save Market PNG Image**. The journal and stable record ID allow the operation to resume with the same reserved ID.

### Capture composition is wrong for several assets

The camera profile is shared by category/subcategory. Adjust the profile using a representative model, or click **Reset Camera Angle** for that active profile and compose it again. Other category/subcategory profiles remain unchanged.

### Local audit reports ID 310148

This is a known collision in existing project content. Existing assets are audited only and are not renamed or backfilled. Investigate it separately if the project team decides to clean up legacy data; unrelated new imports may continue.

## 12. Configuration and maintenance

Taxonomy, category prefixes, ID ranges, gender requirements, optional filename-ID behavior, and output folders are stored in:

```text
data/asset_import_categories.json
```

Project maintainers can add or adjust subcategories there without rewriting importer code. Make configuration changes through normal source control review because they affect naming, validation, destinations, and future ID allocation.

Existing assets are never automatically migrated, renamed, or backfilled when configuration changes.

## 13. Quick operator checklist

1. Open **Asset Importer**.
2. Click **Refresh IDs** and confirm **Sheets: connected**.
3. Add one or more self-contained GLBs.
4. Complete and review every row's metadata.
5. Compose the preview and optionally run **Temporary Capture Test**.
6. Select ready rows and click **Capture & Save Market PNG Image**.
7. Select captured rows and click **Export CSV / JSON**.
8. Select exported rows and click **Sync Google Sheets**.
9. Confirm the rows show **Synced** and verify important outputs.

