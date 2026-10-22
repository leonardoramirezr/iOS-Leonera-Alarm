# Vigilia

An iPhone alarm (iOS 26 or later) built with **AlarmKit**, the alarm framework Apple opened to third-party apps in iOS 26:

- ⏰ **The same time every day, or a different time for each day** (for example, 6:30 on weekdays and 9:00 on weekends).
- 🔊 **A different sound every day** so you don't get used to it: there are 90 sounds synthesized from scratch, all different from one another, and none repeats until all of them have been used (about three months).
- 🚫 **No snooze.** The alarm has no snooze button, and if you stop it from the lock screen, with the hardware buttons, or by closing the app, **it rings again**.
- 🧠 **To really turn it off you have to do mental math for 15 seconds to 10 minutes** (your choice). Time only moves forward while you answer correctly. You also choose the difficulty: operations with 1-, 2-, or 3-digit numbers.
- 🌙 **Already awake?** Starting 3 hours before it rings you can turn off that alarm by doing the same challenge from the app. Only that one occurrence is skipped.
- 📈 **Wake-up statistics:** what time the alarm rang, what time you turned it off, and how long it took you, with averages, percentiles, and charts of how they have changed, by weekday or for the whole week, counting all time, the last year, month, or week.

It can be built in two ways: on **GitHub Actions** (no Mac needed), which signs the app Ad Hoc and publishes it on a page you install it from with Safari on the iPhone, or with a **local script** without an Xcode project (just `swiftc`, a `Makefile`, and `build.sh`). The Xcode project that GitHub Actions uses is not in the repository: it is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen) from [`project.yml`](project.yml).

> The app's interface is in Spanish. Button and setting names below are quoted exactly as they appear in the app, followed by an English translation.

---

## At a glance

