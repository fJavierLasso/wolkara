# Wolkara

**World of Warcraft on iPhone and iPad, built on [Tolkara](https://github.com/tolkara/tolkara).**

Wolkara is an independent, experimental fork focused on the WoW experience:
choose an edition, download its macOS client on the device, keep it updated,
and play with touch controls or a physical controller. The game runs locally
through Tolkara's compatibility layer; it is not streamed from a Mac.

Tolkara's runtime and macOS API translation are the foundation of this project.
Wolkara adds the WoW launcher, downloader/updater and mobile input interface.
The upstream history, MIT license and [third-party notices](NOTICE.md) are retained.
Selected improvements from [WolkaraForever](https://github.com/jklock/wolkaraforever)
by **John Klockenkemper ([jklock](https://github.com/jklock)) and its contributors**
are integrated here: addon management, settings backups, audio-session coordination,
localization infrastructure, background pacing, the optional performance overlay
and build optimizations. Thank you
for that work. Wolkara's native keyboard, reviewed dictation, movable toolbar and
saved-text key include the refinements developed and tested together on iPhone.
The imported MIT [license](WolkaraForever-LICENSE) is retained and shipped in the app.

This project is not affiliated with or endorsed by Blizzard Entertainment.

## Try it with Xcode

**Start here: [Build and run Wolkara](docs/GETTING_STARTED.md).**

The current route needs a Mac with Xcode, XcodeGen and Python 3, your own Apple
developer signing with the required capabilities, Developer Mode on the device,
and one-time USB authorization. Use the **Tolkara** scheme: the app is displayed
as **Wolkara**, while the internal target name is retained for compatibility.

You do not need to install WoW or Battle.net on the Mac to build the generic
launcher. You need your own eligible game account/access to log in. Game files
are downloaded from Blizzard's CDN; no game code or assets are included here.

This is a source release for people comfortable with Xcode. There is no tested
public Wolkara IPA, App Store/TestFlight release or AltStore PAL install path.
A successful build alone does not prove that a signing profile permits startup.

This branch also includes an [External JIT prototype](docs/EXTERNAL_JIT.md)
(`WolkaraExternalJIT` scheme). It uses separately installed StikDebug and
LocalDevVPN without Wolkara's integrated tunnel or special memory entitlements.
Its synthetic execution test passes on iPhone; Personal Team provisioning and
WoW gameplay under this capability set remain untested.

## Features

- A single WoW home screen with edition, region and language selection.
- On-device installation and automatic update checks; required updates finish
  before Play becomes available.
- Resumable downloads, checksum verification and reuse of verified unchanged
  game data. Updates preserve settings and addons.
- Apple's keyboard with iOS autocorrection and dismissal after Send, plus a
  touch trackpad with two-finger scrolling.
- Direct camera dragging with mouse mode off keeps the cursor anchored when a
  finger lifts and restarts elsewhere; taps click their screen position on lift.
- A microphone button opens chat and transcribes speech into a visible local draft.
  Review or edit it before ✓ sends; × discards. Recognition callbacks never type
  into the game. Choose the spoken language in the draft (remembered between sessions);
  changing language starts a fresh draft without reopening chat. On-device Apple
  Speech availability and permissions are required.
- A key button: tap to edit a saved value; hold to type it and send once. Storage
  uses this device's Keychain, not the clipboard, config files or input logs.
- Physical controller support and an on-screen controller when none is connected.
  Tap the controller toolbar button to switch Full/Simple; hold to turn it on/off.
  Simple keeps the left stick, LB/RB and menu, hiding both button rings, the right stick
  and LT/RT. LB/RB positions are saved separately for Simple and Full.
  Touch ability circles remain available. Double-tap the left stick for L3 or the
  right stick for R3. With the touch controller active, double-tapping bare game
  content in the lower-right quadrant also sends R3, including in Simple mode.
- Optional touch zones over action bars, with editable controller shortcuts (including LB/RB),
  individual circle sizing, independent groups of four and whole-layout movement/scaling. The initial layout
  has neutral, LT, RT and LT+RT groups; enable it in Settings → Touch abilities.
  Taps activate on lift; drags over circles control the camera/pointer without activating an ability.
- Movable touch controls, opacity and size settings, shoulder-position swapping,
  an alignment grid and haptics. The mouse/keyboard/microphone/key toolbar also
  moves in Edit layout.
- An optional performance overlay in the in-game control settings shows presented
  FPS, frame intervals, GPU timing, thermal state, memory and battery. Tap to expand
  or collapse; drag to reposition. Monitoring stops when hidden or backgrounded;
  it does not raise the rendering limit. GPU timing covers the presenting command
  buffer, not all GPU work in the system.
- Settings → Game tools: import/manage addon ZIPs, browse CurseForge with your own
  API key, back up/restore WTF + Interface, enable gamepad, or reset graphics.
  Tools follow the selected edition. Imports require a matching TOC Interface
  version for the installed client; that check is not a gameplay compatibility guarantee.
- Release builds and optimized adapters, shader cache hits without a full byte copy,
  optional expensive diagnostics and a 5 FPS background rendering limit. Foreground
  rendering keeps the standard iOS frame-rate behavior; no 120 Hz override or M1
  graphics preset is applied.

## Moving an existing installation

Close the game in the source app first. In Files, move the **whole `World of
Warcraft` folder** into **On My iPhone → Wolkara**. Keep `_forever_`, shared `Data`
and hidden `.build.info` together, without nesting a second `World of Warcraft`
folder. Choose the same region and language in Wolkara. The released Forever
client uses product `wowf` and `_forever_`; older beta files are not a current copy.

Wolkara and WolkaraForever have separate app containers. Moving game files does
not transfer saved passwords, CurseForge credentials or app preferences. Normal
startup uses Wolkara's integrated Developer service after its one-time enrollment;
no separate LocalDevVPN app is needed for that route. A matching installation is
checked using metadata and its executable; full data verification is reserved for
an update or an explicit repair, and verified unchanged blocks can be reused.

## What has been tested

The developer reports **60 FPS at graphics quality 4 on an iPhone 16 Pro Max**
playing WoW Forever (Classic beta). This is a gameplay report, not a benchmark
or a promise for every scene/device. Render scale was not specified in this
latest report; the earlier quality-2 session used 50% render scale.

Forever login, gameplay and the touch controls have been tested on that phone.
Classic Era reached its cinematic and login screen. A Mac-disconnected launch,
including after reboot, has also been reported with the existing authorization.
The edition selector includes other WoW clients; their presence is not a
compatibility claim. See [COMPATIBILITY.md](COMPATIBILITY.md) for dated results.

The updater has synthetic regression coverage, isolated Mac-copy tests and a
recorded device patch installations. Xcode logs also confirm that the latest
metadata-recovery fix completed an on-device update. A complete first download
into an empty iPhone installation still needs end-to-end validation. Follow the [fresh-install checklist](docs/FRESH_INSTALL_TEST.md)
and report the exact commit and client build you tried.

## Current limits

- Setup is still a developer workflow, with personal signing and enrollment.
- Executable-memory preparation still takes several minutes on each launch.
  Keep the app in the foreground during this step.
- Cellular-only startup has an unresolved report; a disconnected Mac does not
  establish that every mobile-network condition works.
- Other devices, editions and signing methods need testing. Voice chat's
  separate helper process is not supported.
- Keyboard/input and update recovery are actively being improved. If something
  fails, include the exact message from Settings → Technical details and a
  redacted log, never account or pairing information.

## Development

```bash
tools/test_emulation.sh
```

Focused updater tests: `tools/test_wow_launcher.sh`. UIKit fixtures:
`tools/test_wow_launcher_ui.sh` (set `SIMULATOR` to an available simulator).
Read [CONTRIBUTING.md](CONTRIBUTING.md) before contributing.

- [Launcher and updater](docs/WOW_LAUNCHER.md)
- [Touch input](docs/TOUCH_INPUT.md)
- [Touch controller](docs/TOUCH_CONTROLLER_PROPOSAL.md)
- [Engine architecture](docs/ARCHITECTURE.md)
- [Advanced Tolkara build and execution modes](docs/BUILDING.md)
- [Distribution research and unverified routes](docs/WOLKARA_DISTRIBUTION.md)

The shared engine, adapters and non-WoW test fixtures remain in this fork to
preserve upstream compatibility and regression coverage. Public Wolkara builds
use the WoW home; alternative loaders/modes are development tools.

## What Tolkara does to the application

So that you can judge this yourself rather than take our word for it:

- The original executable is imported as a file, verified by SHA-256, and mapped
  into memory. It is never edited, re-signed, or included in the app bundle. The
  loader applies the same rebases and binds dyld would; those are runtime state
  in memory, not changes to the file. With Local signing, a copy of its final
  code pages is signed with your identity in a separate page container that
  stays on your Mac and your iPad.
- The loader answers a short, fixed list of calls itself instead of passing them
  to iPadOS, because they concern how the image was loaded: `mmap`, `mprotect`,
  `munmap`, `memcpy`, `memmove`, `memset`, `__clear_cache` (for the separate
  read-write and executable views of code memory), `pthread_jit_write_protect_np`, `dladdr`,
  `dlsym`, `_NSGetExecutablePath`, `CFBundleGetMainBundle`, `_tlv_bootstrap`,
  `dyld_stub_binder`, `__ulock_wait` and `sigaction` (the last only when you
  opt into crash logging). The list is in
  [`runtime/NativeGuest.m`](runtime/NativeGuest.m).
- Everything else the application imports resolves to the real iPadOS framework,
  to a translation library in [`translation/`](translation), or to a library the
  application carries in its own bundle. An import that nothing provides
  becomes a stub that logs and returns zero: generated at build time for the
  executable of a build made for it, and made at launch in a generic build (made
  for no particular application) and for the libraries an application carries.
  In a build made for one application, an import of its executable that nothing
  provides at launch stops the launch instead.
- Nothing in Tolkara exists to hide the environment from the application. It does
  not conceal debuggers, processes, the device model or the operating system.
  With Developer service, the debugger used to prepare memory detaches before
  the first application instruction runs, and nothing attaches afterwards.
  With External JIT, Tolkara asks the enabler's debugger to detach and does not
  start the application while any debugger is attached. Local signing uses no
  debugger.

## Policy

Wolkara builds on Tolkara as a compatibility layer. This fork will not accept:

- reading or changing an application's memory for any purpose other than
  loading it, including "trainers", overlays, bots or input automation;
- workarounds for anti-cheat, licence or integrity checks;
- redistribution of third-party application code, assets or operating-system
  components in this repository or its releases. The updater obtains game
  content directly from the vendor for the user's installation.

## Online games

Wolkara is not approved or supported by Blizzard. Successful execution does not
establish publisher approval or guarantee the safety of an online account.
The project provides no anti-cheat, license or integrity-check workarounds.

## Legal

Wolkara and the upstream Tolkara code are released under the [MIT License](LICENSE).
No game files or Apple operating-system components are included. Third-party
adaptations and reference material are credited in [NOTICE.md](NOTICE.md).

Wolkara is an independent project and is not affiliated with, sponsored by or
endorsed by Apple Inc. or Blizzard Entertainment, Inc. macOS, iPadOS, iPad,
Metal and Xcode are trademarks of Apple Inc. World of Warcraft and Blizzard are
trademarks of Blizzard Entertainment, Inc. Other names are the property of their
owners and are used only to describe compatibility.

You are responsible for having the right to use any application you run with
Wolkara, and for complying with its licence.

Wolkara: [source and issues](https://github.com/fJavierLasso/wolkara).
Upstream engine: [Tolkara](https://github.com/tolkara/tolkara) · [tolkara.org](https://tolkara.org).
