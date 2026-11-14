# RokuCast Bridge
Experimental Chromecast with Google TV / Android TV hardware remote bridge.

This app can remap physical key presses **only after** Android TV actually receives them:
through compatible HDMI-CEC TV forwarding or a USB infrared-to-keyboard receiver.
It does NOT pair directly with Roku Voice remotes or read infrared without hardware.

Features: remote-key diagnostic screen, custom key-code learning, opt-in Accessibility remapping
of Back, Home, playback, volume, system UI, and streaming apps.
No Internet permission. No screen content accessed.

## Build
JDK 17, Gradle 8.9, Android SDK 35:
`gradle :app:assembleDebug`
Or use the GitHub Actions APK artifact on this branch.

## Set up
1. On Roku TV, Settings > System > Control other devices (CEC) > 1-touch play.
2. On Chromecast with Google TV, enable HDMI-CEC in Settings > Display & Sound.
3. Test directional navigation while using Chromecast HDMI input. TV model support varies.
4. If no keys arrive, try an IR USB-HID receiver such as FLIRC for an **IR Roku remote** and a compatible powered hub. Configure FLIRC mapping on a computer first.
5. Install the APK on Google TV, launch it, test incoming key presses.
6. For advanced remapping, enable "RokuCast key remapper" in Accessibility settings and learn a mapping.

Some Roku TVs react to buttons locally while also forwarding signals. Protected keys (including Power and Home) may never reach ordinary applications. Voice, volume through HDMI-CEC, Roku-specific shortcut buttons, and wake behavior are not guaranteed. Not for cast-only Chromecast.
