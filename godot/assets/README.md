# Art and Audio Assets

Assets are organized by shared use, level ownership, and music. New art should
go directly into the matching folder instead of the root `assets/` directory.

## Layout

```text
assets/
  common/
    ui/       Shared UI sprites, icons, panels, fonts.
    sfx/      Shared sound effects.
  levels/
    1-1_binary/
    1-2_mango/
    1-3_schrodinger/
    1-4_bbq/
    1-5_rent/
    1-6/
  music/      BGM and edited music files.
```

## Naming

- Use lowercase snake_case for new files.
- Prefix level-specific files with the level theme, for example
  `rent_bill_sheet.png` or `mango_background.png`.
- Avoid spaces in new file names. Existing files with spaces can stay until
  their chart/script references are migrated.

## Migration Notes

- When moving an asset, update every `res://assets/...` reference in scripts,
  charts, and `.import` files.
- Prefer moving one level at a time.
- After moving imported assets, open Godot and let it reimport before committing.
