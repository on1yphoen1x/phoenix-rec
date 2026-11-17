# Ember

Game clipping for macOS. Ember has a main window for browsing your clips and screenshots, plus a menu bar icon, and keeps the last 15 to 120 seconds of your screen and game audio in a rolling buffer. Press Option-Shift-C and that stretch is saved as an MP4, copied to the clipboard and shown in a small panel with Copy and Copy Link buttons.

- 1080p, 1440p or 4K at 60 fps, H.264 so clips play everywhere, including Discord embeds
- Game audio always, microphone optional (saved as a second audio track)
- Screenshots of an area, window or full screen (Option-Shift-4 for area)
- Manual start/stop recording of a chosen screen, window or app
- Copy puts the whole file on the clipboard, so it pastes straight into Messages, Discord, Slack or Finder
- Copy Link uploads to your own Cloudflare R2 bucket and copies a link on your own domain that never expires
- Shared copies are shrunk to 1080p at 6 Mbps with game and mic audio mixed, about half the size; saved clips stay full quality (toggle in Settings)
- No ads, no analytics, nothing leaves the Mac unless you press Copy Link

Requires macOS 15 Sequoia or later.

## Building the app

1. Install Xcode from the App Store and XcodeGen: `brew install xcodegen`
2. In this folder run `xcodegen` to generate `PhoenixRecording.xcodeproj`, then `open PhoenixRecording.xcodeproj`
3. Select the PhoenixRecording target, Signing & Capabilities, and pick your Personal Team
4. Press Run. macOS will ask for Screen Recording permission; allow it in System Settings, then quit and reopen Ember

Clips are saved to `~/Movies/Ember` by default. Change it, the clip length and quality in Settings.

## Setting up share links

1. In the Cloudflare dashboard open R2 and enable it (it asks for a card; the first 10 GB a month is free)
2. From the `worker` folder:

```sh
npm install
npx wrangler r2 bucket create phoenix-clips
```

3. In the dashboard go to R2, Manage API tokens, and create a token with Object Read & Write on `phoenix-clips`. Note the access key ID, secret and your account ID
4. Set the secrets. For the upload token, generate something long with `openssl rand -hex 32`:

```sh
npx wrangler secret put UPLOAD_TOKEN
npx wrangler secret put R2_ACCOUNT_ID
npx wrangler secret put R2_ACCESS_KEY_ID
npx wrangler secret put R2_SECRET_ACCESS_KEY
npx wrangler deploy
```

5. In Ember Settings, set Upload URL to your share address, for example `https://share.example.com` and paste the same upload token

Shared clips are kept forever, so links never break. The first 10 GB is free (roughly 440 thirty-second clips with shrinking on); after that R2 charges $0.015 per GB a month, and viewing is always free.

## How the replay buffer works

ScreenCaptureKit streams frames from the main display (Ember itself is excluded). `ReplayBuffer` encodes them into five-second MP4 segments in a temporary folder and deletes segments older than the clip length. Saving a clip closes the open segment, joins the newest segments with `AVMutableComposition` and exports them without re-encoding, trimmed to the clip length.

Uploads skip the Worker: the app asks the Worker for a signed R2 URL and sends the file directly to R2, which avoids the 100 MB request limit on Cloudflare's free plan.
