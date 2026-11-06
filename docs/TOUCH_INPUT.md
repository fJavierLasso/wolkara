# Touch controls and text input

The toolbar offers mouse/trackpad, Apple keyboard, gamepad, settings, leave app,
microphone and saved-text key controls. With mouse mode enabled, touches outside controls use the trackpad;
opening an editor releases held inputs. Settings → Edit layout lets you move both
the gamepad controls and individual toolbar buttons. Positions are saved relative
to the safe area and stay on screen when the window changes size. Transparency,
size, shoulder swapping and haptics remain configurable.

## Controller modes

Tap the toolbar controller button to alternate **Full** and **Simple**. Hold for
0.6 seconds to turn the virtual controller on or off; the selected mode is remembered.
Tapping while off changes the remembered layout without enabling it. VoiceOver
also offers an on/off action. A physical controller continues to take priority.

Simple keeps the left analog stick without its directional ring, LB/RB, the menu
button and enabled touch ability circles. It hides the right stick, A/B/X/Y ring
and LT/RT. Move LB/RB in Settings → Edit layout while Simple is selected to save
their positions separately from Full; each mode restores its own placement.
By default, Simple places LB/RB over the green/red target icons above the neutral
abilities in the reference screenshot. They follow the ability block's position
and scale until moved manually; saved positions take priority. Full mode's
shoulder swapping does not swap these default targets.
Hidden areas pass touches to the camera or pointer. Changing the
mode releases held inputs without reconnecting the controller or altering saved
positions. Use Full to edit controls that are hidden in Simple.

## Direct camera dragging

With mouse mode disabled, a tap clicks its screen position on lift; a drag turns
the camera. Touch-down does not move the guest cursor. After 8 points of movement,
the drag starts at the existing cursor position. Before mouse capture it moves
that position by the finger delta, so clients using absolute positions can detect
movement and request capture on every gesture. During capture, only relative
motion is sent and the requested cursor anchor stays fixed. Cursor warps update
both window and screen position queries. Lifting and restarting elsewhere never
uses the new finger origin as a cursor position. The game still controls
camera sensitivity. Enable mouse mode for pointer movement and dragging UI items.

The first finger owns the drag until it lifts. Opening native controls, losing
focus, changing input mode or resizing the viewport releases it; remaining samples
from that cancelled gesture cannot start another drag. A drag starting over an
ability circle follows the same camera path, or moves the pointer in mouse mode.

## Touch abilities

Open Settings → **Touch abilities…** and enable **Touch abilities**. The circles
send button combinations through the same virtual controller as the sticks.
They are active only while the touch controller is active; keyboard/draft entry,
backgrounding, hiding the controller or opening its settings releases held input.

The initial 32 circles follow the reference layout: the neutral D-pad and Y/B/A/X
diamonds are above, LT is on the left, RT on the right, and LT+RT below. The overlay
does not detect spells or inspect the game. Align it with the matching action bars.

- **Whole layout:** drag any circle to move the block; pinch or use the size slider
  to scale positions and diameters together. This is useful after changing WoW's UI scale.
- **Group of 4:** select a circle and move or resize its whole diamond independently.
  There are eight default groups: D-pad and face buttons for each modifier set.
  Existing saved positions and bindings are preserved when the groups are added.
- **One circle:** tap a circle to select it, drag it, resize it, and choose its button
  and modifier. Buttons include A/B/X/Y, the four directions, **LB** and **RB**;
  each supports None, LT, RT or LT+RT. Individual circles can be hidden/deleted; **Add** creates another.
- **Borders** controls the outline while playing; zero leaves invisible touch zones.
  The editor always shows labels and outlines. **Done** saves; **Reset** restores
  the reference arrangement without changing whether the feature is enabled.

Lifting a tap inside a circle commits one combination: modifiers first, then the
ability button, button-up with modifiers still held, and finally modifier release.
Resting a finger sends no controller input. Moving 8 points converts it into a drag;
returning to the circle does not turn it back into a tap. These circles are tap
shortcuts; use the regular controller buttons for held abilities. Opening controls or suspending
the controller clears pending input. Shared modifiers remain held while another
touch owns them. An incompatible simultaneous combination is rejected with
an orange outline instead of becoming a different shortcut. A conflicting manual
trigger press cancels the existing circle's chord before applying the manual input.
The layout fits inside resized windows without overwriting the saved arrangement.

## Apple keyboard

