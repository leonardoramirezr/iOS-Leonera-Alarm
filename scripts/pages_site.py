#!/usr/bin/env python3
"""Builds the GitHub Pages site that installs the Ad Hoc builds from Safari.

    pages_site.py build  --dir SITE/<tag> --base-url URL --tag TAG ...
        Writes one build folder: manifest.plist, index.html and build.json
        (the IPA and the 57/512 px icons must already be in the folder).
    pages_site.py index  --dir SITE --base-url URL --keep-branch-builds N
        Deletes the old branch builds (every main version is kept), rewrites the
        URLs of every build for URL and writes the home page that lists them all.
    pages_site.py screenshots --dir SITE/screenshots --full DIR --preview DIR --tag TAG
        Replaces the App Store screenshots with the ones screenshots/render.js
        wrote to DIR (full size, PNG) and DIR (small previews). There is only one
        set: every build page shows the one from the latest build that has it.

Only folders that contain a build.json are treated as builds.
"""

import argparse
import datetime
import html
import json
import os
import plistlib
import shutil
import sys
import urllib.parse
import zipfile

SCREENSHOTS = "screenshots"


def install_url(manifest_url):
    return "itms-services://?action=download-manifest&url=" + urllib.parse.quote(manifest_url, safe="")


def load_builds(site):
    builds = []
    for name in sorted(os.listdir(site)):
        path = os.path.join(site, name, "build.json")
        if os.path.isfile(path):
            try:
                with open(path, encoding="utf-8") as f:
                    build = json.load(f)
            except ValueError:
                print("warning: ignoring %s (invalid JSON)" % path, file=sys.stderr)
                continue
            build["folder"] = name
            builds.append(build)
    return builds


def version_key(build):
    try:
        return tuple(int(part) for part in build.get("version", "").split("."))
    except ValueError:
        return (0,)


PAGE = """<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<link rel="apple-touch-icon" href="{icon}">
<style>
:root {{ color-scheme: light dark; --bg: #f5f5f7; --card: #fff; --text: #1d1d1f; --muted: #6e6e73; --accent: #0071e3; --line: #d2d2d7; }}
@media (prefers-color-scheme: dark) {{ :root {{ --bg: #000; --card: #1c1c1e; --text: #f5f5f7; --muted: #98989d; --accent: #2997ff; --line: #38383a; }} }}
* {{ box-sizing: border-box; }}
body {{ margin: 0; background: var(--bg); color: var(--text); font: 16px/1.45 -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif; }}
main {{ max-width: 640px; margin: 0 auto; padding: 32px 16px 48px; }}
header {{ display: flex; gap: 16px; align-items: center; margin-bottom: 24px; }}
header img {{ width: 72px; height: 72px; border-radius: 16px; }}
h1 {{ font-size: 28px; margin: 0; }}
h2 {{ font-size: 20px; margin: 32px 0 12px; }}
p {{ margin: 4px 0; }}
.muted {{ color: var(--muted); font-size: 14px; }}
.button {{ display: block; text-align: center; background: var(--accent); color: #fff; text-decoration: none; font-weight: 600; padding: 14px 20px; border-radius: 12px; margin: 16px 0; }}
.card {{ background: var(--card); border-radius: 14px; padding: 16px; margin: 12px 0; }}
ul {{ list-style: none; padding: 0; margin: 0; background: var(--card); border-radius: 14px; }}
li {{ padding: 12px 16px; border-top: 1px solid var(--line); display: flex; justify-content: space-between; gap: 12px; align-items: center; }}
li:first-child {{ border-top: 0; }}
li a {{ color: var(--accent); text-decoration: none; font-weight: 600; }}
.tag {{ font-size: 12px; padding: 2px 8px; border-radius: 999px; border: 1px solid var(--line); color: var(--muted); white-space: nowrap; }}
code {{ font-size: 13px; }}
.warn {{ border: 2px solid #ff9f0a; font-weight: 600; }}
[hidden] {{ display: none !important; }}
.shots {{ display: flex; gap: 12px; overflow-x: auto; scroll-snap-type: x mandatory; padding: 4px 0 12px; margin: 12px 0; }}
.shots figure {{ flex: 0 0 40%; max-width: 200px; margin: 0; scroll-snap-align: start; }}
.shots img {{ display: block; width: 100%; height: auto; border-radius: 12px; background: var(--card); }}
.shots figcaption {{ font-size: 13px; color: var(--muted); margin-top: 6px; display: flex; flex-direction: column; }}
.button.secondary {{ background: var(--card); color: var(--accent); border: 1px solid var(--line); }}
a {{ color: var(--accent); }}
</style>
</head>
<body>
<main>
{body}
</main>
</body>
</html>
"""

