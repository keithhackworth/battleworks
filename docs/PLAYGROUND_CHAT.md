# The Playground multiplayer chat

The Playground has a compact Chat button in the lower-left safe area, on foot and in tanks. Tap/click to expand or collapse; the badge counts new global deliveries while collapsed. On keyboard, Enter opens the panel and Roblox focuses its managed input; Enter submits and Escape cancels. In Mouse Direct, Enter opens chat without an Alt gesture; Alt remains the existing way to reach other HUD controls. On touch, expand Chat and tap the 44-pixel input field to use Roblox's native keyboard/send action.

## Architecture and safety

Before implementation, the HUD/input/game-mode wiring and project chat settings were inspected. There were no project chat overrides. RoyaleClient owns a persistent battle client, on-foot presentation and shell transitions; the input controller already releases manual commands for ordinary text focus. Touch controls occupy the lower left/right and FIRE occupies the bottom center. The default chat configuration has alignment/scale but no arbitrary offset above those controls.

This milestone uses Roblox's native **TextChannelWindow** for global RBXGeneral history and **ChatInputBarConfiguration.TextBox** for managed input. Only the surrounding collapsible dock, status label and unread badge are game UI. Native rendering owns sender display names, message content, recent history, scrolling, delivery updates, reporting/muting/translation and accessibility behavior. The game does not read Text, PrefixText or Translation, render its own player messages, call SendAsync, or create message RemoteEvents. It also works without access to message text under platform-integrated chat; that rollout is not enabled/disabled by this change.

The Rojo project explicitly selects TextChatService and Roblox's default channels/commands. No custom channel, AddUserAsync call, CanSend override or delivery callback is introduced. The existing RBXGeneral membership, recipient privacy/blocking rules, filtering and moderation remain Roblox-owned. CanUserChatAsync is called only for the local player; sending is offered only when that check succeeds and Roblox supplies a matching TextSource with CanSend=true. Source changes and permission-query errors fail closed. Eligibility is never inferred from Studio mode or a game-owned flag.

The unread model sees only channel, status, MessageId and numeric sender ID. Sending updates, failures, own echoes and unrelated channels never add unread; each successful ID counts once within the bounded recent-ID window (200 IDs, badge capped at 99). Message rows are never appended by our code, so local echo/final delivery cannot produce duplicate game-created rows. Native Roblox controls actual history retention and auto-scrolling. Permission/error labels contain developer-authored constants, not player text.

## Input and lifecycle integration

InputController adds a generic owner-based text-entry focus bridge and a high-priority wrapper route for Return/Escape. The route opens/collapses the dock and passes the keys onward; Roblox owns native focus, submission, clearing and cancellation. It does not use CaptureFocus/ReleaseFocus or change a promoted chat TextBox.Text, which Roblox forbids. Both native input IsFocused and the owned field's Focused/FocusLost events participate in the bridge, including cases where CoreGui text focus is absent from GetFocusedTextBox.

Focus immediately emits neutral input, clears all provider-held state, disables native character movement and local proximity prompts, and uses the existing provider suspension to yield mouse lock. Another text-entry owner cannot be released by chat blur. Royale's separate F/controller-B exit action also checks the shared text-entry flag. When focus ends, the prior character/prompt state and selected mouse mode return, with no stale movement/fire. The aiming providers, aiming mode math, turret geometry, mechanical stops, firing, server combat and BW APIs are unchanged.

The chat instance and native history survive tank switches, destruction/respawn and on-foot transitions. Return to Main Menu hides the dock and disables managed chat input; World Editor and Classic create no Playground chat component. Rejoining reuses it. Local-player departure disconnects chat/source/config subscriptions, unbinds the keyboard route, clears its focus owner and restores original native configuration. Other player departures need no game-owned channel membership or per-player UI resource cleanup.

## Layout and limits

Desktop/tall-device chat sits above the existing lower-left controls. Short touch viewports use a modal expanded panel: the existing providers/native character controls hide while it is open, rather than placing chat over live sticks or FIRE. Very short viewports retain a 44-pixel input and collapse the history display. Collapse restores the previous controls. Safe-area insets, native fonts and native message rendering remain enabled.

A client that cannot create TextChannelWindow gets an update notice, no alternative sender, and keeps its original Roblox chat configuration. Modern Roblox is required for the positioned Playground panel. Chat history is session-local and Roblox-managed; there is no game chat storage/export or cross-server chat. The panel targets global RBXGeneral; this milestone does not implement a separate whisper/team frontend or programmatic messages.

## Verification and native acceptance

The automated harness checks production chat modules and the real RoyaleClient/InputController composition with native-service stand-ins. It verifies mode gating, collapse/unread and delivery-ID deduplication, failure/denial/revocation, native/owned-field focus, neutral output, Enter/Escape routing, Direct cursor restoration, touch layouts, multiple modal owners, delayed permission responses, lease/menu continuity and departure cleanup. Stand-ins cannot verify Roblox filtering, privacy policy or native input/rendering.

Native acceptance with two eligible accounts (Keith and Shane) is still required:

1. Sync and restart a Playground server. Join the **same** Team Test/published server with both accounts; check that Chat is available on foot and in different tanks. Synthetic Studio players may not have real chat eligibility; do not add a permission bypass if Roblox denies them.
2. Enter focuses the promoted native field from the collapsed panel; Enter sends exactly once and Escape cancels without sending. Verify the high-priority wrapper/native hotkey ordering, keypad Enter, the default slash hotkey, on-screen keyboard Send, and collapse while focused. If the native client does not focus the promoted field via its configured key, record that behavior rather than adding an unsupported focus workaround.
3. Each user sees the other's Roblox display name and filtered message once. Check automatic scroll, native recent history, sending/failure feedback and unread reset/capping. Verify reporting/muting and blocked/privacy-ineligible accounts using Roblox tools. Account denial/service failure must leave sending unavailable.
4. Hold movement/fire, then focus chat. Type W/A/S/D, C, F, Alt and BW-looking text: no driving, aiming shortcut, shot, entry/exit or BW command may occur. Blur must require fresh held input. Repeat Points/Direct/Joystick, including Direct lock/Alt behavior and turret orientation preservation.
5. Repeat focus through tank destruction/respawn, switching, character death, menu return/rejoin, window focus loss, CoreGui menus and disconnect. Confirm one chat panel, correct camera/controls, and no orphan input owner.
6. On touch, test tall and short phone/tablet safe areas: collapsed button clear of sticks/FIRE, modal expansion hiding controls, 44-pixel field, native keyboard/send, readable error state and restored controls after collapse. Check preferred-input/manual-input-selector changes and resizing.
7. Restart Classic and use World Editor/custom-world loading. Their original UI/input and native chat behavior must remain intact. Run two-player combat and the existing 3D aiming acceptance without chat focus to confirm no regression.

Sources: [TextChannelWindow and platform-integrated chat](https://create.roblox.com/docs/chat/platform-integrated-chat), [managed input and its security restrictions](https://create.roblox.com/docs/reference/engine/classes/ChatInputBarConfiguration), [TextChatService permissions/default channels](https://create.roblox.com/docs/reference/engine/classes/TextChatService).
