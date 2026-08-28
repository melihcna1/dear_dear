# Dear Dear Asset Importer

The plugin is enabled in `project.godot` and appears as **Asset Importer** beside Godot's 2D, 3D, Script, Game, and AssetLib workspaces. It does not change or replace the game's main scene.

User manuals: [English](USER_MANUAL.md) · [Türkçe](USER_MANUAL_TR.md)

## Workflow

1. Open **Asset Importer** and use **Add GLB Files…**. Only self-contained binary GLBs are accepted; source files are never moved or renamed.
2. Edit the active row's category, subcategory, gender, item name, flags, and automatic/manual ID mode. Each queued file retains its own metadata. **Apply Category Settings to Selected** copies only the shared classification fields.
3. Orbit with left-drag, pan with Shift-left or middle-drag, and zoom with the wheel. Camera profiles persist by category/subcategory. **Lighting Settings** adjusts ambient, key, fill, and rim energy for both the preview and saved PNG. **Reset Camera Angle** resets only the active profile.
4. Configure the Apps Script `/exec` URL and shared token through **Sheets Settings**, then click **Refresh IDs**.
5. Select one or more rows and run **Capture & Save Market PNG Image**. The server permanently reserves each six-digit ID before the plugin copies the standardized GLB and saves its 1024×1024 transparent PNG.
6. Run **Export CSV / JSON** to upsert captured rows into `data/asset_catalog.json` and regenerate `data/asset_exports/asset_catalog.csv`.
7. Run **Sync Google Sheets** to complete the reserved spreadsheet rows. All actions are idempotent by `record_id`.

Drafts, incomplete operations, recent camera profiles, and absolute source paths are stored below ignored `.godot/dear_dear_asset_importer/`. Spreadsheet credentials remain in per-user Godot editor settings; the environment variables documented in `google_apps_script/SETUP.md` take precedence.

## Safety and updates

- Existing project assets are scanned for ID use and collisions but are never renamed or backfilled. Keep legacy source models outside the project until they are processed by the importer; copying ID-bearing source filenames directly into `res://assets` will correctly reserve those IDs.
- New outputs cannot replace unrelated files. To recapture a record already owned by the managed catalog, enable the explicit update confirmation for that row.
- Automatic allocation uses the highest permanently claimed ID plus one and does not recycle gaps.
- Manual IDs may use a genuine gap, but every GLB/FBX filename, queued draft, managed catalog row, and Sheet reservation is still treated as an owner. Collision errors identify the local owner when available.
- Preview and **Temporary Capture Test** work without Sheets. Final project asset writes require a successful server reservation.
- Category labels, active ranges, filename prefixes, gender rules, optional ID behavior, and destination paths are configured in `data/asset_import_categories.json`.