HELP = """<p class="card warn" id="warn" hidden></p>
<div class="card" id="after" hidden>
<p><strong>¿Tocaste «Instalar» en la ventana de Safari?</strong></p>
<p class="muted">La app se descarga directo a la pantalla de inicio (o solo a la Biblioteca de apps, según tus ajustes), sin barra de progreso en Safari: desliza hacia abajo en la pantalla de inicio y busca «Extreme Alarm».
Si no apareció ninguna ventana, recarga esta página y vuelve a tocar el botón.</p>
</div>
<div class="card">
<p><strong>Cómo instalar</strong></p>
<p class="muted">Abre esta página en <strong>Safari</strong> (no en Chrome ni dentro de otra app) en un iPhone registrado en la cuenta de desarrollador, toca el botón y luego <strong>Instalar</strong> en la ventana que aparece.
Para abrir la app hace falta Ajustes › Privacidad y seguridad › <strong>Modo de desarrollador</strong> activado (pide reiniciar).</p>
</div>
<script>
(function () {
  var ua = navigator.userAgent;
  var ios = /iPhone|iPad|iPod/.test(ua) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);
  var safari = /Safari[/]/.test(ua) && !/CriOS|FxiOS|EdgiOS|OPiOS|GSA[/]/.test(ua);
  var warn = document.getElementById("warn");
  if (!ios) {
    warn.textContent = "Abre esta página en el iPhone: las apps solo se instalan desde Safari en el iPhone.";
    warn.hidden = false;
  } else if (!safari) {
    warn.textContent = "Estás en otro navegador o en el navegador de una app, que no pueden instalar apps. Abre esta página en Safari.";
    warn.hidden = false;
  }
  document.querySelectorAll('a[href^="itms-services:"]').forEach(function (a) {
    a.addEventListener("click", function () { document.getElementById("after").hidden = false; });
  });
})();
</script>"""


def write_json(path, data):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")


def load_screenshots(site):
    """The screenshots.json written by `screenshots`, or None."""
    path = os.path.join(site, SCREENSHOTS, "screenshots.json")
    if not os.path.isfile(path):
        return None
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except ValueError:
        print("warning: ignoring %s (invalid JSON)" % path, file=sys.stderr)
        return None


def screenshots_section(shots):
    """HTML for a build page (one folder below the site root)."""
    def url(file):
        # The files keep their names on every publish: ?v= skips stale caches.
        return "../%s/%s?v=%s" % (SCREENSHOTS, urllib.parse.quote(file), urllib.parse.quote(shots["tag"]))

    parts = ['<h2>Capturas para el App Store</h2>',
             '<p class="muted">Las del último build publicado (%s), en %d × %d, el tamaño de iPhone 6.9" que pide App Store Connect. '
             'Toca una para abrirla en tamaño completo.</p>' % (html.escape(shots["tag"]), shots["width"], shots["height"]),
             '<div class="shots">']
    for slide in shots["slides"]:
        parts.append('<figure><a href="%s"><img src="%s" alt="%s" width="%d" height="%d" loading="lazy"></a>'
                     '<figcaption><span>%s</span><a href="%s" download>Descargar</a></figcaption></figure>'
                     % (html.escape(url(slide["full"])), html.escape(url(slide["preview"])), html.escape(slide["name"]),
                        shots["preview_width"], shots["preview_height"], html.escape(slide["name"]),
                        html.escape(url(slide["full"]))))
    parts.append('</div>')
    missing = sorted({c for slide in shots["slides"] for c in slide.get("missing_captures", [])})
    if missing:
        parts.append('<p class="card warn">Faltan capturas en el repositorio: %s. Las imágenes que las usan muestran un aviso en su lugar; '
                     'no las subas al App Store.</p>' % ", ".join("<code>screenshots/%s</code>" % html.escape(c) for c in missing))
    parts.append('<a class="button secondary" href="%s" download>Descargar todas (ZIP)</a>' % html.escape(url(shots["zip"])))
    return "\n".join(parts)


