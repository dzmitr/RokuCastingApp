# ScreenCastTV Roku Receiver

Minimal native Roku receiver for ScreenCastTV built with BrightScript and SceneGraph. The app cold-launches into a lightweight idle scene, accepts launch params from deep links or DIAL-style launches, fetches a session JSON payload when `src` is present, and plays the resolved media through Roku's built-in `Video` node.

## Project layout

```text
manifest
source/main.brs
components/MainScene.xml
components/MainScene.brs
components/SessionTask.xml
components/SessionTask.brs
components/ControlPollTask.xml
components/ControlPollTask.brs
```

## Supported launch params

- `contentID`
- `mediaType`
- `src` - URL to a session JSON document
- `title` - optional display title override
- `kind` - optional hint such as `live`

If `src` is missing and `contentID=review-demo`, the app plays a public demo HLS stream for certification and deep-link testing.

If no valid playback launch params are provided, the app stays on the idle screen and shows:

`Open ScreenCastTV on iPhone and connect to this Roku.`

## Expected session JSON

The receiver is intentionally flexible about field names, but this shape is recommended:

```json
{
  "title": "Kitchen TV Demo",
  "description": "Local HLS session",
  "url": "http://192.168.1.50:8080/live/session.m3u8",
  "streamFormat": "hls",
  "live": true,
  "controlUrl": "http://192.168.1.50:8080/control/session-123"
}
```

Accepted playback URL aliases include `url`, `src`, `streamUrl`, `playbackUrl`, and `mediaUrl`.

Accepted control aliases currently include `controlUrl` and `control_url`.

The control endpoint may return either plain text or JSON:

```json
{ "command": "reload" }
```

```text
stop
```

Supported control commands:

- `noop`
- `reload`
- `stop`

## Sideload steps

1. Enable Developer Mode on the Roku device and reboot if prompted.
2. Find the Roku IP address from `Settings > Network > About`.
3. Zip the contents of this folder, making sure `manifest` is at the root of the zip.
4. In a browser, open `http://ROKU_IP`.
5. Sign in with the Roku developer credentials you set during Developer Mode setup.
6. Upload the zip package and click **Install**.

## Debugging

- Open the device web installer page at [http://ROKU_IP](http://ROKU_IP) for sideloading.
- Use the BrightScript debugger on port `8085`, for example: `telnet ROKU_IP 8085`
- Watch console logs for:
  - app launch
  - parsed params
  - session fetch success or failure
  - playback start
  - buffering
  - playback error
  - stop or back

## Example launch URLs

Replace `ROKU_IP` with your device IP.

Review demo:

```text
http://ROKU_IP:8060/launch/dev?contentID=review-demo&mediaType=video&title=Review%20Demo
```

Remote session fetch:

```text
http://ROKU_IP:8060/launch/dev?contentID=session-42&mediaType=video&src=http%3A%2F%2F192.168.1.50%3A8080%2Fsession.json&title=Kitchen%20TV
```

Live hint via `kind`:

```text
http://ROKU_IP:8060/launch/dev?contentID=live-abc&mediaType=video&kind=live&src=http%3A%2F%2F192.168.1.50%3A8080%2Flive.json
```

Photo session:

```text
http://ROKU_IP:8060/launch/dev?contentID=photo-1&mediaType=image&kind=photo&src=http%3A%2F%2F192.168.1.50%3A8080%2Fphoto.json&title=Vacation
```

## Manual QA checklist

- Launch the app without params and verify the idle scene renders immediately.
- Launch with `contentID=review-demo` and verify demo HLS playback starts.
- Launch with a valid `src` session JSON and verify the loading state transitions to playing.
- Confirm the loading spinner appears while the session JSON is being fetched.
- Force buffering or throttle the stream and verify the buffering state and log output.
- Return `{ "command": "reload" }` from `controlUrl` and verify the session reloads.
- Return `{ "command": "stop" }` or plain `stop` from `controlUrl` and verify playback stops and the app returns to idle.
- Press Back during playback and verify playback stops and the app returns to idle.
- Launch with an invalid `src` and verify a human-readable error plus retry instructions appear.
- Launch with `mediaType=image` or `kind=photo` and verify the receiver loads and displays the photo full-screen.
