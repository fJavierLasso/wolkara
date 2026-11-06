# Compatibility

Applications that people have actually run with Tolkara. Add a row through a
pull request; say what you tested, on what hardware, with which execution mode
(Developer service, Local signing or External JIT), and what did not work.

| Application | Version | Device / OS | Execution mode | Works | Known problems | Profile |
| --- | --- | --- | --- | --- | --- | --- |
| World of Warcraft Classic (Classic Era, macOS arm64 client) | 1.15.x | iPad Pro M5, iPadOS 27 | Developer service | In-game login, world entry, movement, combat, spells, quests, trading, audio, intro cinematics, cursors, clean exit. Up to 120 FPS at graphics quality 8, 50% render scale. Launch without a Mac, including after reboot. | Character-selection top menu is oversized and misplaced. Voice chat unavailable (its separate helper app is not supported). Memory preparation at each launch (about 80 s before the 2026-09-27 speed-up; not re-measured since). Switching apps during startup may interrupt it. Shader coverage beyond the played areas is unverified. | [`wow-classic-era`](profiles/wow-classic-era) |
| World of Warcraft Classic (Classic Era, macOS arm64 client) | 1.15.9 (70003) | iPhone 16 Pro Max, iOS 27.0 | Developer service | User-confirmed startup, opening cinematic, login screen and mouse use with AssistiveTouch; runtime log records graphics window and audio. | Experimental. Region/language configuration required to avoid unsupported RegionPicker. AssistiveTouch required for the tested mouse setup. Account login, world entry, gameplay and controller input unverified. See [iPhone validation](#iphone-validation-2026-10-01). | [`wow-classic-era`](profiles/wow-classic-era) |
| World of Warcraft Classic (Classic Era, macOS arm64 client) | 1.15.x | iPad Pro M5, iPadOS 27 | Local signing | Login and gameplay (2026-09-27), with no debugger, helper or tunnel and no memory preparation. At startup the client's own unpacked code matched the signed page container byte for byte, and all 12,658 initializers ran into the original `main`. | Building the page container for this client needs a capture of its final code pages, which the app cannot produce on its own yet. | [`wow-classic-era`](profiles/wow-classic-era) |
| World of Warcraft Forever (Classic beta, macOS arm64 client) | 1.60.1 | iPad Pro M5, iPadOS 27 | Local signing | Login and gameplay (2026-09-27), with no debugger, helper or tunnel and no memory preparation. At startup the client's own unpacked code matched the signed page container byte for byte, and all 13,280 initializers ran into the original `main`. | Developer service not yet validated on this iPad. Same capture limitation as Classic Era. | [`wow-forever`](profiles/wow-forever) |
| World of Warcraft Forever (Classic beta, macOS arm64 client) | 1.60.1 (70170) | iPhone 16 Pro Max, iOS 27.0 | Developer service | User-confirmed login, world entry and about two hours of gameplay without reported problems (2026-10-02). Reported 60 FPS at 50% render scale and graphics quality 2. Controller support enabled using middle mouse click; controller menu navigation works. | Initial tests used a Bluetooth keyboard and AssistiveTouch; physical left mouse click did not activate the tested menu controls, while wheel-button click worked. The new [iOS keyboard and touch trackpad](docs/TOUCH_INPUT.md) were subsequently confirmed working by the user on this iPhone (2026-10-02). See [iPhone validation](#iphone-validation-2026-10-01). | [`wow-forever`](profiles/wow-forever) |
| Heroes of Might and Magic III: Horn of the Abyss (GOG, Windows x86, with the HD mod) | HotA 1.8.1, HD mod 5.8 | iPad Pro M5, iPadOS 27 | Developer service | New games on scenario maps: adventure map, towns, battles, AI turns with up to eight players over several days, saving and loading, music and sound, mouse and keyboard. Runs through Tolkara's builds of Wine and FEX, with the HD mod's GDI renderer. | Local signing cannot run it (FEX translates the game's code while it runs). About 33 s of memory preparation per launch. A double click is not recognised (Enter opens a selected town). Light grey margins when the HD mod letterboxes the game. Saving fails if launched with the development option `--case-insensitive-files`. Performance not measured. | [`heroes3-hota`](profiles/heroes3-hota) |
| Cyberpunk 2077 (GOG, macOS arm64) | 2.3.x (buildId 59052989568257053) | iPad Pro M5, iPadOS 27 | Developer service | Experimental software-memory mode completes all 6,540 initializers, main, GOG initialization, archives, scripts and shader caches, creates the game window, and visibly renders the opening cinematic with a Space-to-continue prompt. | Menu content and gameplay unverified. Early presentation samples are about 5 FPS, then settle near 1 FPS in the cinematic, with long pauses. Manual Space presses reach the adapter queue but have not visibly continued the game; routing 4 GiB pools to software passes the earlier Foundation allocation failure and reaches further loading. Loader and call-wrapper unwind support clears the GOG rich-presence abort on the iPad: the call reports its service error and returns, and loading continues. The merged-main run logs a main-menu presence state; visual menu and gameplay validation remain pending. Tests use a 3600-second watchdog timeout and a two-CPU query cap. See [VM investigation](docs/CYBERPUNK_VM.md) and [software-memory experiment](docs/SOFTWARE_MEMORY.md). | [`cyberpunk-2077`](profiles/cyberpunk-2077) |

## Wolkara integration on iPhone Duo (2026-11-05)

The signed Release tree published at `4d1a911` was installed as a separate
Wolkara app on iPhone Duo, iOS 27.2. Trusted USB enrollment completed and the
verified identity was imported into the device-only Keychain. After the user
approved the integrated local tunnel's iOS permission, `--local-execution-probe`
authenticated the developer service, prepared executable memory, confirmed
debugger detachment and executed our own return-42 fixture successfully.

This validates the new app's integrated startup with the Mac connected. It does
not establish a disconnected/reboot launch, full-game memory preparation or WoW
gameplay. No game was loaded or modified by the probe. Game-folder migration and
gameplay in this Wolkara bundle remain for the user to test. The existing
WolkaraForever installation was preserved.

## External JIT prototype (2026-10-07)

The isolated `WolkaraExternalJIT` target builds and installs on iPhone 16 Pro Max,
iOS 27, as **Wolkara JIT**. Its signed app has `get-task-allow` and no integrated
tunnel extension, Network Extension, special memory or shared Keychain
capabilities. The existing development identity was used; **actual free Personal
Team provisioning remains untested**.

With separately built StikDebug 3.1.13, iloader 2.3.6 pairing and LocalDevVPN,
the URL handoff prepared one 16 KiB page. After debugger detachment, our own
sample returned `42`; rewriting our sample then returned `1337`. The log and
the user-visible result both report PASS. The initial detach flag was briefly
still set when the script resumed the process; the prototype now waits up to
two seconds for confirmed detachment before its readiness decision. The final
build was reinstalled and the device probe passed again.

This is host-authored code only. No game was loaded, signed or modified, and
the existing Wolkara game container was not written. Full-game memory capacity,
startup duration, gameplay, cellular-only operation, reboot and free-profile
renewal are not established by this test. Normal integrated Wolkara also still
builds. See [setup, commands and acceptance gates](docs/EXTERNAL_JIT.md).

## Latest Wolkara gameplay report (2026-10-07)

### Downloader and Mac import check (2026-10-12)

A reported slow 50 GB update was a full download into staging: the normal
Wolkara app had no active `World of Warcraft` directory. The installed Mac beta,
1.60.1.70338, matched Blizzard's published EU build. Its 54,232,001,788 bytes of
shared Data were copied to the empty iPhone library while Wolkara was closed.
All 1,628 Data paths and sizes matched; after a transfer connection interruption,
the nine incomplete files were recopied and SHA-256 checked by readback. All 56
bundle/metadata/initial-configuration files were also SHA-256 checked, including
the unchanged original executable. No Mac account settings were imported.

The normal Wolkara target was rebuilt and updated in place with the rolling
download scheduler described in [the launcher notes](docs/WOW_LAUNCHER.md).
The sanitizer launcher suite passes, and the old scheduler fails the new
blocked-range regression. The signed iOS build succeeds. All 1,684 imported game
files retained their sizes and modification dates across app installation;
executable and configuration hashes were unchanged. No game was launched during
these checks. Download throughput on the physical iPhone and gameplay of this
new client build remain unmeasured. Existing partial download staging was retained.

### User-reported gameplay

The developer reports **60 FPS at graphics quality 4 on an iPhone 16 Pro Max**
in WoW Forever. Render scale, exact client build and a repeatable benchmark were
not supplied for this latest report; do not infer them from the older quality-2
session below. This confirms reported gameplay performance, not the fresh-download
flow or the latest update-recovery fix. Those require separate device tests.

## iPhone validation (2026-10-01)

The [WoW launcher branch](docs/WOW_LAUNCHER.md) was compiled for iOS on 2026-10-03.
The user tested the themed home screen on this iPhone and requested automatic
installation of detected patches. This revision implements native CDN updates,
verified data reuse, resumable staging and atomic activation. Synthetic tests
and isolated Mac-copy transactions pass: Forever 1.60.1.70205 selected
1,215,567 standard macOS objects (67,079,188,425 encoded bytes), fetched
248,252,461 missing asset bytes and verified all 143 loose files. The Mac source
installation was unchanged. The user subsequently completed the patch download
on the physical iPhone. Readback confirmed version 1.60.1.70205 and an executable
identical to the Mac original (SHA-256). Startup stopped before guest entry:
the loader incorrectly required a DONE marker after the complete rebase stream.
This revision accepts a stream ending at its declared length, retains operand
and target bounds checks, and validates all 241,069 rebases and 3,549 binds of
the readback executable without running it. **Device startup and gameplay after
this fix still need manual confirmation.** Fresh installation is covered only by synthetic
fixtures. AltStore PAL execution remains unproven. These launcher checks do not
extend the gameplay results recorded below.

The 2026-10-07 updater optimization persists verification receipts so ordinary
patches can reuse unchanged CASC segments without rereading all their payload.
The first update without receipts still checks existing content; Settings →
**Verify and repair game files** always forces a complete check. Synthetic
patch/resume/corruption tests, the simulator repair flow and the signed device
build pass. A 16 MiB synthetic warm planning pass reads zero payload bytes;
speed on the physical iPhone's full installation remains unmeasured. The first
device trial reported repeated **CASC data changed during the update** while
resuming 70235 → 70245. A follow-up revalidates only a changed segment's trusted
objects before allowing metadata-only recovery; checksum failures still block
activation. Synthetic metadata-change/resume and 64 MiB checkpoint tests pass;
a subsequent physical retry reached `activate` and `complete` in Xcode after
rechecking `data.075`. The logged counters were 67,488,524,145 bytes read and
44,033,527 reused during that adoption/resume pass. This is an observed update
completion, not a warm-patch speed measurement or a post-update gameplay test.
See [persistent verification](docs/WOW_LAUNCHER.md#persistent-verification-2026-10-07).

On 2026-10-06, the follow-up adds an [automatic touch controller](docs/TOUCH_CONTROLLER_PROPOSAL.md)
with a custom UIKit layout, and fixes clipped descenders in the home status.
Real GameController input and connection lifecycle are covered by synthetic
simulator fixtures. This touch-controller revision has **not yet been tested
in WoW on the physical iPhone** and does not extend the gameplay report below.

The subsequent Wolkara revision adds saved control opacity, separate rear/front
sizes, draggable groups/buttons and reset. Its original UIKit fixture verifies
preferences, bounds, all button/axis events and input suppression during editing;
the settings and editor were also inspected in the simulator. The app now has
its own name/icon and selects the build's startup route without a public picker.
The signed arm64 iOS build and strict signature check pass. The user subsequently
reported native keyboard/slider stalls while WoW and the controller continued
working; beginning the Control Center gesture released the UI. A follow-up fixes
UIKit starvation reproduced with a busy synthetic desktop-event queue and
publishes pending native UI changes after event processing. Regression tests,
manual simulator typing/slider drags and the signed device build pass. The
[UI-pump correction](docs/TOUCH_INPUT.md#native-ui-stalls-while-the-guest-continues-2026-10-06)
did **not** resolve the full device symptom: on 2026-10-07 the user reported
queued keyboard taps released by Control Center / Notification Center. The new
[visible draft editor and tracking-mode follow-up](docs/TOUCH_INPUT.md#visible-draft-and-tracking-mode-follow-up-2026-10-07)
remove per-key native document resets and service UIKit tracking work while the
keyboard/settings are open. Synthetic checks pass; resolution of the device
stall and frame-rate impact remain unverified. The toolbar now stays top center
regardless of keyboard/controller state, with a further optical pointer offset.
The draft's **Replace** action now selects all and replaces the focused field
instead of appending; an empty draft clears it. Reading the field's prior text
is still unsupported. Synthetic replacement/clearing and key-order tests pass;
WoW's handling of Select All on the iPhone needs user validation.

On 2026-10-07, the user reported a first-launch failure after installing from
Xcode, followed by a successful launch from the icon. The failed device log
records completed memory preparation and confirmed helper detachment, followed
by an `isLowPower` Objective-C exception on the native iOS Metal device during
initialization. Xcode's launch record enabled `MTL_DEBUG_LAYER=1`; the shared
scheme now disables Metal API Validation to match an ordinary icon launch.
A synthetic Metal-property probe passes in the simulator with validation both
on and off, so it does not reproduce the device failure. The user subsequently
reported that it now works after this correction (2026-10-07).

The subsequent haptics change adds optional phone feedback for controller and
toolbar buttons, plus one cue per stick-edge crossing with independent radial
hysteresis. Synthetic tests check pulse requests and unchanged controller input;
the physical feel and strength still need testing on the iPhone.

Results updated on 2026-10-02 with the Forever gameplay report below.

Experimental support was tested on an iPhone 16 Pro Max / iOS 27.0 with
Developer service. The generic arm64 build installed successfully. Trusted USB
enrollment and the local authenticated tunnel/capability probe passed. The user
confirmed a cold launch after reboot with the iPhone disconnected from the Mac.
On 2026-10-04 the first reported launch using cellular data, with Wi-Fi enabled
but unassociated, failed before preparation: the local route was running but
the TCP connection to the on-device developer service failed. Disconnected-Mac
launches do not establish cellular-only startup support. The branch now keeps
the local route alive and retries initial connection failures for up to two
minutes, with instructions to temporarily disable mobile data and restore it
after preparation. Synthetic recovery tests and compilation are separate from
physical evidence: **this recovery sequence is not yet validated on the iPhone**.
See [the iPhone guide](docs/IPHONE.md) for a reproducible setup.

The user confirmed that both Classic Era and Forever start and work through
the screens described below. Both required AssistiveTouch for the tested mouse
setup. These are manual device observations; the extent of input and gameplay
validation is recorded separately for each client.

### World of Warcraft Classic Era 1.15.9 (build 70003)

Memory preparation took 53–55 seconds for 87,425,024 bytes, all 12,658
initializers returned, and the original main ran. The user reached the opening
cinematic and login screen. The runtime log records a game window, loaded
Metal libraries and audio playback. The user confirmed mouse use with
AssistiveTouch enabled. Successful account login, world entry,
gameplay and performance have not been validated.

Initial launches stopped in `RegionPicker.nib`: its window, controls and
bindings are unsupported by the AppKit adapter. The source installation had
no `WTF/Config.wtf` to copy. Setting only `portal` did not resolve the failure;
setting `portal`, `textLocale` and `audioLocale` together to match the chosen
region and installed languages allowed startup to proceed. See the
[configuration workaround](profiles/wow-classic-era/README.md#region-and-language-before-the-first-launch).
No game executable was modified.

Controller input remains unverified. With `GamePadEnable=1`, a GameSir G8+
using its Switch profile did not control the login screen. A reported crash
in that attempt was a clean guest exit in the captured log: main returned 0,
startup returned PASS, and the host ended its session normally. No related
system crash report was available. The action that triggered the exit is
unknown. The build did not include the experimental controller-hiding adapter.
ConsolePort 3.2.7 installation was subsequently verified (interface 11509),
but addon loading inside a character and physical input were not validated.
These results do not establish gamepad support at login.

### World of Warcraft Forever 1.60.1 (build 70170)

On 2026-10-02 the user confirmed successful login, world entry and about two
hours of gameplay without problems on an iPhone 16 Pro Max / iOS 27.0, using
Developer service. The reported frame rate was 60 FPS at 50% render scale and
graphics quality 2. This is a manual report from the tested session, not a
benchmark across all areas or activities.

The initial setup used a Bluetooth keyboard and AssistiveTouch. The keyboard
was needed to enter account details. With AssistiveTouch
enabled, clicking the mouse wheel (middle button, not scrolling) selected the
controls used to enable controller support; left mouse click did not. The
controller could then navigate the menus. The separate
[touch-input implementation](docs/TOUCH_INPUT.md) now provides an iOS keyboard
and trackpad with two-finger scrolling. Its synthetic and simulator checks
pass, and on 2026-10-02 the user confirmed the new controls working correctly
in Forever on the same iPhone 16 Pro Max / iOS 27.0. Other-device input testing
remains pending. The two-hour gameplay/performance report above predates
these controls.

The working setup uses the beta's own `portal "test"` setting and the default
`TOLKARA_SYSTEM_ROOTS=YES` for the private build. Earlier attempts rejected
login with `BLZ51900003`. Matching the portal alone did not resolve it; the
initial build also lacked `CompatibilityRootCertificates.plist`. Login and
gameplay were confirmed after rebuilding with that public certificate
resource. The existing certificate-adapter tests passed with ASan/UBSan on
the Mac using all 158 packaged candidates.

Build 70170 was copied over 70124 with current Data files verified by path and
size, and the copied client bundle and metadata verified by SHA-256 readback.
Game files and iPhone settings were preserved during the subsequent Tolkara
app update. The original game executable was not modified.

### Palworld 1.0.8

The first native attempt prepared 351,895,552 bytes of executable memory in
209.602 seconds, then stopped before initializers at legacy rebase operation
1,000,001. The loader now bounds rebase work by the loaded image's pointer
capacity instead of a fixed million. A data-only Mac check of the unchanged
executable and its six carried libraries passed: the executable has 1,598,313
rebases and 14,217 binds.

With that fix installed, the next attempt prepared memory in 210.030 seconds,
completed all 5,741 initializers and entered the original main, then stopped.
The log includes unavailable libraries/stubbed imports and an unimplemented
`NSAppleEventManager` call, and ends with Unreal's crash reporter failing to
spawn (`EPERM`). The reporter failure does not identify the preceding fault.
No out-of-memory error was recorded in that runtime log; peak memory and the
original crash cause remain unknown. No game window or gameplay was validated.

## Runtime diagnostics

On 2026-09-26, `--sparse-memory-probe` passed on the iPad Pro M5 / iPadOS 27.
Tolkara's own assembly used 112 GiB of software address ranges and completed
18,600 scalar, SIMD, addressing and atomic fault/resume operations, using
96 KiB of backing pages. The subsequent opt-in Cyberpunk run uses full software
reservations and passes the original first-archive crash on the same iPad.
It opens all 32 archives and `final.redscripts`, then reaches an engine watchdog
timeout after over 33 million handled faults. No gameplay result is validated.
The experiment and instruction limitations are in
[Software-memory experiment](docs/SOFTWARE_MEMORY.md).

An entry records what one person observed. It is not a promise that the
application will keep working, and it says nothing about whether its publisher
permits it: read "Online games and account risk" in the [README](README.md).

## Controller-only follow-up (2026-10-07)

The user confirmed that Forever starts after restoring the enrollment reference.
They reported Lua errors with the experimental WolkaraTouch addon, so the addon
and touch-adventure mode were withdrawn. Controller mode now stays active: the
touch controller appears without physical hardware and hides when it connects.
The native trackpad remains available and the first-launch touch tutorial is gone.
Existing WolkaraTouch files are retired outside AddOns without deleting other
addons. Settings gain saved shoulder-position swapping and a compact layout.
Runtime validation of this revised controller layout on the iPhone is pending.

## Touch ability modifier delivery (2026-11-06)

On the iPhone Duo, the user reported that unmodified ability circles worked,
but modified circles activated only LT/RT even when held for a second. The
virtual-controller fixture reproduced a delivery problem: the modifier callback
already saw the ability button held, and button-up already saw the modifier
released. Final-state assertions had missed those intermediate states.

Modifier-down, button-down, button-up and modifier-up now use separate delivery
phases. All 32 held combinations and quick-tap callback sequences pass in the
synthetic controller fixture; cancellation discards pending presses, including
several overdue presses cancelled together. The signed update was installed over
the existing Wolkara app, together with the direct-camera cursor-warp correction;
its process remained running after launch. Gameplay confirmation is still pending.

## Touch intent and independent ability groups (2026-11-06)

The user reported that restarting a camera drag elsewhere still jumped, that UI
scaling needed independent four-button groups, and that dragging over an ability
should not activate it. The new fixture reproduced an absolute-position change
on touch-down even with zero event delta; the previous fix covered only deltas.

Mouse-off touches now wait for tap/drag intent. Drags keep the existing cursor
anchor from their first event, including before capture; taps click on lift.
Ability circles also commit on lift, while movement hands off to the camera or
trackpad without a controller press. Eight saved four-button groups can move and
resize independently; existing layouts migrate without resetting their positions.

Synthetic tests pass cursor polling/restarts, circle-to-host drag handoff, all 32
tap/quick-tap sequences, drag/cancel suppression, group geometry and persistence.
The signed update was installed in place on the Duo and its process was running
after launch. Physical gameplay confirmation of these three changes is pending.


## Repeated swipes, simple controller and shoulder bindings (2026-11-06)

- The user reports mouse-off dragging stops after the first swipe until moving
  the virtual right stick. Our adapter log still shows capture/release requests.
  The previous change froze event and polled cursor positions even before capture.
  Direct drags now advance the existing cursor by finger deltas while uncaptured,
  retain the requested anchor during capture, and synchronize screen/window queries
  on cursor warps. A new finger origin still cannot teleport the pointer.
- Tap the controller button to alternate Full/Simple; hold 0.6 seconds to enable
  or disable it. Simple keeps the left stick and menu, hides both rings, the right
  stick and LB/LT/RB/RT, and keeps enabled ability circles. Layout changes release
  held/pending input without reconnecting the device or altering saved positions.
- Ability circles can bind LB/RB with any existing modifier set. Their controller
  aliases share ownership with the regular shoulder buttons; serialized bindings
  survive reloads.
- Synthetic UIKit regressions cover repeated capture cycles at different finger
  origins on Pro, Pro Max, Duo and iPad window sizes; tap/drag cancellation; real
  virtual-controller shoulder delivery with all modifier combinations; hidden-area
  passthrough; full/simple restoration; tap/hold persistence and trailing-tap
  suppression. UIKit adapter regressions pass. No game input was automated.
- The emulation/sanitizer suite and clean staged-source tests pass. The new
  cursor-position regression fails against the previous adapter and passes with
  the fix. Signed Release bundle validation passes. Installed in place on the
  Duo after confirming the app was closed; normal launch/process confirmed and
  existing game data preserved. In-game camera confirmation remains pending.


## Simple-mode shoulder buttons (2026-11-06)

- The user confirms the repeated camera swipes from PR #16 now work in WoW on
  the Duo. This follow-up changes only controller presentation and placement.
- Simple mode retains the normal LB/RB buttons along with the left stick, menu
  and configured ability circles. LT/RT and the right cluster remain hidden.
- LB/RB use independent saved positions in Simple. Edit layout moves the buttons
  for the selected mode; Full keeps its existing slot-based positions, including
  shoulder swapping. Simple positions follow LB/RB identities and survive reloads,
  mode switches and later edits to Full. Reset clears both sets of positions.
- The real virtual-controller fixture verifies LB/RB press/release in Simple,
  independent edits in both modes, cancelled drags, saved-position reloads,
  both shoulder-slot orders, window clamping and no controller reconnection.
- Emulation/sanitizer and UIKit adapter regressions pass, as does the clean
  staged-source controller fixture. Reviewed the Simple screenshot. Signed Release
  bundle validation passes; updated Wolkara in place on the Duo after confirming
  the app was closed and confirmed normal launch. Game files were preserved;
  the user's in-game test of the new shoulder placement remains pending.


## Duo folding during Starting (2026-11-06)

- User report: opening/closing the Duo during Starting can leave a black screen
  and unresponsive phone. The app's 14:53 local crash report records SIGKILL by
  FRONTBOARD, `scene-update` watchdog `0x8badf00d`, with a five-second allowance.
  The main thread was in nanosleep under native startup; the runtime log had not
  reached the guest window. This confirms an app scene-update timeout, not a
  demonstrated device reboot or GPU fault.
- Cooperative main-thread sleep adapters service UIKit and commit layout only
  during pre-window startup. Original durations use a monotonic deadline; worker
  and nested sleeps bypass the policy. It is cleared on guest-window visibility
  and all startup completion/stop paths. No executable edits or game automation.
- Synthetic sleep tests cover deadlines, invalid arguments, interrupted remainders,
  aliased request/remainder, nested/worker bypass and disabling during a wait.
  A six-second UIKit fixture issued six orientation requests and delivered five
  geometry updates plus 150 timer ticks, with a longest timer gap of about 50 ms.
  The native blocking baseline delivered zero ticks/geometry updates and failed
  the same fixture. Physical Duo/WoW folding confirmation remains pending.
- The emulation/sanitizer suite, UIKit adapter regressions, clean staged-source
  sleep/scene fixtures and signed Release bundle validation pass. Installed in
  place on the Duo after confirming Wolkara was closed; normal launcher process
  confirmed and existing game data preserved. In-game folding remains unverified.

## Simple-mode shoulder defaults (2026-11-06)

- Default LB/RB centers in Simple now match the green/red target icons in the
  user's 1280x900 reference: (507,568) and (772,568), above the neutral abilities.
  They use the ability block's viewport transform, including its position and
  scale, while retaining the configurable shoulder-button size and safe-area
  clamping. Saved Simple positions still override the defaults; Full positions
  and shoulder swapping remain independent.
- Existing ability-layout and virtual-controller UI regressions pass, including
  input delivery, Full/Simple switching, editing, persistence and slot swapping.
  Signed Release build and bundle validation pass. Installed in place on the
  Duo after the user closed Wolkara; normal launch confirmed, game data kept.
  Physical confirmation of the new default alignment remains pending.

## Dictation language, camera restart and performance overlay (2026-11-06)

- The previous punctuation/task-hint trial did **not** fix the English title-case
  draft on the Duo, according to the user's screenshot. A synthetic English
  recording through on-device `es-ES` recognition reproduced title-cased words
  and recognition mistakes; the same audio through `en-US` returned normal
  sentence case. This supports the locale diagnosis without claiming to have
  inspected the recognizer's locale on the user's device.
- The draft now displays its speech language. English, Spanish and configured
  keyboard languages are selectable; the selection persists. A language change
  clears the draft and restarts only recognition, invalidating late results.
  It adds no Return/Esc or guest text. Transcript casing is not rewritten, and
  sending still requires explicit review. Native Speech punctuation is retained.
- Direct camera regression now invokes the real `CGWarpMouseCursorPosition`
  wrapper: uncaptured restore warps previously failed. A second regression
  reproduced an absolute hover update overwriting the anchor while a finger
  owned the gesture. Both failed before and pass after their respective fixes.
  The four-viewport fixture also covers repeated drags, capture/release,
  cancellation, resizing, trackpad mode and ability-circle handoff. The user
  subsequently confirmed that the combined update works correctly on the Duo.
- Ported the optional performance HUD from WolkaraForever (including late Metal
  lookup/enable from `227b69e`), with attribution retained. The in-game controls settings own
  its persisted toggle. Frame rate comes from Metal presentation timestamps;
  GPU timing covers the presenting command buffer only. No display-link FPS
  substitute, 120 Hz override, render preset or frame readback is enabled.
  Hidden/background HUDs stop polling and per-frame statistics. Invalid,
  duplicate and stale samples are rejected; re-enabling resets old history.
- Validation: 43 toolbar-controller checks, language/draft UIKit checks, direct
  camera regressions, HUD toggle/late-load/hide-show and synthetic 60/30 FPS
  interval tests, the emulation/sanitizer suite, signed Release build and app
  bundle checks passed. Synthetic metrics do not establish game FPS on the Duo.
  The installed build also retains previously verified local audio/toolbar work;
  that unrelated work is excluded from this PR's new changes.
- Installed in place over Wi-Fi after the user closed Wolkara; normal launcher
  process confirmed. Game data was preserved. The user subsequently reported
  that the combined update works perfectly; no numeric device FPS was supplied.

## Double-tap stick clicks (2026-11-06)

- Double-tapping the left/right stick sends one L3/R3 press and release. The
  lower-right safe-area quadrant also accepts R3 on bare game content while the
  virtual controller is visible, including Simple mode. Toolbar, ability circles,
  other UIKit controls, indirect pointers and settings/editing are excluded.
  Dragging at the existing eight-point threshold defeats tap recognition;
  joystick lifts remain immediate. UIKit delays background tap endings to
  distinguish a single click from R3, cancelling the taps when R3 is recognized.
- Apple's native hidden virtual controller did not expose either stick button in
  the simulator, even when requested. A scoped compatibility extension provides
  the missing buttons using public writable controller snapshots. Only registered
  touch controllers are extended; their identity, axes and existing buttons remain
  intact. Discovery, dictionaries, per-button/profile callbacks and captures expose
  the added buttons. Physical/unregistered controllers and snapshots are excluded.
- Native-controller fixture checks pass for initial discovery, polling, callbacks,
  captures, pulse release and settings/mode cancellation. A separate unregistered
  native-controller fixture confirms isolation. Full controls/32 ability-chord,
  lifecycle and direct-camera regressions also pass. These synthetic tests do not
  prove physical double-tap recognition or in-game L3/R3 behavior; device validation
  remains pending.
- Signed Release build and bundle validation pass, including the new controller
  bridge in the packaged AppKit adapter. Installed in place over Wi-Fi after the
  exact-bundle guard confirmed Wolkara was closed; normal launch confirmed and
  game data preserved.
