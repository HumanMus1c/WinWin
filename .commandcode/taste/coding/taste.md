# Coding preferences

- Prefers upgrading legacy Material 2 widgets to current official Material 3 equivalents rather than leaving them in place — e.g., `MenuAnchor`/`MenuItemButton` over `PopupMenuButton`, `DropdownMenu` over `DropdownButton`, `RadioGroup` over `RadioListTile`'s deprecated `groupValue`/`onChanged`. Trend toward eliminating deprecated/legacy components fully (targets "清零", not partial). Confidence: 0.65
- When introducing a new widget, aligns with patterns already used elsewhere in the same repo (对齐项目已有范式) instead of inventing a new approach. Confidence: 0.5
- When a legacy API has no clean modern equivalent, prefers keeping it and documenting the rationale rather than forcing a hacky migration (recorded, not silently degraded). Confidence: 0.5
- Preserves existing visual/interaction semantics (colors, tooltips, selected-state highlighting) when refactoring widgets. Confidence: 0.5
