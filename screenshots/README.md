# App Store screenshots

Marketing screenshots for **Extreme Alarm by Leonera Labs**: every slide has a title, a subtitle, and a full app capture inside an iPhone frame. They are plain HTML and CSS pages with the captures embedded as images, rendered to PNG with [Playwright](https://playwright.dev).

The slides are in Spanish, like the app.

## Files

```
screenshots/
├── 01-intro.html … 05-statistics.html   # one page per slide: its title and subtitle
├── styles.css     # shared layout, iPhone frame, and the two themes
├── slide.js       # fits the frame to the capture and flags missing captures
├── index.html     # preview of the five slides side by side (open it in a browser)
├── render.js      # Playwright script that writes the PNGs
├── package.json
├── fonts/         # Inter and Inter Tight (SIL Open Font License, see fonts/OFL.txt)
├── captures/      # INPUT: the app screenshots you take on the iPhone
└── output/        # OUTPUT: the rendered PNGs (not committed)
```

## The slides

| # | Slide | Theme | Title / subtitle | Capture it expects |
|---|---|---|---|---|
| 1 | `01-intro.html` | night | «Despierta de verdad» / what the app does and why: an alarm with no snooze that only turns off with mental math | `captures/01-intro.png`: the alarm ringing on the lock screen (see [tips](#taking-the-captures)) |
| 2 | `02-challenge.html` | dawn | «Resuelve para apagarla» / the clock only runs while you answer correctly | `captures/02-challenge.png`: the challenge, with an operation and the keypad |
| 3 | `03-schedule.html` | night | «Tu horario, día por día» / days and a time for each day | `captures/03-schedule.png`: top of the main screen, with «Alarma activada», the days, and the per-day times |
| 4 | `04-difficulty.html` | dawn | «Tú eliges el reto» / 1, 2, or 3 digits, 15 s to 10 min | `captures/04-difficulty.png`: main screen scrolled to «Dificultad del reto» and «Duración del reto» |
| 5 | `05-statistics.html` | night | «Mide cómo despiertas» / time it rang, time you turned it off, how long it took | `captures/05-statistics.png`: «Estadísticas» with «Gráficas» selected |

## Naming the files

- **Captures (input):** `captures/<slide>.png`, the slide's file name with `.png` instead of `.html`: `01-intro.png`, `02-challenge.png`, `03-schedule.png`, `04-difficulty.png`, `05-statistics.png`. Lowercase, PNG, exactly as the iPhone saves it (don't crop or resize it).
- **Rendered (output):** `output/<width>x<height>/<slide>.png`, for example `output/1320x2868/01-intro.png`. The number prefix is the order to upload them in App Store Connect.

A slide whose capture is missing still renders, with a striped placeholder that names the file it expects, and `render.js` lists the missing files at the end. Don't upload those.

> The captures currently in `captures/` are from before the rename: the main screen still says «Vigilia». Take them again with a build that says «Extreme Alarm», and add `01-intro.png`.

## Taking the captures

- Use any iPhone with Face ID (the frame draws a Dynamic Island over the middle of the status bar, which captures leave empty). Captures are 1179 × 2556 or 1206 × 2622 on the 6.1" and 6.3" iPhones and 1290 × 2796 or 1320 × 2868 on the large ones; all of them fit, and the frame takes the capture's proportions.
- Take a screenshot with the **side button + volume up** and AirDrop or sync the PNG to your computer. Don't send it through a chat app: they recompress it.
- For the **alarm ringing** (slide 1), pressing the side button can stop the alarm, so turn on **Back Tap** first (Settings › Accessibility › Touch › Back Tap › Double Tap › Screenshot) and double-tap the back of the iPhone. Set a real alarm one or two minutes ahead so it shows «¡Despierta! Haz el reto»; the «Probar» test alarm shows «Prueba de Extreme Alarm» instead.
- For a tidy status bar: charge the battery, turn off any Focus (it adds an icon next to the time), and use Wi-Fi.
- For the statistics, use an iPhone that already has a few weeks of wake-ups, so the charts have something to show.

## Rendering

Requirements: [Node.js](https://nodejs.org) 18 or later. Works on macOS, Windows, and Linux.

```sh
cd screenshots
npm install                       # installs Playwright
npx playwright install chromium   # downloads its Chromium (once)
npm run render                    # 6.9" PNGs in output/1320x2868/
```

Options (`node render.js --help`):

```sh
node render.js --size 6.9,6.5        # several sizes: 6.9, 6.7, 6.5, 6.5-xs, or WIDTHxHEIGHT
node render.js --size 1290x2796      # a custom size (both sides must divide by 3)
node render.js --only 02,05          # only the slides whose name starts with 02 or 05
node render.js --out ~/Desktop/shots # another output folder
npm run render:all                   # 6.9" and 6.5"
```

| Preset | Size | App Store Connect display |
|---|---|---|
| `6.9` (default) | 1320 × 2868 | iPhone 6.9" (required; App Store Connect scales it down for smaller iPhones) |
| `6.7` | 1290 × 2796 | Also accepted as 6.9" |
| `6.5` | 1284 × 2778 | iPhone 6.5" (only if you want a separate set) |
| `6.5-xs` | 1242 × 2688 | iPhone 6.5" |

Each page is laid out at a third of the final size (440 × 956 for 1320 × 2868) and captured at device scale factor 3, the way an iPhone draws it. The PNGs are written without an alpha channel (Chromium adds one), so App Store Connect never sees transparency. Check the current sizes in App Store Connect's [screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications) before uploading.

## Editing the slides

- **Text:** edit the `<h1>` (title) and `<p>` (subtitle) of the slide's HTML file. Wrap the words to highlight in `<em>`: orange on the night theme, deep orange on the dawn theme. Use `<br>` to choose where the title breaks.
- **Length:** the layout reserves room for a two-line title and a three-line subtitle, so the phone keeps the same size and position on every slide. Longer text pushes the phone down and makes it smaller; check it in `index.html`.
- **Theme:** the class on `<main>`: `theme-night` (the colors of the challenge screen, with dawn at the bottom) or `theme-dawn` (cream turning orange). The slides alternate them so they look good side by side in the App Store.
- **Preview:** open `index.html` (or any slide) in Chrome. With the developer tools in device mode at 440 × 956 you see the slide exactly as it renders.
- **Adding a slide:** copy one of the HTML files with the next number (`06-sounds.html`), change its text and its `<img src>` to `captures/06-sounds.png`, and add it to `index.html`. `render.js` picks up every `NN-name.html` file by itself.
- **No app icon** on the slides: the App Store already shows it next to them.
