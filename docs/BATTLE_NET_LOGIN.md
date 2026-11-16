# Experimental Battle.net browser login

Enable **Settings → Battle.net browser login (experimental) → Use Battle.net
browser login**, then press Play. After checking game updates, Wolkara opens
Blizzard's HTTPS login in a private WebKit window. Enter your Battle.net email
and password there and complete any CAPTCHA or verification yourself. On
success Wolkara closes the browser and starts the unchanged macOS WoW client.
The region/language selected on Wolkara's home screen are used for this route.
To return to manual in-game login, choose **Use the game's login** in Settings.

This is an experiment, **not yet confirmed to authenticate an account on iOS**.
Receiving a ticket or preparing launch options does not prove game login.
Confirmation requires actual world entry and the game's own Connection.log
reporting a token-based login. The local reported manual-login failure was
status 14400 after a CAPTCHA form submission; this does not establish its cause.

## Relation to Scuffle

[Scuffle](https://github.com/nyrda/scuffle/tree/5efccb44777bba7e28e70ef782564b713e7373b5)
uses Blizzard web authentication plus a Windows DPAPI/registry game handoff.
Wolkara runs the native macOS client, so that helper cannot be reused directly.
This implementation follows [Waypoint's native Mac flow](https://github.com/wowlocal/waypoint-launcher/blob/a9aa570adc4afcc36420314bb6bc33d24caf8b49/Sources/WaypointCore/LaunchOptions.swift):

1. Open `https://<region>.battle.net/login/en/?externalChallenge=login&app=WoW`.
2. Collect the top-level `http://localhost:0/?ST=…` redirect in the navigation
   policy, server-redirect callback, or the failing-URL field when WebKit rejects
   port 0 before the policy callback. The latter paths require our browser's
   current approved main-frame login navigation. Cancelled, superseded and
   policy-rejected callbacks cannot create a session. Reject malformed,
   duplicate or untrusted callbacks. Do not inspect forms,
   inject scripts, override TLS verification or automate submissions.
3. Encrypt the returned ticket in the native Mac launch-options format:
   AES-128-CBC/PKCS7, zero IV, PBKDF2-HMAC-SHA1 with the documented fixed entropy
   XORed with `NSUserName()` (1000 iterations, `someSalt`). This is the client's
   legacy interchange format, **not** a secure vault for persistent credentials.
4. Keep only the encrypted envelope in memory while preparing startup. Bind it
   to this game's executable hash, product, region, locale and a ten-minute limit.
5. Immediately before the runtime loads WoW, consume it once into this iOS app's
   private `net.battle` preferences domain (`Launch Options/WoW/WEB_TOKEN`,
   `ACCOUNT_TS`, `REGION`, `LOCALE`). Remove stale account/server selectors.
   Read back the written fields before proceeding, and append only
   `-launcherlogin -uid <selected-product>` to the normal launch arguments.
6. Clear the handoff after five minutes, on startup failure/game exit, and on the
   next normal app launch in case the preceding process was killed.

The BGS client, Windows helper and OAuth developer API are not included. A BGS
exchange might still be needed if the direct web ticket is rejected by this
client; the first device test will distinguish that from a native handoff problem.
The code neither reads the Mac's Battle.net credentials nor changes the original
game executable, system trust or authentication requirements.

## Current limits and validation

- Off by default. One explicit web sign-in per launch; no saved account/ticket,
  no background renewal, no retries after consuming a ticket.
- Battle.net email login only for now. Top-level redirects to external identity
  providers are blocked with an explanation. CAPTCHA subframes may load HTTPS
  resources. Closing the browser cancels without starting the game.
- Passwords and forms stay in WebKit. No callback URLs, tickets or account IDs
  are logged. WebKit storage is nonpersistent; private launch preferences never
  go to Documents or the shared authorization extension.
- Host tests use fake tickets and throwaway preferences domains. They cover an
  independent cipher vector, URL boundaries, duplicate callbacks, malformed
  tickets, app binding, expiry, single consumption and cleanup. Run
  `bash tools/test_wow_browser_login.sh`. Preferences tests need permission to
  write their temporary domain in the user's Library.
- `tools/test_wow_launcher_ui.sh` covers callback cancellation, main-frame
  restrictions, redirect delivery through WebKit error URL/string fields,
  stale/foreign navigation rejection, secret-free error messages and unchanged
  manual-login launching without network access.
- Do not export a real `net.battle.plist`, collect raw callback URLs or publish
  unredacted Connection.log when investigating an account test.

Source credits and licenses are in [NOTICE.md](../NOTICE.md).