def render_build(folder, build, base_url, shots=None):
    """Writes the URL-dependent files of a build (manifest.plist, index.html and
    the URLs in build.json) for base_url. Run for every build on each publish,
    so a change of Pages URL (e.g. a custom domain) reaches the old builds too,
    and so is the latest set of App Store screenshots (shots)."""
    base = base_url.rstrip("/") + "/" + urllib.parse.quote(build["tag"]) + "/"
    ipa_name = build["ipa"]
    manifest_url = base + "manifest.plist"
    manifest = {"items": [{
        "assets": [
            {"kind": "software-package", "url": base + urllib.parse.quote(ipa_name)},
            {"kind": "display-image", "url": base + "icon-57.png"},
            {"kind": "full-size-image", "url": base + "icon-512.png"},
        ],
        "metadata": {
            "bundle-identifier": build["bundle_id"],
            "bundle-version": build["version"],
            "kind": "software",
            "title": build["title"],
        },
    }]}
    with open(os.path.join(folder, "manifest.plist"), "wb") as f:
        plistlib.dump(manifest, f)

    build["manifest_url"] = manifest_url
    build["install_url"] = install_url(manifest_url)
    write_json(os.path.join(folder, "build.json"), {k: v for k, v in build.items() if k != "folder"})

    kind = ("versión estable" if build.get("stable")
            else "build de prueba de la rama <code>%s</code>" % html.escape(build.get("branch", "")))
    body = """<header><img src="icon-512.png" alt=""><div><h1>{title} {tag}</h1>
<p class="muted">{kind} · versión {version} ({build_number}) · commit <code>{commit}</code></p>{commit_title}</div></header>
<a class="button" href="{install}">Instalar en el iPhone</a>
{help}
<p class="muted"><a href="{ipa}">Descargar el IPA</a> · <a href="{release}">Release</a> · <a href="{run}">Ejecución en Actions</a> · <a href="../">Todos los builds</a></p>
{screenshots}
""".format(title=html.escape(build["title"]), tag=html.escape(build["tag"]), kind=kind,
           version=html.escape(build["version"]), build_number=html.escape(str(build.get("build_number", ""))),
           commit=html.escape(build.get("commit", "")[:7]),
           commit_title=('<p>%s</p>' % html.escape(build["commit_title"])) if build.get("commit_title") else "",
           install=html.escape(build["install_url"]), help=HELP,
           ipa=html.escape(urllib.parse.quote(ipa_name)), release=html.escape(build.get("release_url", "")),
           run=html.escape(build.get("run_url", "")),
           screenshots=screenshots_section(shots) if shots else "")
    with open(os.path.join(folder, "index.html"), "w", encoding="utf-8") as f:
        f.write(PAGE.format(title=html.escape("%s %s" % (build["title"], build["tag"])), icon="icon-512.png", body=body))


def cmd_build(args):
    folder = args.dir
    ipa_name = os.path.basename(args.ipa)
    if not os.path.isfile(os.path.join(folder, ipa_name)):
        sys.exit("error: %s is not in %s" % (ipa_name, folder))
    build = {
        "tag": args.tag,
        "version": args.version,
        "build_number": args.build_number,
        "run_number": int(args.run_number),
        "stable": args.stable == "true",
        "branch": args.branch,
        "commit": args.commit,
        "commit_title": args.commit_title,
        "bundle_id": args.bundle_id,
        "title": args.title,
        "date": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "ipa": ipa_name,
        "run_url": args.run_url,
        "release_url": args.release_url,
    }
    render_build(folder, build, args.base_url, load_screenshots(os.path.dirname(os.path.abspath(folder))))


def read_manifest(folder):
    with open(os.path.join(folder, "manifest.json"), encoding="utf-8") as f:
        return json.load(f)


def cmd_screenshots(args):
    full = read_manifest(args.full)
    preview = read_manifest(args.preview)
    previews = {slide["name"]: slide for slide in preview["slides"]}
    size = "%dx%d" % (full["width"], full["height"])
    if os.path.isdir(args.dir):
        shutil.rmtree(args.dir)
    os.makedirs(os.path.join(args.dir, size))
    os.makedirs(os.path.join(args.dir, "preview"))

    slides = []
    zip_name = "app-store-screenshots-%s.zip" % size
    with zipfile.ZipFile(os.path.join(args.dir, zip_name), "w", zipfile.ZIP_DEFLATED) as archive:
        for slide in full["slides"]:
            small = previews.get(slide["name"])
            if not small:
                sys.exit("error: %s has no preview in %s" % (slide["name"], args.preview))
            shutil.copyfile(os.path.join(args.full, slide["file"]), os.path.join(args.dir, size, slide["file"]))
            shutil.copyfile(os.path.join(args.preview, small["file"]), os.path.join(args.dir, "preview", small["file"]))
            archive.write(os.path.join(args.full, slide["file"]), slide["file"])
            slides.append({
                "name": slide["name"],
                "full": "%s/%s" % (size, slide["file"]),
                "preview": "preview/%s" % small["file"],
                "missing_captures": slide.get("missing_captures", []),
            })
    write_json(os.path.join(args.dir, "screenshots.json"), {
        "tag": args.tag,
        "date": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "width": full["width"],
        "height": full["height"],
        "preview_width": preview["width"],
        "preview_height": preview["height"],
        "zip": zip_name,
        "slides": slides,
    })
    print("App Store screenshots of %s: %d slides" % (args.tag, len(slides)))


