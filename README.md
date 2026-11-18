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

Clips are saved to `~/Movies/Ember` by default (or `~/Movies/Flint` if you used the app before it was renamed). Change it, the clip length and quality in Settings.

## Setting up share links

1. In the Cloudflare dashboard enable R2 and create a bucket (this repo's `wrangler.toml` expects one called `flint`)
2. Create a Worker and paste in `worker/src/index.js`, or run `npx wrangler deploy` from the `worker` folder
3. In the Worker's settings, bind the bucket as `CLIPS`, add a secret called `UPLOAD_TOKEN` (any long random string) and add a route such as `your-domain/clip*` (a route leaves the rest of the site alone)
4. In Ember Settings > Sharing, paste the same upload token. Set Upload URL to `https://your-domain/clip` if you aren't using the default

Shared clips are kept forever, so links never break. The first 10 GB is free (roughly 440 thirty-second clips with shrinking on); after that R2 charges $0.015 per GB a month, and viewing is always free.

## How the replay buffer works

ScreenCaptureKit streams frames from the main display (Ember itself is excluded). `ReplayBuffer` encodes them into five-second MP4 segments in a temporary folder and deletes segments older than the clip length. Saving a clip closes the open segment, joins the newest segments with `AVMutableComposition` and exports them without re-encoding, trimmed to the clip length.

Uploads go through the Worker straight into R2. The free plan caps a request at 100 MB, so the app lowers the bitrate of long recordings to keep every upload under 95 MB.
