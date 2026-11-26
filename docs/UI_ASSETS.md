# UI image assets

Keep original PNGs under `assets/ui/`. Organize them in any depth of directories
that makes sense for the UI. For example, a component can discover both
`footlockers/olive/corners/top-left/01.png` and
`footlockers/olive/corners/top-left/02.png` by listing their shared directory.
Paths are case-sensitive, use forward slashes, and include the filename
extension. Identical filenames in different directories have distinct identities.

## Import

Set `ROBLOX_API_KEY` in your local environment with **Assets Write** permission,
plus exactly one of `ROBLOX_GROUP_ID` or `ROBLOX_USER_ID` for the creator that
owns the experience. This is the same configuration used by the GLB importer.
Keep credentials out of the repository. The tool uploads PNGs as Roblox
`Image` assets. Source files can be up to 20 MB and must be smaller than 8000
pixels on each side. [Roblox Open Cloud Assets](https://create.roblox.com/docs/cloud/guides/usage-assets)

```sh
# Import a file or subtree already under assets/ui/.
node tools/import-ui.js assets/ui/icons/home.png
node tools/import-ui.js assets/ui/footlockers

# Preview a recursive import without credentials or writes.
node tools/import-ui.js assets/ui --dry-run

# Import an external directory, preserving paths relative to that directory.
node tools/import-ui.js /art/ui-export
node tools/import-ui.js /art/steel-tags --into dogtags/steel

# Import an external file into assets/ui/backgrounds/desk.png.
node tools/import-ui.js /art/desk.png --into backgrounds

# Preview or upload a trimmed logo.
node tools/import-ui.js assets/ui/branding/logo.png --trim --dry-run
node tools/import-ui.js assets/ui/branding/logo.png --trim

# Upload again even if the bytes match the manifest.
node tools/import-ui.js assets/ui/icons/home.png --force
```

External files without `--into` are imported at the root of `assets/ui/`.
Directory imports recurse through regular PNG files and skip symlinks. The
importer copies and uploads original bytes, preserving dimensions and alpha.
It uses SHA-256 to skip unchanged images at the same path. Replacing the PNG
at a registered path creates a new Roblox image and updates that path's
reference. Dry-run checks the input and reports the upload decisions.

`--trim` requires ImageMagick (`magick` or `convert` on PATH). It crops
fully transparent borders on images with transparency and pure white borders
on opaque images. Visible white artwork on transparent images is preserved.
If there is no content to crop around, it uses the original image. The source
PNG stays intact. The manifest and client registry report the uploaded
dimensions, and the manifest marks cropped uploads with `trimmed: true`.
Repeat `--trim` on later imports to retain the cropped version. Importing
the same path without it restores the full image. Dry-run reports the crop
without writing files or uploading.

The separate manifest at `assets/ui-manifest.json` records the filename stem,
relative source path, Roblox image ID, width, height, and SHA-256 for each
successful import. A failed upload keeps any prior reference for its path.
Batch imports report failures with a nonzero exit status and retain successful
entries. Imports are additive. Removing or moving a source file does not
remove its prior registration.

Commit the PNGs, the manifest, and the generated `src/shared/UIAssetData.luau`
together. Rojo syncs the generated data with the client registry. Verify that
the uploaded images pass Roblox moderation and are accessible to the target
experience in Studio. The importer registers images exclusively in the UI
registry. World Editor and gameplay asset pickers use their own catalogs.

## Client registry

```luau
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local UIAssets = require(Shared:WaitForChild("UIAssets"))

local home = UIAssets.get("icons/home.png")
if home then
    imageLabel.Image = home.image
end

local corners = UIAssets.listImages("footlockers/olive/corners/top-left")
local cornerFolders = UIAssets.listDirectories("footlockers/olive/corners")
local rootFolders = UIAssets.listDirectories()
```

`get` returns an immutable image record with `source`, `name`, `assetId`,
`image` (the `rbxassetid://` URI), `width`, and `height`, or nil for a missing
path. `listImages` lists the immediate image records in a directory.
`listDirectories` lists its immediate child directory paths relative to
`assets/ui/`. Both list functions return sorted, immutable arrays and accept
an empty string or omitted argument for the root. A missing directory gives
an empty array. A newly imported variation appears in its directory listing
when the updated data module loads.

Standalone images, texture atlases, and nine-slice textures use the same
image records. Their original dimensions are available to the future UI
framework for sprite regions and slice configuration.

See [the client UI framework](UI_FRAMEWORK.md) for the Studio demo and examples
of using registered artwork in components.
