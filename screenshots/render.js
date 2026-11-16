#!/usr/bin/env node
// Renders every slide (NN-name.html) to a PNG ready for App Store Connect.
//
//   node render.js                      # 6.9" (1320 x 2868), into output/1320x2868/
//   node render.js --size 6.9,6.5       # several sizes
//   node render.js --size 1290x2796     # any size whose sides divide by 3
//   node render.js --only 02,05         # just some slides
//   node render.js --out ~/Desktop/shots
//
// Each slide is laid out at a third of the final size and captured at device
// scale factor 3, the way an iPhone draws it. See README.md.

const fs = require("fs");
const path = require("path");
const zlib = require("zlib");
const { pathToFileURL } = require("url");
const { chromium } = require("playwright");

const ROOT = __dirname;
const SCALE = 3;

// Portrait sizes App Store Connect accepts for iPhone.
const PRESETS = {
  "6.9": [1320, 2868],
  "6.7": [1290, 2796],
  "6.5": [1284, 2778],
  "6.5-xs": [1242, 2688],
};

function parseArgs(argv) {
  const options = { sizes: ["6.9"], only: [], out: path.join(ROOT, "output") };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    const value = () => {
      if (i + 1 >= argv.length) throw new Error(`${arg} needs a value`);
      return argv[++i];
    };
    if (arg === "--size") options.sizes = value().split(",");
    else if (arg === "--only") options.only = value().split(",");
    else if (arg === "--out") options.out = path.resolve(value());
    else if (arg === "--help" || arg === "-h") {
      console.log(fs.readFileSync(__filename, "utf8").split("\n").slice(1, 9).map((l) => l.replace(/^\/\/ ?/, "")).join("\n"));
      process.exit(0);
    } else throw new Error(`Unknown option ${arg} (see --help)`);
  }
  return options;
}

function resolveSize(size) {
  const preset = PRESETS[size];
  const match = /^(\d+)x(\d+)$/.exec(size);
  const [width, height] = preset || (match ? [Number(match[1]), Number(match[2])] : []);
  if (!width) throw new Error(`Unknown size ${size}: use ${Object.keys(PRESETS).join(", ")} or WIDTHxHEIGHT`);
  if (width % SCALE || height % SCALE) throw new Error(`${width}x${height}: both sides must divide by ${SCALE}`);
  return { width, height };
}

function findSlides(only) {
  return fs
    .readdirSync(ROOT)
    .filter((file) => /^\d{2}-[\w-]+\.html$/.test(file))
    .filter((file) => only.length === 0 || only.some((prefix) => file.startsWith(prefix)))
    .sort();
}