| Requirement | Possible? | Details |
|---|---|---|
| Use AlarmKit | ✅ Yes | iOS schedules the alarms through `AlarmManager`: they ring with the iPhone on silent, in a Focus, with the app closed, and after a restart. |
| A different sound every day | ✅ Yes | 90 custom sounds in a shuffled rotation. The same sound never plays two days in a row. |
| No snooze, not even by closing the app | ✅ Yes, with a caveat | iOS **always** shows a control to stop the alarm and the hardware buttons stop it too; no app can remove that. Vigilia handles it by making the alarm **ring again** (every minute and then further apart, for an hour) until you complete the challenge. Those repeats are already scheduled in iOS, so closing or killing the app does not stop them. |
| Ring at full volume even if the volume is low | ⚠️ Partial | **During the challenge, yes:** if you stop answering correctly, the alarm rings again inside the app and raises the iPhone volume to the maximum (on its speaker). **With the iPhone locked, no:** AlarmKit rings at the iOS ringtone and alerts volume and no app can raise it; you have to leave it at the maximum and turn off "Change with Buttons". See [Volume](#volume). |
| Turn it off with a 1-minute mental exercise | ✅ Yes | 1 minute of mental math (or 15 s to 10 min, if you choose); the clock pauses if you stop answering and each mistake subtracts 5 s. |
| Build without Xcode | ⚠️ Partial | **GitHub Actions: yes, with no Mac and no Xcode on your side.** **Locally:** you need a Mac with Xcode *installed* (you never open it and there is no `.xcodeproj`). Without Xcode installed it is not possible: the iOS SDK only ships inside Xcode. |
| Install it from the iPhone | ✅ Yes, with the developer account | Every push signs the app **Ad Hoc** and publishes it on GitHub Pages: it installs from Safari on the iPhones registered in your Apple Developer account. See [Install from Safari](#install-from-safari-ad-hoc). |
| Install it without the developer subscription | ⚠️ Yes, with limits | With your **free** Apple ID and Sideloadly, AltStore, or SideStore. The signature lasts **7 days** (it has to be renewed), at most 3 apps installed this way, and you need a computer (Windows or Mac) at least the first time. |

---

## How it works

### The alarms
- For each chosen weekday a weekly alarm is scheduled in AlarmKit, **at that day's time** and with **the sound assigned to that date**. With «Misma hora todos los días» ("Same time every day") on, every day uses a single time; turning it off lets you choose the time of each day separately (and if you turn it back on, the per-day times are kept for next time). Every time you open the app (and you open it daily, because that's where the challenge happens) the alarms are readjusted so the sounds keep rotating. If you didn't open the app for a week, 7 different sounds would still play.
- Behind each alarm there is a **chain of repeats** already scheduled in iOS: at 1, 2, 3, 4, 5, 6, 7, 8, 10, 12, 15, 20, 30, 45, and 60 minutes. It is only cancelled when you complete the challenge.
- If you stop the alarm from the lock screen, Vigilia also schedules another repeat in 1 minute (if iOS runs its "stop" action; sometimes it doesn't, which is why the chain exists).
- The alert has a single extra button, **«Resolver reto»** ("Solve challenge"), which opens the app directly in the challenge.

### The sounds
There are 90 and all of them are synthesized from scratch with [`scripts/generate_sounds.py`](scripts/generate_sounds.py), with no recordings or third-party audio. Each one has its own timbre, rhythm, and pitch, and none of them imitates an emergency siren or alarm: waking up to something that sounds like an emergency is needlessly scary.

| Type | Sounds |
|---|---|
| Beeps and signals | Classic beeps, High beeps, Digital clock, Beep storm, Morse: WAKE UP, Teletype, Sonar, Accelerating pulses, Lasers, Chatty robot, Reversing beeper, Walkie-talkie, Modem, Geiger counter |
| Horns and whistles | Foghorn, Train horn, Referee whistle |
| Bells, chimes, and clocks | Glass bells, Bell tower, Bell alarm clock, Old telephone, Music box, Railroad crossing, Doorbell, Cuckoo clock |
| Instruments | Fanfare, Reveille, Muted trumpet, Nervous marimba, Steel drum, Handpan, Vibraphone, Organ, Barrel organ, Piano, Harpsichord, Minor arpeggio, Endless staircase, Strummed guitar, Electric guitar, Banjo, Harp, Koto, Kalimba, Violin, Bagpipes, Kazoo, Theremin, Didgeridoo, Choir, Cheerful whistling |
| Styles and rhythms | 8-bit video game, Cumbia, Mariachi, Trance, Acid bass, Dembow, Batucada, Taiko, Cowbell, Flamenco clapping, Military drum roll, Conch and teponaztli, Drums and gong, Gamelan, Norteño polka, Cuban son, DJ scratch |
| Machines and street | Steam locomotive, Sweet potato cart, Knife sharpener, Helicopter, Car race, Slot machine, Typewriter |
| Animals and effects | Electric birds, Crickets, Rooster, Woodpecker, Frog chorus, Hungry cat, Mosquito, Cave drips, Rubber duck, Springs, Bouncing ball, Ping-pong, Bubbles, Endless rise, System failure |

The names above are translated; in the app they appear in Spanish.

To listen to them without building the app: `make sounds` generates them as WAV files in `build/sounds/` (it only needs Python 3).

### The challenge
- Random operations that get harder as the challenge goes on: additions, subtractions, multiplications, three-number sums, sequences, and combinations.
- **Difficulty** (in the alarm settings), based on how many digits the numbers have:

  | Difficulty | Examples |
  |---|---|
  | 1 digit | `7 + 8`, `6 × 9`, `8 × 7 − 4 × 6` |
  | 2 digits (the default) | `47 + 38`, `6 × 23`, `7 × 13 − 25` |
  | 3 digits | `347 + 285`, `6 × 135`, `7 × 124 − 358` |

- **Duration** (also in the alarm settings): you have to accumulate **15 seconds to 10 minutes** (1 minute is the default). The duration only changes how much time you have to accumulate: the rules are the same and the operations keep getting harder throughout the whole challenge.
- After each correct answer the clock runs for 15 s (25 s with 3 digits, which take longer); if you don't answer correctly again within that time it pauses. It can't be completed by waiting.
- A mistake subtracts 5 s; skipping an operation does too.
- If you go that same amount of time without a correct answer (15 s, or 25 s with 3 digits), **the alarm rings again inside the app**, at full volume, until your next correct answer (see [Volume](#volume)). The challenge to unlock the settings and the one to turn the alarm off early don't ring.
- If you leave the app the challenge starts over, and if you close it, the alarm rings again in a little over a minute.

### Volume
There are two different volumes and the app can only control one:

| When | Which volume it uses | Can the app raise it? |
|---|---|---|
| The AlarmKit alarm (lock screen, Dynamic Island, every repeat) | iOS **Ringtone and Alerts** | ❌ No. Apple provides no API for that ([confirmed by an Apple engineer](https://developer.apple.com/forums/thread/821315)). |
| Inside the app, when the alarm rings again during the challenge | Music and video volume | ✅ Yes: it raises it to the maximum |

**Why it sometimes only vibrates:** with **"Change with Buttons"** on (Settings › Sounds & Haptics), the volume buttons change the ringtone and alerts volume when nothing is playing, so lowering the music volume also lowers the alarm's. At its lowest, the alarm vibrates and shows on screen, but can barely be heard. To make it always ring loudly, in **Settings › Sounds & Haptics**:
1. Turn off **"Change with Buttons"**: the buttons then only change the music and video volume.
2. Raise the **Ringtone and Alerts** volume to the maximum.
3. On **iOS 27**, the **"Alarms and Timers"** section lets alarms have their own volume, independent of the ringtone. If you turn it on, raise it to the maximum too. There is no documentation on whether AlarmKit respects it, so check it with the test.
4. Tap **«Probar»** ("Test"), lock the iPhone, and check that it sounds loud.

The app explains the same thing in **«Volumen de la alarma»** ("Alarm volume"), on the main screen.

**Inside the app:** during the alarm challenge, if you go 15 s without a correct answer (25 s with 3 digits), Vigilia plays the day's sound again and **raises the iPhone volume to the maximum**; if you lower it with the buttons, it raises it again. As soon as you answer correctly it stops playing and restores the volume to where it was; if you again go without a correct answer, it plays again. It ignores silent mode. Details:
- It only raises the volume on the **iPhone speaker**. With headphones or a Bluetooth speaker connected it plays through them, at whatever volume you have, so it doesn't hurt your ears.
- iOS has no API to change the volume: Vigilia moves the slider of a hidden `MPVolumeView` ([`src/App/SystemVolume.swift`](src/App/SystemVolume.swift)), the trick alarm apps have used for years. If a version of iOS broke it, the alarm would still ring inside the app, but at whatever volume you have.
- If an AlarmKit alarm or a call interrupts the sound, it restarts on its own.

### Turning it off before it rings
If you're already awake, starting **3 hours before** the alarm time, **«Próxima alarma»** ("Next alarm") shows the button **«Desactivarla con el reto de 1 minuto»** ("Turn it off with the 1-minute challenge") (or however many minutes you chose). It is the same challenge you'd do when it rings (same difficulty, same duration, and same rules, although here you can cancel it) and, when you complete it:
- That alarm no longer rings or rings again: its repeats are cancelled too.
- **It is only turned off that once.** The other days' alarms stay the same and that same weekday rings again the following week (in the meantime the app shows the alarm as «Desactivada», "Turned off").
- It doesn't count in the statistics, because it didn't ring.
- It doesn't unlock the settings. If you then change that day's time, the new time does ring.

It can't be used while an alarm (or the test) is ringing or has its challenge pending, nor in the last 20 seconds before it rings.

Under the hood: since a weekly AlarmKit alarm can't skip a week, that day's alarm is replaced by a one-time alarm for the following week; once the turned-off time has passed, the app makes it weekly again.

### Changing the next alarm
In the **«Alarma»** ("Alarm") section, **«Cambiar siguiente alarma»** ("Change next alarm") sets a different time just for the next alarm, whether it's today, tomorrow, or several days away, without touching the other days:
- If the next one rings on Monday at 8:00, you can change it to 9:00: that Monday it only rings at 9:00 and the 8:00 one doesn't ring.
- When turned on it starts with that alarm's usual time; the following days ring as usual.
- It works like any alarm: it can't be snoozed, it rings again until you complete the challenge, and it can be turned off early.
- It's part of the settings, so it's also locked if changes are locked.

Under the hood it's a one-time AlarmKit alarm; that day's weekly alarm is replaced by a one-time alarm for the following week, just like when turning it off early.

### Locked settings
The **«Bloquear cambios»** ("Lock changes") toggle (on by default) decides whether the settings get locked. When off, they never lock and you can change or turn off the alarm without the challenge. To turn it off while the settings are already locked you have to unlock them first; when you turn it back on you have 5 minutes before they lock.

With locking on, while the alarm is on, **changing the time, the days, the challenge difficulty or duration, or turning it off also requires the challenge** (afterwards they stay unlocked for 5 minutes). The unlock challenge uses the difficulty you already had, but it always lasts 1 minute, whatever duration you chose for the alarm. That way you can't turn it off half-asleep from the settings. Turning it on is free and, when you do, you have 5 minutes to adjust the time, days, difficulty, and duration before it locks.

**While the alarm is ringing** (or has already rung and the challenge is still pending, including the test), any change to the time, days, difficulty, challenge duration, or the toggle **is ignored**, even if the settings are unlocked. That way changing the time can't silence it or stop it from coming back: only the challenge turns it off.

### Statistics
In **«Estadísticas»** ("Statistics", on the main screen) you choose three things, independent of one another, and any combination works:

| Option | Values |
|---|---|
| Statistic | **Summary** (average and percentiles) or **charts** of how they have changed |
| By | **Weekday** (one average or one line per day) or **whole week** |
| Counting | **All time**, **1 year**, **1 month**, or **1 week** (back from today) |

- Each wake-up has three data points:
  - **Time it rang:** the first time the alarm rang, not counting when it rings again.
  - **Time you turned it off:** when you completed the challenge.
  - **Time to turn it off:** from when it first rang until you completed the challenge.
- Tests don't count, nor do alarms turned off before ringing.
- The **summary** shows how many wake-ups there are and, for each data point, the average and three percentiles, each with its explanation on screen:
  - **10th percentile:** 1 in 10 days was at that time or earlier (or you took that long or less).
  - **50th percentile (median):** half of the days.
  - **90th percentile:** 9 in 10 days.
- By weekday, each day shows the three averages; tap it to see its percentiles.
- Times handle midnight correctly: 23:50 and 0:10 average to 0:00, not noon.
- **Charts:** one per data point. They show each wake-up for short periods and weekly or monthly averages for long periods. Hold your finger on one to see each value; «Ver datos» ("See data") shows the table with the three data points.
- About 10 years of wake-ups are kept (previously only the last 30 were kept).

### «Probar» ("Test") button
Schedules a test alarm in 1 minute that behaves just like the real one (repeats included). Lock the iPhone to see it as it will look in the morning.

### What iOS doesn't allow (so it doesn't surprise you)
- **The iOS "Stop" control can't be removed** and the hardware buttons stop the alarm. That's why the strategy is to make it come back, not to make it impossible to touch.
- **The AlarmKit alarm volume is set by iOS** (Ringtone and Alerts), not by the app. If it's low, the alarm with the iPhone locked rings quietly or only vibrates. See [Volume](#volume).
- **Uninstalling the app or removing its Alarms permission** (Settings › Vigilia) does turn it off. No app can prevent that.
- AlarmKit custom sounds must last **less than 30 s** and, according to reports from other developers, may play only once instead of repeating. That's why each sound lasts 28 s and the alarm rings again every minute.
- Apple states that apps **hidden or locked with Face ID** can't use AlarmKit: don't hide or lock Vigilia.
- If the **signature expires** (7 days with a free Apple ID; up to a year with the GitHub Actions Ad Hoc signature), the app doesn't open: the alarms still ring, but you couldn't do the challenge. The app shows you when the signature expires and warns you 2 days before.
- Repeats last one hour (two if you keep stopping it) so that, if you leave your phone at home, it doesn't ring all day.

---

## Building

### Option 1: GitHub Actions (no Mac needed)

The workflow [`.github/workflows/build.yml`](.github/workflows/build.yml) runs on a GitHub Mac (`macos-15`, with the most recent Xcode 26 it has installed) on every push to any branch except `gh-pages`, and it can also be started manually (*Run workflow*). No build cancels another: `main` builds run one after another (so each one gets its version number) and builds for other branches run in parallel.

1. Picks the label (see below) and the identifiers:
   - **Bundle ID:** always `com.leonardoramirezr.leoneraalarm` (fixed in `project.yml`, `build.sh`, and the workflow; it doesn't depend on the repository or on variables).
   - **Extensions** (if any are ever added): `<bundle>.<suffix>`, for example `com.leonardoramirezr.leoneraalarm.widget`.
2. Runs the logic tests (`make test`).
3. Generates the sounds and the Xcode project (`make project`, with XcodeGen).
4. Checks the App Store Connect key and that at least one iOS device is registered ([`scripts/asc.py`](scripts/asc.py)).
5. Archives with **automatic signing** (`-allowProvisioningUpdates` and the API key): Xcode creates or updates the App ID and the profiles.
6. Exports the **Ad Hoc** IPA (`method=release-testing`): it uses the distribution certificate managed in the cloud by Apple and an Ad Hoc profile with all registered devices. Then it checks that each bundle has a valid Ad Hoc profile and a valid signature, and warns if any registered iPhone is not in the profile ([`scripts/verify-ipa.py`](scripts/verify-ipa.py)).
7. Publishes it on **GitHub Pages** ([`scripts/publish-pages.sh`](scripts/publish-pages.sh)) and as a **Release**, and uploads it as an artifact.
8. When it finishes (even if something failed), it **revokes the temporary development certificate** that `xcodebuild` creates on each run: only new "Apple Development" certificates in the runner's keychain, never the ones you already had.

Labels:
- **`main` → `0.x.0`** (`0.1.0`, `0.2.0`, `0.3.0`…): each push to `main` bumps the middle number by 1. It's the stable version, marked as *Latest*.
- **Any other branch → `build-<N>-<commit>`** (for example `build-2-c1e51fa`): `<N>` is the workflow run number and `<commit>` the first 7 characters of the hash. It's published as a pre-release, never as *Latest*.

#### Secrets (signing)

In the **repository's** *Settings › Secrets and variables › Actions › Secrets* (not an organization's: this repository is personal):

| Secret | Contents |
|---|---|
| `ASC_KEY_ID` | Key ID of the App Store Connect API key |
| `ASC_ISSUER_ID` | Issuer ID |
| `ASC_KEY_P8` | Full contents of the `AuthKey_XXXX.p8` file |
| `APPLE_TEAM_ID` | Team ID of the Apple Developer account |

The key must be a **Team Key with the Admin role** (App Store Connect › Users and Access › Integrations): the cloud-managed distribution certificate needs it. iPhone UDIDs are registered in [Apple Developer › Devices](https://developer.apple.com/account/resources/devices/list); after registering a new one, the next build already includes it.

- **With all four secrets:** Ad Hoc signed IPA, published on GitHub Pages and in Releases.
- **With none:** **unsigned** IPA (as before, for Sideloadly, AltStore, or SideStore), only in Releases and Artifacts.
- **With only some:** the build fails and says which ones are missing.

#### One-time manual setup: GitHub Pages

*Settings › Pages › Build and deployment*: **Source: Deploy from a branch**, branch **`gh-pages`**, folder **`/ (root)`** › *Save*. The `gh-pages` branch is created by the first signed build; if it doesn't show up in the list yet, wait for it to finish and come back to this screen.

#### Install page

`https://leonardoramirezr.github.io/vigilia-ios/` (or the domain configured in Pages):
- The home page lists all builds and has a button to install the **latest stable version**.
- Each build has its own folder (`/0.3.0/`, `/build-41-c1e51fa/`) with the IPA, `manifest.plist`, `build.json`, and its own page with the install button (`itms-services://`).
- `gh-pages` is rewritten on every publish as **a single commit** (old IPAs don't pile up in the history). **All `main` versions** and the **last 50 builds** of other branches are kept. Each IPA weighs about 17 MB and GitHub Pages allows sites up to 1 GB, so with many `main` versions it's worth lowering `KEEP_BRANCH_BUILDS` in the workflow.

Other ways to download the IPA: each build's Release (the most recent stable one is at `https://github.com/leonardoramirezr/vigilia-ios/releases/latest/download/Vigilia.ipa`) or *Actions* › the run › *Artifacts* › `Vigilia-ipa`.

The repository is public, so Mac minutes on GitHub Actions cost nothing.

### Option 2: local script (Mac)

Requirements:
- A Mac with **Xcode 26 or later installed** (free on the App Store). You don't need to open it, create a project, or have a developer account.
- The command line pointing to Xcode: `sudo xcode-select -s /Applications/Xcode.app`

```sh
make test     # logic tests (sound rotation, challenge, schedules)
make build    # generates build/Vigilia.app and build/Vigilia.ipa
make clean
```

`build.sh` does the same as Xcode, step by step and in plain sight:
1. Compiles all of `src/` with `swiftc` for `arm64-apple-ios26.0`.
2. Extracts the App Intents metadata (`appintentsmetadataprocessor`), which iOS needs for the alarm buttons.
3. Assembles the `Info.plist` and compiles the icon with `actool`.
4. Generates the sounds (`scripts/generate_sounds.py`, only the first time) and converts them to CAF with `afconvert`.
5. Packages `Payload/Vigilia.app` into `build/Vigilia.ipa`.

Optional variables: `BUNDLE_ID=com.yourname.vigilia make build`, `VERSION=1.1`, `BUILD_NUMBER=2`, `BUILD_NAME=my-test` (the build name shown at the end of the settings, `local` by default).

To open or build it with Xcode: `brew install xcodegen` and `make project`, which generates `Vigilia.xcodeproj` (it isn't saved in the repository).

### What about without Xcode installed?

It's not possible, and it's not because of the template: the iOS SDK (SwiftUI for iPhone, AlarmKit, etc.), `actool`, and the App Intents processor **are only distributed inside Xcode.app**. The *Command Line Tools* only include the macOS SDK, which is why the original template worked without Xcode and an iPhone app doesn't. The way out is exactly Option 1: GitHub's Macs already have Xcode, you just push.

---

## Install from Safari (Ad Hoc)

For the iPhones registered in the Apple Developer account (see [Secrets](#secrets-signing)):

1. On the iPhone, open `https://leonardoramirezr.github.io/vigilia-ios/` in **Safari**.
2. Tap **«Instalar la última versión estable»** ("Install the latest stable version") (or the build you want) and confirm. The app appears on the home screen.
3. The first time: Settings › Privacy & Security › **Developer Mode** › turn on and restart (iOS requires it for Ad Hoc apps). You don't need to "trust" any profile.
4. Continue with [First launch on the iPhone](#first-launch-on-the-iphone) from step 3.

To update, install the new build on top: alarms and statistics are kept. If Safari says it can't be installed, it's almost always because the iPhone wasn't registered when that build was compiled: register it and run the workflow again.

## Installing it on your iPhone without paying for the subscription

With a **free Apple ID** you can sign apps for your own devices. The tools below sign the IPA for you; you don't need Xcode. None of these tools are made by Apple.

**Free account limits:**
- The signature **lasts 7 days**. After that the app doesn't open until you renew it. Renewing doesn't erase your data: **don't uninstall the app**, just sign it again or refresh it.
- At most **3 apps** signed this way at a time (AltStore and SideStore take one of those slots).
- At most 10 new App IDs per week.
- You need a computer with **Windows or macOS** at least for the first installation.

**iPhone requirements:** iOS 26 or later and a passcode turned on.

### Option A: Sideloadly (the simplest)

1. Install [Sideloadly](https://sideloadly.io) on Windows or Mac. On Windows also install **iTunes and iCloud downloaded from Apple's website** (not the Microsoft Store versions).
2. Download `Vigilia.ipa` (see [Building](#building)).
3. Connect the iPhone with a cable, unlock it, and tap **Trust This Computer**.
4. Drag `Vigilia.ipa` into Sideloadly, enter your Apple ID, and press **Start**. It will ask for your password and verification code. If you want, create a new Apple ID just for this.
5. Continue with [First launch on the iPhone](#first-launch-on-the-iphone).
6. **Every 7 days** repeat step 4 (without deleting the app). If your version of Sideloadly offers *automatic refresh*, turn it on: it renews the signature only while the computer is on and the iPhone is reachable over Wi-Fi or cable (turn on Wi-Fi sync in iTunes or Finder).

### Option B: AltStore Classic

1. Install **AltServer** from [altstore.io](https://altstore.io) on your Windows or Mac and, with it, install **AltStore** on the iPhone using your Apple ID.
2. Transfer `Vigilia.ipa` to the iPhone (AirDrop, the Files app, or downloading it from Releases in Safari).
3. In AltStore: **My Apps › +** and choose the IPA.
4. AltStore renews the signature automatically when the iPhone and the computer running AltServer are on the same Wi-Fi network.

### Option C: SideStore (renew without a computer)

[SideStore](https://docs.sidestore.io) is a variant of AltStore that, after an initial setup with a computer, **renews apps from the iPhone itself** using a local VPN (LocalDevVPN, on the App Store). It's the most convenient option day to day but the most laborious to install; follow the [official guide](https://docs.sidestore.io/docs/installation/prerequisites). Keep in mind that updating iOS may ask you to regenerate the pairing file with the computer.

### First launch on the iPhone

1. **Developer Mode:** Settings › Privacy & Security › **Developer Mode** › turn on and restart. (The option appears after the first attempt to install an app this way.)
2. **Trust your Apple ID:** Settings › General › **VPN & Device Management** › your Apple ID › Trust.
3. Open **Vigilia** and tap **«Permitir alarmas»** ("Allow alarms").
4. Turn on the alarm, choose the days and the time (or turn off «Misma hora todos los días», "Same time every day", to set a different time for each day).
5. Tap **«Probar: sonará en 1 minuto»** ("Test: it will ring in 1 minute"), lock the iPhone, and check that it rings, that it can't be snoozed, and that it only turns off with the challenge.

---

## Customizing

| What | Where |
|---|---|
| Days and time (the same or one per day) | In the app |
| Bundle ID | Fixed: `com.leonardoramirezr.leoneraalarm` (don't change it) |
| Display name | `CFBundleDisplayName` in [`Info.plist`](Info.plist) (`Leonera Alarm`) |
| Version (local) | `VERSION=… make build` |
| Repeats, session length, unlocking, how early it can be turned off | `AlarmRules` in [`src/Core/AlarmMath.swift`](src/Core/AlarmMath.swift) |
| Penalties, time per answer, possible challenge durations | `ChallengeRules` and `ChallengeDuration` in [`src/Core/MathChallenge.swift`](src/Core/MathChallenge.swift) |
| Operation types for each difficulty | `ProblemFactory` in [`src/Core/MathChallenge.swift`](src/Core/MathChallenge.swift) |
| Statistics | [`src/Core/WakeStatistics.swift`](src/Core/WakeStatistics.swift) |
| Sounds | `SOUNDS` list in [`scripts/generate_sounds.py`](scripts/generate_sounds.py) (each one must last less than 30 s) |
| Icon | See [Icon](#icon): `python3 scripts/make_icon.py --use N`, or replace `Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png` (1024×1024) |

## Icon

Four options on the same idea, a sunrise over the city. The app uses **1 (Horizon)**.

![The four icon options](design/icons/preview.png)

Each option is an SVG in [`design/icons/`](design/icons) drawn by [`scripts/make_icon.py`](scripts/make_icon.py). To change the app icon:

```sh
python3 scripts/make_icon.py --use 3    # 1 Horizon, 2 Alarm clock, 3 Window, 4 Isometric
```

It needs Pillow (`pip install pillow`) and Chrome or Chromium to convert the SVG to PNG (if it can't find it, point to it with `CHROME=/path/to/chrome`).

## Project structure

```
.
├── src/
│   ├── App/        # AlarmKit, App Intents, audio, signing
│   ├── Core/       # pure logic: sound rotation, challenge, schedules (tested in tests/)
│   └── Views/      # SwiftUI
├── tests/          # logic tests (make test)
├── Resources/      # asset catalog with the icon
├── scripts/        # sounds, icon, App Store Connect API, IPA verification, and GitHub Pages
├── design/icons/   # the four icon options (SVG) and their preview
├── Info.plist
├── project.yml     # Xcode project for XcodeGen (used by GitHub Actions)
├── build.sh        # full build without an Xcode project
├── Makefile
└── .github/workflows/build.yml
```

## License

[GNU General Public License v3.0](LICENSE). The sounds and the icon are generated with this repository's scripts and are distributed under the same license.
