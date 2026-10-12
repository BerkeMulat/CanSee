<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="CanSee app icon">
</p>

<h1 align="center">CanSee</h1>

<p align="center">
  <b>Keep your Mac awake, even with the lid closed, so your AI agents keep working.</b><br>
  A small menu bar app for Apple Silicon MacBooks.
</p>

<p align="center">
  <a href="https://github.com/BerkeMulat/CanSee/releases/latest">Download</a> ·
  <a href="README.tr.md">Türkçe</a>
</p>

<p align="center">
  <img src="docs/panel-idle.png" width="300" alt="The CanSee panel before a session">
  &nbsp;
  <img src="docs/panel-active.png" width="300" alt="The CanSee panel during a session">
</p>

## Why

Long agent runs (Claude Code, Codex, ChatGPT and the like) stop the moment you close the lid, because macOS puts the Mac to sleep. `caffeinate` doesn't help: it only blocks *idle* sleep, and lid-close sleep takes a different path. CanSee keeps the Mac awake for exactly as long as you choose, in minutes, hours or days, and then puts every setting it touched back the way it was.

## Features

- **Closed-lid mode.** The Mac keeps running with the lid shut, no external display needed.
- **Any duration.** One-click presets from 30 minutes to 1 day, or any number of minutes, hours or days. Extend a running session by +15 min, +1 h or +4 h.
- **Sleep always comes back.** When the time is up, when you stop or quit, on logout or restart, on `killall`, and even when the app crashes or is force-quit, because a small watchdog restores sleep at the deadline. After a power loss, CanSee fixes it on the next login.
- **Battery saver** (*Pil tasarrufu*). Turns on macOS Low Power Mode for the session (less heat, longer battery) and restores your setting afterwards.
- **No lock screen** (*Kilitlenmesin*). Keeps the display from idling off, so the screen saver and lock never start while the lid is open. See [About the lock screen](#about-the-lock-screen) for the closed lid.
- **Safety guards.** Ends the session when the battery runs low (10 % by default, on battery) or the Mac gets critically hot, and leaves a notification.
- **An eye that watches.** The menu bar eye sleeps while idle, wakes up when a session starts, and now and then blinks or glances around. It stops completely while the display is off.
- **Menu bar only.** No Dock icon and no ⌘-Tab entry. Right-click the eye for quick actions.
- **Light.** About 12 MB of memory and 0 % CPU when idle. Everything is event-driven; nothing polls.

<p align="center">
  <img src="docs/eye-states.png" width="720" alt="The menu bar eye: closed, blinking, open, looking around">
</p>

The interface is in Turkish.

## Install

1. Download **CanSee-2.1.dmg** from [Releases](https://github.com/BerkeMulat/CanSee/releases/latest) and drag CanSee into Applications.
2. The build is signed but not notarized, so macOS won't open it the first time. Open **System Settings › Privacy & Security** and click **Open Anyway**, or run:
   ```sh
   xattr -dr com.apple.quarantine /Applications/CanSee.app
   ```
3. An eye appears in the menu bar. On its first launch from Applications, CanSee adds itself to Login Items; you can turn that off in its settings.
4. The first closed-lid session asks once for an administrator password (see [Permissions](#permissions)).

## Use

Click the eye, pick a duration and close the lid. The eye stays open while the Mac is kept awake and closes when the session ends. Don't put the Mac in a bag while it runs with the lid closed; it needs air.

## About the lock screen

Closing the lid switches the display off in hardware. macOS then starts its "Require password after screen saver begins or display is turned off" timer, and according to Apple's `IOPMLib.h`, no app can keep the display on through a closed lid. So:

- **Lid open** (or closed with an external display): with *No lock screen* on, the display never idles off and the Mac never locks.
- **Lid closed**: the screen locks after the delay set in **System Settings › Lock Screen**. To prevent that, set "Require password…" to **Never**. CanSee shows the current delay and links straight to the setting. Keep in mind that anyone who opens the lid can then use the Mac.

## Permissions

Blocking lid-close sleep and switching Low Power Mode both need root. On first use, CanSee installs one narrowly scoped sudoers rule, checked with `visudo` first, at `/private/etc/sudoers.d/cansee-<uid>`. It allows only these commands, without a password:

```
/usr/bin/pmset -a disablesleep 0|1
/usr/bin/pmset -b lowpowermode 0|1
/usr/bin/pmset -c lowpowermode 0|1
```

Nothing else runs as root. You can remove the rule at any time under **Ayarlar › Yönetici izni › Kaldır** (Settings › Administrator permission › Remove). If you cancel the password prompt, CanSee still keeps the Mac awake while the lid is open.

## How it works

| Part | What it does |
| --- | --- |
| `Core/AwakeManager` | Session state, with one wall-clock timer per session so nothing wakes up before the deadline |
| `Core/SleepControl` | The `pmset` calls, the sudoers rule, and IORegistry reads (`SleepDisabled`, lid state) |
| `Core/SessionStore` | Saves the session to disk; a detached `zsh` watchdog (builtins only, at most one wakeup a minute) undoes every change if the app dies |
| `Core/PowerMonitor` | Battery, thermal and Low Power Mode changes from system notifications, subscribed only while needed |
| `Eye/` | One eye drawing shared by the menu bar icon, the panel and the app icon; frames are drawn only while an animation runs |
| `UI/` | The SwiftUI panel, built when first opened and released after it closes |

## Build from source

You need macOS 27 and Xcode 27.

1. Open `CanSee.xcodeproj`.
2. Under **Signing & Capabilities**, pick your own team.
3. Run. Leave **App Sandbox** off: the app has to call `sudo pmset`.

## Requirements

macOS 27 or later on Apple Silicon. Closed-lid mode needs a MacBook; on a desktop Mac, CanSee just prevents idle sleep.

## License

[MIT](LICENSE) © 2026 Berke Mulat