Select the game's text field before opening the keyboard. Write or dictate into
the visible native draft; iOS autocorrection and spelling are enabled. **Replace**
replaces the whole focused game field without submitting. **Send** (including the
keyboard's Send key) replaces it, sends Return once and dismisses the keyboard.
An empty Replace clears the field. Duplicate submission callbacks are ignored.
Escape, Tab, arrows, game backspace and Return remain available on the accessory
row. Newlines and control characters in pasted text cannot become extra commands.

The bridge cannot inspect which game field is focused. Whole-field replacement
uses the game's macOS Select All/backspace behavior. Opening a draft never reads
text or passwords from the game. Closing or backgrounding discards the local draft;
temporary focus changes used by Apple's text UI preserve it.

## Microphone and reviewed dictation

Tap the microphone to send one Return (opening WoW chat) and start on-device Apple
Speech recognition. Partial and final results appear **only in the visible draft**.
Tap the draft to pause recognition and edit it with Apple's keyboard. Confirm with
✓ to send exactly the reviewed text, Return, then one Escape to close the empty chat.
Cancel with × to discard it and send one Escape. Backgrounding discards without
sending any keys. Late speech/permission callbacks cannot reopen or submit a draft.

Check that chat opened before confirming; the compatibility layer cannot identify
the game's focus. Speech and microphone permission, a supported language and
on-device recognition availability are required. This uses `SFSpeechRecognizer`,
not Whisper. You can also use Apple's own dictation microphone on its keyboard.

## Saved-text key

Tap the key to edit and save a value. Its explanation is:

> Hold key to type what's in the box and send it. Useful for your password

Holding the key for 0.6 seconds types the stored value and sends one Return. It
never opens chat first: select the destination field yourself. A tap only edits;
an empty save deletes the value. Storage uses this device's unlocked Keychain,
with no synchronization, clipboard copy, plaintext config or input diagnostics.
Unsaved editor text is cleared when the app enters the background. Wolkara and
WolkaraForever do not share this credential store.

## Implementation and checks

`translation/AppKit/TouchControls.m` owns UIKit editing; `AppKit.m` converts an
explicit submission into balanced macOS key events. `ToolbarDictationController`
owns the reviewed voice transaction. `SavedTextController` and `SavedTextStore`
keep stored values out of ordinary event diagnostics. The native-control event
pump services both default and tracking modes while the guest owns the main loop.

Run `tools/test_toolbar_dictation.sh --self-test` and
`tools/test_touch_controls_ui.sh --self-test`. The latter also accepts
`--saved-text-test`, `--review-draft-test`, `--toolbar-test` and
`--tracking-progress-test` with `--self-test`. Tests use synthetic app views,
speech/audio doubles and a Keychain double. The ad-hoc simulator fixture cannot
prove real device Keychain persistence or microphone capture; those require the
signed app on a physical device. No game input is automated by these tests.

`tools/test_touch_abilities.sh` checks all modifier combinations, ownership and
reference-layout geometry, plus quick taps and cancellation with a deterministic
clock. Modifier/button delivery uses separate 1/30-second phases: virtual-controller
callbacks read the live profile, so setter order within a single turn is insufficient.
`tools/test_touch_gamepad_ui.sh --self-test-input` checks all three edit modes and
the 32 tap-on-lift/quick-tap callback sequences through an actual iOS virtual controller in our
synthetic fixture; `--self-test` covers controller lifecycle. Gameplay validation
still requires the signed app on a physical device.

`tools/test_direct_touch_camera.sh` (also part of `test_translation_sim.sh`) checks
cursor capture/warps, unchanged polled position on touch-down/restart, delta continuity
at different touch positions and viewport sizes, tap intent, circle drag handoff,
cancellation, finger ownership, trackpad movement and
indirect pointer clicks. Its events are synthetic; it does not run a game.

## Stick clicks

While the virtual controller is active, double-tap the left stick for L3 or the
right stick for R3. Bare game content in the lower-right safe-area quadrant also
accepts R3, including in Simple mode. Controls and ability circles keep their own
touch behavior; settings/editing, keyboard visibility and physical controllers
disable these gestures. A drag defeats tap recognition at the camera threshold.
A background single tap waits briefly to distinguish it from the R3 double tap.

`TouchStickButtons` supplements missing buttons on our registered virtual
controller using Apple's public writable snapshots. It extends only the owned
profiles; physical controllers and unrelated snapshots are forwarded unchanged.
The input fixture covers discovery, polling, button/profile notifications,
captures and balanced press/release. Run `tools/test_touch_gamepad_ui.sh
--self-test-input --unregistered-controller-test` for the separate isolation
check (iOS permits only one active native virtual controller).
