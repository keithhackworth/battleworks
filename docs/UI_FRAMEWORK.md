# BattleWorks UI framework

In Battle Royale, the BattleWorks Home page opens automatically in Studio and
in the published client. In other modes, Studio still provides **Open UI Demo**
with a **Close** button for previewing the shell. Home opens a dossier with Personnel and Debrief tabs. The Debrief
shows sample data. Its links and the Personnel actions open the demo routes.
In Battle Royale, Training Grounds opens the live Playground through the
existing session. The dog tags stack into the Menu box below the Roblox controls. Click the
box to drop them back down or park them again.

Home reads optional artwork from `home/paper.png`, `home/bunny-tank.png`,
and `home/river-crossing.png` through `UIAssets`. It uses a generated paper
finish and in-engine previews until those images are registered.

The header uses `branding/logo3.png` when it is registered in `UIAssets` and
shows the BattleWorks text title until then.

The default theme picks complete dog tag images from `dogtags/`.
A menu uses each variant at most once until it has used the entire pool.
Artwork stays fixed through resizing and selection. All tags share a responsive
height and preserve their selected image’s aspect ratio. The engraved label
uses dark text with a subtle highlight below it. Tags grow by 4% on hover and 9% when selected. Their connectors follow
the eyelets as the tags scale.

The olive panel discovers its artwork in `footlockers/olive/panels`.
Components display a solid color when their artwork is unavailable.
To register the source PNGs, configure
the Open Cloud credentials, then run the import and sync the generated modules.
[UI image import and configuration](UI_ASSETS.md)

```sh
node tools/import-ui.js assets/ui
```

## Instantiate the shell

`UI/App.luau` creates the ScreenGui, router, and standard layout. The shell
stays mounted across routes. An instance of the app owns its resize listener
and the layout instances. Call `app:destroy()` when closing the shell.

```luau
local App = require(client.UI.App)
local app
app = App.new(playerGui, {
    onClose = function()
        app:destroy()
    end,
    routes = {
        initialRoute = "home",
        items = {
            { id = "home", text = "Home", route = "home" },
            {
                id = "supply",
                text = "Supply",
                route = "supply",
                icon = "icons/supply.png",
                rotation = -3,
                enabled = true,
                onSelect = function(item)
                    print(item.id)
                end,
            },
        },
    },
})
```

The default menu lives in `UI/Routes.luau`. Items appear in the supplied
order. Rotation is in degrees. `enabled = false` prevents button activation.
An icon path is relative to `assets/ui/`. The item's callback runs after
a successful click and receives the item. `App.new` also accepts a `theme`,
`pages` folder, or `layouts` table for other shells. To reuse just the menu,
call `DogTagMenu.new(parent, items, theme, assets, onSelect)`. Its container
is `menu.root`. Call `menu:resize(position, size, state)` from the host's
layout handler and `menu:destroy()` when finished. The optional menu-level
callback can return false to reject selection.

## Add and mount a page

The default Rojo client tree maps `src/client/Pages` to the `Pages` folder
next to `UI`. Create either `Pages/details.luau` or
`Pages/details/main.luau`. Sibling modules in a page folder can be required
from the entry point. The router loads the entry point on the first visit.
Add a menu entry when a route should appear in navigation.

```luau
return {
    layout = "standard",
    title = "Supply Details",
    mount = function(context)
        local label = Instance.new("TextLabel")
        label.Size = UDim2.fromScale(1, 0.15)
        label.Text = "Supply Details"
        label.Parent = context.content

        context.scope:add(context.layout.changed:Connect(function(state)
            label.TextSize = math.round(18 * state.scale)
        end))
        label.TextSize = math.round(18 * context.layout.current.scale)
    end,
    unmount = function(context)
        -- Release page-specific state here. The scope releases tracked resources.
    end,
}
```

Each mount gets its own context with `router`, `assets`, `theme`, `layout`,
`content`, `route`, `params`, and `scope`. Parent page UI to `context.content`.
The router destroys that container on unmount. Use `context.scope:add(resource)`
for external instances, connections, tweens, animation tracks, and cleanup
functions. The scope releases them in reverse registration order, including
when a mount fails. Keep lifecycle functions synchronous and keep per-visit
state in the mount context.

Use `context.router:navigate("details", { itemId = "example" })` from an event
handler to open a route programmatically. It returns a success boolean and,
on failure, an error message. Routes outside the menu clear the menu selection.
A repeat visit to the current route with no params keeps the current mount.

## Layout and header

`Responsive.luau` measures the available GUI size and calculates proportional
menu sizing. The standard layout gives the panel the remaining width. The
menu scales tags at their source aspect ratio and scrolls when the available
height cannot accommodate practical tag sizes. Tag rotation is included in
the sizing calculation.

`Layouts/Standard.luau` owns the placement of `Components/Header.luau`,
the menu, and the panel. The header uses the Roblox top bar height and the
safe area to the right of its controls. On narrow screens it moves below the
top bar. The workspace starts two pixels below the header and uses the full
viewport width. The logo scales from its registry aspect ratio, with the
page title immediately beside it. A layout can reserve toolbar space using
the header toolbar frame’s `PreferredWidth` attribute in pixels. A layout
that reuses `Standard.new` can pass a third argument with `margin`,
`columnGap`, and `headerGap` overrides. The router supplies the
game title and the page’s optional `title` or menu label. Additional layouts
can be registered by name with `App.new`. A layout factory implements
`new(parent, options)` and returns `root`, `content`, `resize`,
`setSelected`, `setHeader`, and `destroy`. Pages use the same mount
contract across layouts.
