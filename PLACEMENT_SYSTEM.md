# M-Star Style Placement System

This project now has a reusable coordinate-frame placement layer for Godot 4.

## Core Scripts

- `scripts/PlacementFrame.gd`
  - Stores position plus orthonormal local X/Y/Z axes.
  - Supports translate, rotate around pivot/axis, scale around anchor, set position, set Y/Z axis, and canonical `set_placement(position, x_axis, z_axis)`.
  - Regenerates missing axes with cross products and maintains a right-handed frame.

- `scripts/PlacementItem.gd`
  - A `Node3D` wrapper that applies `PlacementFrame` to Godot transforms.
  - Child `PlacementItem` nodes are naturally relative to their parent through Godot hierarchy.
  - Includes duplicate, recenter pivot, define axes, mate, visual validity feedback, and world/local placement helpers.

- `scripts/PlacementSnapper.gd`
  - Provides grid, pivot, vertex, edge, and surface snapping primitives.

- `scripts/PlacementGizmo.gd`
  - Draws local axes, pivot, and bounding box feedback for a target node.

- `scripts/Main.gd`
  - Application bootstrap connecting inventory, placement, and saving.

- `scripts/PlacementController.gd`
  - Owns world placement ghosts, camera controls, editing, stacking, pickup, and placed-object loading.

- `scripts/inventory/`
  - JSON-driven item catalog, unique item instances, stack-aware inventory model, wallet, market/cart/sell models, live 3D inventory previews, UI, and save service.

## Common Calls

```gdscript
item.set_placement_world(Vector3(0, 1, 0), Vector3.RIGHT, Vector3.BACK)
item.translate_world(Vector3(1, 0, 0))
item.rotate_around_world(Vector3.ZERO, Vector3.UP, deg_to_rad(45))
item.set_axis_z_world(surface_normal)
item.scale_around_world(anchor_point, 1.25)
child.mate_to(parent)
```

Orientation is never stored as Euler-only state. The source of truth is always a placement frame: position plus orthogonal local axes.

## Interactive Demo

Run `res://scenes/Main.tscn`.

- `I` opens or closes the 5x10 inventory.
- Inventory category filters show matching slots without changing the underlying slot order.
- Click an occupied inventory slot to begin placing one item.
- Only placeable inventory items begin placement.
- Drag stacks between slots to move, swap, or merge them.
- `Shift` + drag splits half a stack.
- Drag an item outside the inventory to begin placement.
- Hover an inventory slot to rotate its live 3D model and view its tooltip.
- Move the mouse to position the reserved item's preview on the placement surface.
- Move the preview over a placed item to stack on top of it.
- Left click places one item and continues while the selected inventory stack has items.
- `Escape` cancels placement without consuming the reserved item.
- Hold right click and drag to orbit the camera.
- Mouse wheel zooms the camera.
- `W`, `A`, `S`, `D` or arrow keys pan the camera.
- `R` / `F` move the camera focus up or down.
- Hold `Shift` for faster camera movement.
- `Q` / `E` rotate the preview.
- `X` / `Z` scales the preview up or down.
- All placement and edit scaling is uniform and changes in `0.1` steps, with at most three steps below or above the item's default scale.
- `G` toggles grid snapping.
- `Tab` toggles between placement mode and edit mode.
- In edit mode, left click a placed item to select it.
- In edit mode, drag the selected item to move it.
- In edit mode, `Q` / `E` rotate the selected item.
- In edit mode, `X` / `Z` scales the selected item up or down.
- In edit mode, `P` returns the selected placed item to inventory when space is available.
- `Ctrl+D` duplicates the selected placed item.
- `Delete` removes the selected placed item.
- `F5` saves inventory and placed objects.
- `M` opens or closes the market.
- Opening the market smoothly moves the camera to a character-focused left view while the market panel fills the right side.
- Market purchases must be added to the shopping cart before purchase.
- Cart lines allow 1-10 items and validate coins plus inventory space before purchase.
- The sell window only lists sellable Crops, Food, and Fish.
- Clicking a seed in inventory starts gardening placement; left click an empty placed pot to plant it.
- Left click a planted pot to advance a ready sapling, harvest a ready crop, or clear a withered crop.
- `Shift` + left click a planted pot removes the plant and leaves the pot empty.
- `F8` restores any missing catalog items so all 10 unique item types are available.
- `F9` loads inventory and placed objects.

Save data is stored at `user://savegame.json`. The initial inventory contains all supplied FBX items, with pots and candles configured as stackable. Item, sell-price, and gardening data are loaded from `res://data/items.json`, `res://data/sell_prices.json`, and `res://data/gardening.json`.