// zlib.crc32 only exists since Node 20.15 / 22.2.
const CRC_TABLE = Array.from({ length: 256 }, (_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});
function crc32(buffer) {
  if (zlib.crc32) return zlib.crc32(buffer);
  let c = 0xffffffff;
  for (const byte of buffer) c = CRC_TABLE[(c ^ byte) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

// App Store Connect wants opaque images. Chromium writes RGBA PNGs even when
// every pixel is opaque, so drop the alpha channel: decode, keep RGB, encode.
function pngToRgb(buffer) {
  const SIGNATURE = buffer.subarray(0, 8);
  let offset = 8;
  let header;
  const data = [];
  while (offset < buffer.length) {
    const length = buffer.readUInt32BE(offset);
    const type = buffer.toString("ascii", offset + 4, offset + 8);
    const body = buffer.subarray(offset + 8, offset + 8 + length);
    if (type === "IHDR") header = body;
    if (type === "IDAT") data.push(body);
    offset += 12 + length;
  }
  const width = header.readUInt32BE(0);
  const height = header.readUInt32BE(4);
  const bitDepth = header[8];
  const colorType = header[9];
  if (colorType === 2) return buffer; // already RGB
  if (colorType !== 6 || bitDepth !== 8 || header[12] !== 0) {
    throw new Error(`Unexpected PNG format (color type ${colorType}, depth ${bitDepth})`);
  }

  const raw = zlib.inflateSync(Buffer.concat(data));
  const stride = width * 4;
  const rgba = Buffer.alloc(stride * height);
  for (let y = 0; y < height; y++) {
    const filter = raw[y * (stride + 1)];
    const line = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1));
    const out = rgba.subarray(y * stride, (y + 1) * stride);
    const prev = y > 0 ? rgba.subarray((y - 1) * stride, y * stride) : null;
    for (let x = 0; x < stride; x++) {
      const left = x >= 4 ? out[x - 4] : 0;
      const up = prev ? prev[x] : 0;
      const upLeft = prev && x >= 4 ? prev[x - 4] : 0;
      let predictor = 0;
      if (filter === 1) predictor = left;
      else if (filter === 2) predictor = up;
      else if (filter === 3) predictor = (left + up) >> 1;
      else if (filter === 4) {
        const p = left + up - upLeft;
        const pa = Math.abs(p - left);
        const pb = Math.abs(p - up);
        const pc = Math.abs(p - upLeft);
        predictor = pa <= pb && pa <= pc ? left : pb <= pc ? up : upLeft;
      }
      out[x] = (line[x] + predictor) & 0xff;
    }
  }

  // Re-encode as RGB with the "up" filter on every line (compresses well).
  const rgbStride = width * 3;
  const rgb = Buffer.alloc((rgbStride + 1) * height);
  let previous = Buffer.alloc(rgbStride);
  for (let y = 0; y < height; y++) {
    const row = Buffer.alloc(rgbStride);
    for (let x = 0; x < width; x++) {
      row[x * 3] = rgba[y * stride + x * 4];
      row[x * 3 + 1] = rgba[y * stride + x * 4 + 1];
      row[x * 3 + 2] = rgba[y * stride + x * 4 + 2];
    }
    const base = y * (rgbStride + 1);
    rgb[base] = 2;
    for (let x = 0; x < rgbStride; x++) rgb[base + 1 + x] = (row[x] - previous[x]) & 0xff;
    previous = row;
  }

  const chunk = (type, body) => {
    const length = Buffer.alloc(4);
    length.writeUInt32BE(body.length);
    const typeAndBody = Buffer.concat([Buffer.from(type, "ascii"), body]);
    const crc = Buffer.alloc(4);
    crc.writeUInt32BE(crc32(typeAndBody));
    return Buffer.concat([length, typeAndBody, crc]);
  };
  const ihdr = Buffer.from(header);
  ihdr[9] = 2;
  return Buffer.concat([
    SIGNATURE,
    chunk("IHDR", ihdr),
    chunk("IDAT", zlib.deflateSync(rgb, { level: 9 })),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const sizes = options.sizes.map(resolveSize);
  const slides = findSlides(options.only);
  if (slides.length === 0) throw new Error("No slides matched");

  const browser = await chromium.launch();
  const missing = new Set();
  try {
    for (const { width, height } of sizes) {
      const dir = path.join(options.out, `${width}x${height}`);
      fs.mkdirSync(dir, { recursive: true });
      const context = await browser.newContext({
        viewport: { width: width / SCALE, height: height / SCALE },
        deviceScaleFactor: SCALE,
      });
      const page = await context.newPage();
      for (const slide of slides) {
        await page.goto(pathToFileURL(path.join(ROOT, slide)).href, { waitUntil: "load" });
        await page.evaluate(() => document.fonts.ready);
        for (const file of await page.$$eval(".frame.missing .screen", (imgs) => imgs.map((img) => img.getAttribute("src")))) {
          missing.add(file);
        }
        const png = pngToRgb(await page.screenshot({ type: "png", animations: "disabled" }));
        const outFile = path.join(dir, slide.replace(/\.html$/, ".png"));
        fs.writeFileSync(outFile, png);
        console.log(`${path.relative(process.cwd(), outFile)}  ${png.readUInt32BE(16)}x${png.readUInt32BE(20)}`);
      }
      await context.close();
    }
  } finally {
    await browser.close();
  }

  if (missing.size > 0) {
    console.warn(`\nMissing captures (rendered with a placeholder):\n${[...missing].map((f) => `  screenshots/${f}`).join("\n")}`);
  }
}

main().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});