def cmd_index(args):
    site = args.dir
    builds = load_builds(site)
    stable = sorted((b for b in builds if b.get("stable")), key=version_key, reverse=True)
    branch = sorted((b for b in builds if not b.get("stable")), key=lambda b: b.get("run_number", 0), reverse=True)
    for old in branch[args.keep_branch_builds:]:
        print("Removing old branch build " + old["folder"])
        shutil.rmtree(os.path.join(site, old["folder"]))
    branch = branch[:args.keep_branch_builds]
    shots = load_screenshots(site)
    for b in stable + branch:
        render_build(os.path.join(site, b["folder"]), b, args.base_url, shots)

    title = (stable or branch or [{}])[0].get("title", "App")
    parts = []
    icon = ""
    if stable:
        latest = stable[0]
        icon = latest["folder"] + "/icon-512.png"
        parts.append('<header><img src="%s" alt=""><div><h1>%s</h1><p class="muted">Última versión estable: <strong>%s</strong></p></div></header>'
                     % (html.escape(icon), html.escape(title), html.escape(latest["tag"])))
        parts.append('<a class="button" href="%s">Instalar la última versión estable (%s)</a>'
                     % (html.escape(latest["install_url"]), html.escape(latest["tag"])))
    else:
        if branch:
            icon = branch[0]["folder"] + "/icon-512.png"
        parts.append("<header><div><h1>%s</h1><p class=\"muted\">Todavía no hay una versión estable (de <code>main</code>).</p></div></header>"
                     % html.escape(title))
    parts.append(HELP)

    def listing(heading, items, empty):
        parts.append("<h2>%s</h2>" % heading)
        if not items:
            parts.append('<p class="muted">%s</p>' % empty)
            return
        parts.append("<ul>")
        for b in items:
            detail = b.get("date", "")[:10]
            if not b.get("stable"):
                detail = "%s · %s" % (b.get("branch", ""), detail)
            if b.get("commit_title"):
                detail = "%s · %s" % (b["commit_title"], detail)
            parts.append('<li><div><a href="%s/">%s</a><p class="muted">%s</p></div><a class="tag" href="%s">Instalar</a></li>'
                         % (html.escape(urllib.parse.quote(b["folder"])), html.escape(b["tag"]),
                            html.escape(detail), html.escape(b["install_url"])))
        parts.append("</ul>")

    listing("Versiones estables (main)", stable, "Ninguna todavía.")
    listing("Builds de otras ramas", branch, "Ninguno.")
    with open(os.path.join(site, "index.html"), "w", encoding="utf-8") as f:
        f.write(PAGE.format(title=html.escape(title), icon=html.escape(icon), body="\n".join(parts)))
    with open(os.path.join(site, "builds.json"), "w", encoding="utf-8") as f:
        json.dump([{k: v for k, v in b.items() if k != "folder"} for b in stable + branch], f, ensure_ascii=False, indent=2)
        f.write("\n")
    open(os.path.join(site, ".nojekyll"), "w").close()


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)
    build = sub.add_parser("build")
    for name in ("dir", "base-url", "tag", "ipa", "bundle-id", "version", "build-number", "run-number",
                 "stable", "branch", "commit", "title", "run-url", "release-url"):
        build.add_argument("--" + name, required=True)
    build.add_argument("--commit-title", default="")
    build.set_defaults(func=cmd_build)
    index = sub.add_parser("index")
    index.add_argument("--dir", required=True)
    index.add_argument("--base-url", required=True)
    index.add_argument("--keep-branch-builds", type=int, default=50)
    index.set_defaults(func=cmd_index)
    screenshots = sub.add_parser("screenshots")
    for name in ("dir", "full", "preview", "tag"):
        screenshots.add_argument("--" + name, required=True)
    screenshots.set_defaults(func=cmd_screenshots)
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
