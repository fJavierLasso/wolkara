# Battle.net login

Choose **Login with Battle.net** or **Login ingame** immediately above Play.
The selection is remembered. Existing installations keep their previous choice;
in-game login is the default for new installations.

With Battle.net selected, Play checks game updates, reuses a remembered login
for the selected region, or opens Blizzard's login page. Enter your credentials
and complete any CAPTCHA/2FA yourself. Email sign-in returns to Wolkara
automatically. The Duo user confirmed that this route works on 2026-11-17.
The region/language on the home screen are passed to the native macOS client.

The login ticket is saved in the device-only iOS Keychain, available only while
unlocked, without iCloud synchronization. The integrated app uses its own private
access group, separate from the authorization tunnel's pairing group. Passwords
and provider forms are never captured. **Battle.net account… → Forget login /
Sign in again** removes the saved ticket for this region; press Play to obtain
a fresh one or switch accounts. This does not clear your browser's cookies.
Blizzard can expire or revoke a ticket; Wolkara does not silently renew it or
retry rejected tickets. If the game asks for login, forget it and sign in again.

A session launched with the Battle.net handoff hides and disables the key
shortcut, including stale saved-text actions. Its stored text and layout remain
intact. **Login ingame** neither reads the Battle.net ticket nor hides the key.
The toolbar follows the actual launch mode, not the persisted selector.

## Apple, Google and other linked providers

Choose **Apple / Google…** in the sign-in window, then **Open browser to sign
in**. Use the provider button on Blizzard's page in your normal browser. At the
end, Blizzard redirects to `http://localhost:0/?ST=…`, a page that cannot open.
Copy that final address, return to Wolkara, paste it in the private field and
press **Continue**. A blocked external redirect in the embedded login also
shows this alternative. The saved ticket is reused on later launches.

This is an explicit paste fallback, not automatic Safari handoff. The fixed
HTTP/port-zero return is not a supported custom-scheme or HTTPS callback for
[ASWebAuthenticationSession](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession/callback).
[Google restricts authentication in embedded user agents](https://support.google.com/faqs/answer/12284343).
We do not spoof a browser identity or inject scripts to bypass this restriction.
The browser only opens the initial Blizzard URL; Wolkara never sends a returned
ticket to a relay, reads the clipboard automatically, or inspects Safari storage.
The field is masked and cleared after use, invalid input or cancellation. Keep
the copied address private and close the finished browser tab afterwards.
A pasted ticket is only a credential candidate: the game service authenticates
it. The parser does not establish account ownership or prove world entry.
Apple/Google completion and reuse across real game launches still need a device
test; synthetic tests do not validate either provider's login requirements.

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
4. Remember the returned ticket only in the app-private Keychain. Keep the
   encrypted envelope in memory while preparing startup. Bind it
   to this game's executable hash, product, region, locale and a ten-minute limit.
5. Immediately before the runtime loads WoW, consume it once into this iOS app's
   private `net.battle` preferences domain (`Launch Options/WoW/WEB_TOKEN`,
   `ACCOUNT_TS`, `REGION`, `LOCALE`). Remove stale account/server selectors.
   Read back the written fields before proceeding, and append only
   `-launcherlogin -uid <selected-product>` to the normal launch arguments.
6. Clear the handoff after five minutes, on startup failure/game exit, and on the
   next normal app launch in case the preceding process was killed.

The BGS client, Windows helper and OAuth developer API are not included. The
code neither reads the Mac's Battle.net credentials nor changes the original
game executable, system trust or authentication requirements. The external
browser fallback follows Waypoint's explicit browser-return approach; unlike
Waypoint's account-discovery feature, it does not open a separate BGS session
to inspect accounts before launching the game.

## Current limits and validation

- CAPTCHA, 2FA and identity-provider challenges remain under Blizzard/provider
  control. Closing or timing out the browser cancels without launching a game.
- Embedded WebKit storage is nonpersistent. Retention uses Keychain tickets,
  not persisted cookies. Callbacks, tickets and account IDs are never logged;
  the legacy launch envelope stays outside Documents and is cleared as above.
- Host tests use fake tickets and throwaway preferences domains. They cover the
  cipher vector, URL boundaries, duplicate callbacks, malformed tickets, app
  binding, expiry, single consumption and cleanup under ASan/UBSan:
  `bash tools/test_wow_browser_login.sh`.
- `tools/test_wow_launcher_ui.sh` covers the selector, remembered-session launch,
  isolated Keychain add/reload/update/delete and region isolation, explicit
  external-return import, invalid/stale callbacks and sanitized errors. It uses
  a synthetic system username because the unsigned simulator has none.
- `tools/test_touch_controls_ui.sh --self-test --saved-text-test` covers key
  hiding, stale-action rejection and preservation of its text and position.
- Do not export a real `net.battle.plist`, collect callback URLs or publish
  unredacted Connection.log when investigating an account test.

Source credits and licenses are in [NOTICE.md](../NOTICE.md).
