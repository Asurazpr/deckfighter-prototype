const fs = require("fs");
const path = require("path");
const zlib = require("zlib");

const rootDir = path.resolve(__dirname, "..");
const projectDir = path.join(rootDir, "spine_humanoid_combat");
const imageDir = path.join(projectDir, "images");
const exportDir = path.join(projectDir, "export");

for (const dir of [projectDir, imageDir, exportDir]) fs.mkdirSync(dir, { recursive: true });

function crc32(buf) {
  let c = ~0;
  for (let i = 0; i < buf.length; i++) {
    c ^= buf[i];
    for (let k = 0; k < 8; k++) c = (c >>> 1) ^ (0xedb88320 & -(c & 1));
  }
  return (~c) >>> 0;
}

function chunk(type, data) {
  const name = Buffer.from(type, "ascii");
  const out = Buffer.alloc(12 + data.length);
  out.writeUInt32BE(data.length, 0);
  name.copy(out, 4);
  data.copy(out, 8);
  out.writeUInt32BE(crc32(Buffer.concat([name, data])), 8 + data.length);
  return out;
}

function writePng(file, img) {
  const raw = Buffer.alloc((img.w * 4 + 1) * img.h);
  for (let y = 0; y < img.h; y++) {
    const row = y * (img.w * 4 + 1);
    raw[row] = 0;
    img.data.copy(raw, row + 1, y * img.w * 4, (y + 1) * img.w * 4);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(img.w, 0);
  ihdr.writeUInt32BE(img.h, 4);
  ihdr[8] = 8;
  ihdr[9] = 6;
  fs.writeFileSync(file, Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    chunk("IHDR", ihdr),
    chunk("IDAT", zlib.deflateSync(raw, { level: 9 })),
    chunk("IEND", Buffer.alloc(0)),
  ]));
}

function makeImage(w, h) {
  return { w, h, data: Buffer.alloc(w * h * 4) };
}

function setPx(img, x, y, rgba, aScale = 1) {
  if (x < 0 || y < 0 || x >= img.w || y >= img.h) return;
  const i = (y * img.w + x) * 4;
  const a = Math.max(0, Math.min(255, Math.round(rgba[3] * aScale)));
  const inv = (255 - a) / 255;
  img.data[i] = Math.round(rgba[0] * (a / 255) + img.data[i] * inv);
  img.data[i + 1] = Math.round(rgba[1] * (a / 255) + img.data[i + 1] * inv);
  img.data[i + 2] = Math.round(rgba[2] * (a / 255) + img.data[i + 2] * inv);
  img.data[i + 3] = Math.min(255, a + img.data[i + 3] * inv);
}

function drawEllipse(img, cx, cy, rx, ry, fill, stroke) {
  const minX = Math.floor(cx - rx - 2), maxX = Math.ceil(cx + rx + 2);
  const minY = Math.floor(cy - ry - 2), maxY = Math.ceil(cy + ry + 2);
  for (let y = minY; y <= maxY; y++) for (let x = minX; x <= maxX; x++) {
    const d = ((x + 0.5 - cx) ** 2) / (rx ** 2) + ((y + 0.5 - cy) ** 2) / (ry ** 2);
    if (d <= 1) setPx(img, x, y, fill);
    else if (stroke && d <= 1.12) setPx(img, x, y, stroke, 0.75);
  }
}

function drawRoundRect(img, x, y, w, h, r, fill, stroke) {
  const rr = Math.min(r, w / 2, h / 2);
  for (let py = Math.floor(y - 2); py < Math.ceil(y + h + 2); py++) {
    for (let px = Math.floor(x - 2); px < Math.ceil(x + w + 2); px++) {
      const qx = Math.max(x + rr, Math.min(px + 0.5, x + w - rr));
      const qy = Math.max(y + rr, Math.min(py + 0.5, y + h - rr));
      const dist = Math.hypot(px + 0.5 - qx, py + 0.5 - qy);
      if (px + 0.5 >= x + rr && px + 0.5 <= x + w - rr && py + 0.5 >= y && py + 0.5 <= y + h) setPx(img, px, py, fill);
      else if (px + 0.5 >= x && px + 0.5 <= x + w && py + 0.5 >= y + rr && py + 0.5 <= y + h - rr) setPx(img, px, py, fill);
      else if (dist <= rr) setPx(img, px, py, fill);
      else if (stroke && dist <= rr + 1.2) setPx(img, px, py, stroke, 0.75);
    }
  }
}

function drawPoly(img, pts, fill, stroke) {
  const xs = pts.map(p => p[0]), ys = pts.map(p => p[1]);
  const minX = Math.floor(Math.min(...xs) - 2), maxX = Math.ceil(Math.max(...xs) + 2);
  const minY = Math.floor(Math.min(...ys) - 2), maxY = Math.ceil(Math.max(...ys) + 2);
  for (let y = minY; y <= maxY; y++) for (let x = minX; x <= maxX; x++) {
    let inside = false;
    for (let i = 0, j = pts.length - 1; i < pts.length; j = i++) {
      const xi = pts[i][0], yi = pts[i][1], xj = pts[j][0], yj = pts[j][1];
      if (((yi > y) !== (yj > y)) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) inside = !inside;
    }
    if (inside) setPx(img, x, y, fill);
  }
  if (stroke) {
    for (let i = 0; i < pts.length; i++) {
      const a = pts[i], b = pts[(i + 1) % pts.length];
      for (let t = 0; t <= 1; t += 0.004) drawEllipse(img, a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, 1.2, 1.2, stroke);
    }
  }
}

const skin = [194, 151, 121, 255];
const skinDark = [111, 83, 69, 255];
const torso = [163, 126, 102, 255];
const joint = [128, 96, 78, 255];

const parts = [
  { name: "head", w: 70, h: 82, draw: i => { drawEllipse(i, 35, 43, 27, 35, skin, skinDark); drawEllipse(i, 26, 38, 2, 2, skinDark); drawEllipse(i, 44, 38, 2, 2, skinDark); drawRoundRect(i, 29, 61, 12, 2, 1, skinDark); } },
  { name: "neck", w: 36, h: 42, draw: i => drawRoundRect(i, 7, 3, 22, 36, 9, skin, skinDark) },
  { name: "chest", w: 112, h: 104, draw: i => drawPoly(i, [[12, 12], [100, 12], [88, 96], [24, 96]], torso, skinDark) },
  { name: "abdomen", w: 84, h: 86, draw: i => drawPoly(i, [[14, 4], [70, 4], [76, 78], [8, 78]], [173, 132, 106, 255], skinDark) },
  { name: "pelvis", w: 88, h: 62, draw: i => { drawPoly(i, [[18, 7], [70, 7], [80, 44], [55, 57], [33, 57], [8, 44]], [139, 104, 87, 255], skinDark); } },
  { name: "left_upper_arm", w: 98, h: 34, draw: i => drawRoundRect(i, 4, 6, 90, 22, 11, skin, skinDark) },
  { name: "right_upper_arm", w: 98, h: 34, draw: i => drawRoundRect(i, 4, 6, 90, 22, 11, skin, skinDark) },
  { name: "left_forearm", w: 92, h: 30, draw: i => drawRoundRect(i, 3, 6, 84, 18, 9, [188, 145, 117, 255], skinDark) },
  { name: "right_forearm", w: 92, h: 30, draw: i => drawRoundRect(i, 3, 6, 84, 18, 9, [188, 145, 117, 255], skinDark) },
  { name: "left_hand", w: 40, h: 30, draw: i => drawEllipse(i, 18, 15, 15, 11, skin, skinDark) },
  { name: "right_hand", w: 40, h: 30, draw: i => drawEllipse(i, 22, 15, 15, 11, skin, skinDark) },
  { name: "left_thigh", w: 148, h: 42, draw: i => drawRoundRect(i, 6, 6, 136, 30, 15, [168, 126, 101, 255], skinDark) },
  { name: "right_thigh", w: 148, h: 40, draw: i => drawRoundRect(i, 6, 6, 136, 28, 14, [158, 117, 95, 255], skinDark) },
  { name: "left_shin", w: 148, h: 34, draw: i => drawRoundRect(i, 5, 6, 138, 22, 11, [185, 140, 113, 255], skinDark) },
  { name: "right_shin", w: 148, h: 32, draw: i => drawRoundRect(i, 5, 6, 138, 20, 10, [174, 129, 105, 255], skinDark) },
  { name: "left_foot", w: 72, h: 32, draw: i => drawPoly(i, [[7, 7], [45, 7], [66, 18], [58, 27], [10, 25]], skin, skinDark) },
  { name: "right_foot", w: 72, h: 32, draw: i => drawPoly(i, [[27, 7], [65, 7], [62, 25], [14, 27], [6, 18]], skin, skinDark) },
  { name: "left_shoulder_cap", w: 42, h: 38, draw: i => drawEllipse(i, 21, 19, 17, 14, joint, skinDark) },
  { name: "right_shoulder_cap", w: 42, h: 38, draw: i => drawEllipse(i, 21, 19, 17, 14, joint, skinDark) },
  { name: "left_hip_cap", w: 44, h: 38, draw: i => drawEllipse(i, 22, 19, 18, 14, joint, skinDark) },
  { name: "right_hip_cap", w: 44, h: 38, draw: i => drawEllipse(i, 22, 19, 18, 14, joint, skinDark) },
];

const rendered = {};
for (const p of parts) {
  const img = makeImage(p.w, p.h);
  p.draw(img);
  rendered[p.name] = img;
  writePng(path.join(imageDir, `${p.name}.png`), img);
}

const atlas = makeImage(1024, 512);
let x = 4, y = 4, rowH = 0;
const regions = {};
for (const p of parts) {
  if (x + p.w + 4 > atlas.w) { x = 4; y += rowH + 4; rowH = 0; }
  const img = rendered[p.name];
  for (let py = 0; py < img.h; py++) img.data.copy(atlas.data, ((y + py) * atlas.w + x) * 4, py * img.w * 4, (py + 1) * img.w * 4);
  regions[p.name] = { x, y, w: p.w, h: p.h };
  x += p.w + 4;
  rowH = Math.max(rowH, p.h);
}
writePng(path.join(exportDir, "humanoid-combat.png"), atlas);

let atlasText = "humanoid-combat.png\nsize: 1024,512\nformat: RGBA8888\nfilter: Linear,Linear\nrepeat: none\n";
for (const p of parts) {
  const r = regions[p.name];
  atlasText += `${p.name}\n  rotate: false\n  xy: ${r.x}, ${r.y}\n  size: ${r.w}, ${r.h}\n  orig: ${r.w}, ${r.h}\n  offset: 0, 0\n  index: -1\n`;
}
fs.writeFileSync(path.join(exportDir, "humanoid-combat.atlas"), atlasText);

const bones = [
  { name: "root_master" },
  { name: "pelvis_root", parent: "root_master", length: 34, x: 0, y: 305, rotation: 90 },
  { name: "abdomen", parent: "pelvis_root", length: 58, x: 34, y: 0, rotation: 0 },
  { name: "chest", parent: "abdomen", length: 66, x: 58, y: 0, rotation: 0 },
  { name: "neck", parent: "chest", length: 22, x: 64, y: 0, rotation: 0 },
  { name: "head", parent: "neck", length: 30, x: 27, y: 0, rotation: 0 },
  { name: "arms", parent: "chest", length: 12, x: 50, y: 0, rotation: 0 },
  { name: "left_shoulder", parent: "arms", length: 20, x: -4, y: 52, rotation: 88 },
  { name: "left_upper_arm", parent: "left_shoulder", length: 86, x: 0, y: 0, rotation: 24 },
  { name: "left_forearm", parent: "left_upper_arm", length: 82, x: 82, y: 0, rotation: -7 },
  { name: "left_hand", parent: "left_forearm", length: 22, x: 78, y: 0, rotation: 0 },
  { name: "right_shoulder", parent: "arms", length: 20, x: 3, y: -42, rotation: -95 },
  { name: "right_upper_arm", parent: "right_shoulder", length: 82, x: 0, y: 0, rotation: -18 },
  { name: "right_forearm", parent: "right_upper_arm", length: 78, x: 78, y: 0, rotation: 5 },
  { name: "right_hand", parent: "right_forearm", length: 22, x: 78, y: 0, rotation: 0 },
  { name: "legs", parent: "pelvis_root", length: 12, x: -30, y: 0, rotation: 0 },
  { name: "left_thigh", parent: "legs", length: 132, x: 0, y: 38, rotation: -180 },
  { name: "left_shin", parent: "left_thigh", length: 132, x: 132, y: 0, rotation: 7 },
  { name: "left_foot", parent: "left_shin", length: 56, x: 132, y: 0, rotation: 82 },
  { name: "right_thigh", parent: "legs", length: 132, x: 0, y: -30, rotation: -168 },
  { name: "right_shin", parent: "right_thigh", length: 132, x: 132, y: 0, rotation: -9 },
  { name: "right_foot", parent: "right_shin", length: 56, x: 132, y: 0, rotation: 77 },
];

const slotOrder = [
  ["right_foot", "right_foot"], ["right_shin", "right_shin"], ["right_thigh", "right_thigh"], ["right_hip_cap", "right_thigh"],
  ["left_foot", "left_foot"], ["left_shin", "left_shin"], ["left_thigh", "left_thigh"], ["left_hip_cap", "left_thigh"],
  ["pelvis", "pelvis_root"], ["abdomen", "abdomen"], ["chest", "chest"], ["neck", "neck"], ["head", "head"],
  ["right_upper_arm", "right_upper_arm"], ["right_forearm", "right_forearm"], ["right_hand", "right_hand"], ["right_shoulder_cap", "right_shoulder"],
  ["left_upper_arm", "left_upper_arm"], ["left_forearm", "left_forearm"], ["left_hand", "left_hand"], ["left_shoulder_cap", "left_shoulder"],
];

const slots = slotOrder.map(([name, bone]) => ({ name, bone, attachment: name }));

const attach = {};
function addAttachment(slot, name, spec) {
  attach[slot] ||= {};
  attach[slot][name] = { type: "region", path: name, ...spec };
}
addAttachment("pelvis", "pelvis", { x: 0, y: 0, rotation: -90, width: 88, height: 62 });
addAttachment("abdomen", "abdomen", { x: 26, y: 0, rotation: -90, width: 84, height: 86 });
addAttachment("chest", "chest", { x: 30, y: 0, rotation: -90, width: 112, height: 104 });
addAttachment("neck", "neck", { x: 11, y: 0, rotation: -90, width: 36, height: 42 });
addAttachment("head", "head", { x: 32, y: 0, rotation: -90, width: 70, height: 82 });
for (const side of ["left", "right"]) {
  const far = side === "right";
  addAttachment(`${side}_shoulder_cap`, `${side}_shoulder_cap`, { x: 0, y: 0, width: 42, height: 38, scaleY: far ? 0.9 : 1 });
  addAttachment(`${side}_upper_arm`, `${side}_upper_arm`, { x: far ? 40 : 45, y: 0, width: 98, height: 34, scaleY: far ? 0.9 : 1 });
  addAttachment(`${side}_forearm`, `${side}_forearm`, { x: far ? 39 : 42, y: 0, width: 92, height: 30, scaleY: far ? 0.9 : 1 });
  addAttachment(`${side}_hand`, `${side}_hand`, { x: 18, y: 0, width: 40, height: 30, scaleY: far ? 0.9 : 1 });
  addAttachment(`${side}_hip_cap`, `${side}_hip_cap`, { x: 0, y: 0, width: 44, height: 38, scaleY: far ? 0.9 : 1 });
  addAttachment(`${side}_thigh`, `${side}_thigh`, { x: 66, y: 0, width: 148, height: far ? 40 : 42, scaleY: far ? 0.92 : 1 });
  addAttachment(`${side}_shin`, `${side}_shin`, { x: 67, y: 0, width: 148, height: far ? 32 : 34, scaleY: far ? 0.92 : 1 });
  addAttachment(`${side}_foot`, `${side}_foot`, { x: 31, y: 15, width: 72, height: 32, scaleY: far ? 0.92 : 1 });
}

function rotate(keys) { return keys.map(([time, angle]) => ({ time, angle })); }
function translate(keys) { return keys.map(([time, x, y]) => ({ time, x, y })); }
const walkFrames = [0, 6 / 24, 12 / 24, 18 / 24, 1];

const animations = {
  idle: {
    bones: {
      pelvis_root: { translate: translate([[0, 0, 0], [0.55, 0, 2], [1.1, 0, 0]]) },
      chest: { rotate: rotate([[0, 0], [0.55, 1.5], [1.1, 0]]) },
      head: { rotate: rotate([[0, 0], [0.55, -1], [1.1, 0]]) },
      left_forearm: { rotate: rotate([[0, -6], [0.55, -3], [1.1, -6]]) },
      right_forearm: { rotate: rotate([[0, 6], [0.55, 3], [1.1, 6]]) },
    },
  },
  idle_3q: {
    bones: {
      pelvis_root: { translate: translate([[0, 0, 0], [0.45, 0, 2], [0.9, 0, 0]]), rotate: rotate([[0, 0], [0.45, -1.2], [0.9, 0]]) },
      abdomen: { rotate: rotate([[0, 0], [0.45, 1.2], [0.9, 0]]) },
      chest: { rotate: rotate([[0, 0], [0.45, 2], [0.9, 0]]) },
      head: { rotate: rotate([[0, 0], [0.45, -1.5], [0.9, 0]]) },
      left_upper_arm: { rotate: rotate([[0, 24], [0.45, 26], [0.9, 24]]) },
      right_upper_arm: { rotate: rotate([[0, -18], [0.45, -16], [0.9, -18]]) },
      left_forearm: { rotate: rotate([[0, -7], [0.45, -4], [0.9, -7]]) },
      right_forearm: { rotate: rotate([[0, 5], [0.45, 3], [0.9, 5]]) },
    },
  },
  walk: {
    bones: {
      pelvis_root: { translate: translate([[0, 0, 0], [0.25, 0, 5], [0.5, 0, 0], [0.75, 0, 5], [1, 0, 0]]), rotate: rotate([[0, -3], [0.25, 4], [0.5, -3], [0.75, 4], [1, -3]]) },
      chest: { rotate: rotate([[0, 3], [0.25, -3], [0.5, 3], [0.75, -3], [1, 3]]) },
      left_thigh: { rotate: rotate([[0, -108], [0.25, -92], [0.5, -78], [0.75, -100], [1, -108]]) },
      left_shin: { rotate: rotate([[0, 18], [0.25, 6], [0.5, -12], [0.75, 20], [1, 18]]) },
      right_thigh: { rotate: rotate([[0, -72], [0.25, -90], [0.5, -108], [0.75, -88], [1, -72]]) },
      right_shin: { rotate: rotate([[0, -18], [0.25, -6], [0.5, 12], [0.75, -20], [1, -18]]) },
      left_upper_arm: { rotate: rotate([[0, 44], [0.5, 10], [1, 44]]) },
      right_upper_arm: { rotate: rotate([[0, -10], [0.5, -44], [1, -10]]) },
    },
  },
  walk_side: {
    bones: {
      pelvis_root: { translate: translate([[0, 0, 0], [0.25, 0, 4], [0.5, 0, 0], [0.75, 0, 4], [1, 0, 0]]), rotate: rotate([[0, -5], [0.25, 5], [0.5, -5], [0.75, 5], [1, -5]]) },
      chest: { rotate: rotate([[0, 6], [0.25, -5], [0.5, 6], [0.75, -5], [1, 6]]) },
      arms: { rotate: rotate([[0, -8], [0.5, 8], [1, -8]]) },
      legs: { rotate: rotate([[0, 4], [0.5, -4], [1, 4]]) },
      left_thigh: { rotate: rotate([[0, -200], [0.25, -178], [0.5, -150], [0.75, -182], [1, -200]]) },
      left_shin: { rotate: rotate([[0, 24], [0.25, 6], [0.5, -18], [0.75, 26], [1, 24]]) },
      right_thigh: { rotate: rotate([[0, -146], [0.25, -168], [0.5, -196], [0.75, -162], [1, -146]]) },
      right_shin: { rotate: rotate([[0, -20], [0.25, -8], [0.5, 16], [0.75, -24], [1, -20]]) },
      left_upper_arm: { rotate: rotate([[0, 56], [0.5, 14], [1, 56]]) },
      right_upper_arm: { rotate: rotate([[0, -8], [0.5, -52], [1, -8]]) },
    },
  },
  walk_side_v2: {
    bones: {
      pelvis_root: {
        translate: translate([[walkFrames[0], 0, 0], [walkFrames[1], 0, 5], [walkFrames[2], 0, 0], [walkFrames[3], 0, 5], [walkFrames[4], 0, 0]]),
        rotate: rotate([[walkFrames[0], -3], [walkFrames[1], 2], [walkFrames[2], 4], [walkFrames[3], -2], [walkFrames[4], -3]]),
      },
      abdomen: { rotate: rotate([[walkFrames[0], 2], [walkFrames[1], 0], [walkFrames[2], -2], [walkFrames[3], 0], [walkFrames[4], 2]]) },
      chest: { rotate: rotate([[walkFrames[0], 5], [walkFrames[1], 0], [walkFrames[2], -5], [walkFrames[3], 0], [walkFrames[4], 5]]) },
      neck: { rotate: rotate([[walkFrames[0], -2], [walkFrames[1], 0], [walkFrames[2], 2], [walkFrames[3], 0], [walkFrames[4], -2]]) },
      head: {
        translate: translate([[walkFrames[0], 0, 0], [walkFrames[1], 0, -2], [walkFrames[2], 0, 0], [walkFrames[3], 0, -2], [walkFrames[4], 0, 0]]),
        rotate: rotate([[walkFrames[0], -1], [walkFrames[1], 0], [walkFrames[2], 1], [walkFrames[3], 0], [walkFrames[4], -1]]),
      },
      legs: { rotate: rotate([[walkFrames[0], 2], [walkFrames[1], 0], [walkFrames[2], -2], [walkFrames[3], 0], [walkFrames[4], 2]]) },
      left_thigh: { rotate: rotate([[walkFrames[0], -150], [walkFrames[1], -172], [walkFrames[2], -198], [walkFrames[3], -185], [walkFrames[4], -150]]) },
      left_shin: { rotate: rotate([[walkFrames[0], -10], [walkFrames[1], 18], [walkFrames[2], 28], [walkFrames[3], 8], [walkFrames[4], -10]]) },
      left_foot: {
        translate: translate([[walkFrames[0], 0, 4], [walkFrames[1], 0, 0], [walkFrames[2], 0, 0], [walkFrames[3], 0, 8], [walkFrames[4], 0, 4]]),
        rotate: rotate([[walkFrames[0], 6], [walkFrames[1], 0], [walkFrames[2], -8], [walkFrames[3], 10], [walkFrames[4], 6]]),
      },
      right_thigh: { rotate: rotate([[walkFrames[0], -198], [walkFrames[1], -185], [walkFrames[2], -150], [walkFrames[3], -172], [walkFrames[4], -198]]) },
      right_shin: { rotate: rotate([[walkFrames[0], 28], [walkFrames[1], 8], [walkFrames[2], -10], [walkFrames[3], 18], [walkFrames[4], 28]]) },
      right_foot: {
        translate: translate([[walkFrames[0], 0, 0], [walkFrames[1], 0, 8], [walkFrames[2], 0, 4], [walkFrames[3], 0, 0], [walkFrames[4], 0, 0]]),
        rotate: rotate([[walkFrames[0], -8], [walkFrames[1], 10], [walkFrames[2], 6], [walkFrames[3], 0], [walkFrames[4], -8]]),
      },
      arms: { rotate: rotate([[walkFrames[0], -3], [walkFrames[1], 0], [walkFrames[2], 3], [walkFrames[3], 0], [walkFrames[4], -3]]) },
      left_upper_arm: { rotate: rotate([[walkFrames[0], 8], [walkFrames[1], 28], [walkFrames[2], 52], [walkFrames[3], 28], [walkFrames[4], 8]]) },
      left_forearm: { rotate: rotate([[walkFrames[0], -22], [walkFrames[1], -14], [walkFrames[2], -8], [walkFrames[3], -16], [walkFrames[4], -22]]) },
      left_hand: {
        translate: translate([[walkFrames[0], 0, 0], [walkFrames[1], 1, 1], [walkFrames[2], 0, 2], [walkFrames[3], -1, 1], [walkFrames[4], 0, 0]]),
        rotate: rotate([[walkFrames[0], -6], [walkFrames[1], -2], [walkFrames[2], 4], [walkFrames[3], -2], [walkFrames[4], -6]]),
      },
      right_upper_arm: { rotate: rotate([[walkFrames[0], -52], [walkFrames[1], -28], [walkFrames[2], -8], [walkFrames[3], -28], [walkFrames[4], -52]]) },
      right_forearm: { rotate: rotate([[walkFrames[0], 8], [walkFrames[1], 16], [walkFrames[2], 22], [walkFrames[3], 14], [walkFrames[4], 8]]) },
      right_hand: {
        translate: translate([[walkFrames[0], 0, 2], [walkFrames[1], -1, 1], [walkFrames[2], 0, 0], [walkFrames[3], 1, 1], [walkFrames[4], 0, 2]]),
        rotate: rotate([[walkFrames[0], 4], [walkFrames[1], -2], [walkFrames[2], -6], [walkFrames[3], -2], [walkFrames[4], 4]]),
      },
    },
  },
  walk_side_v3: {
    bones: {
      pelvis_root: {
        translate: translate([[walkFrames[0], 0, -3], [walkFrames[1], 0, 4], [walkFrames[2], 0, -3], [walkFrames[3], 0, 4], [walkFrames[4], 0, -3]]),
        rotate: rotate([[walkFrames[0], -2], [walkFrames[1], 0], [walkFrames[2], 2], [walkFrames[3], 0], [walkFrames[4], -2]]),
      },
      abdomen: { rotate: rotate([[walkFrames[0], 1], [walkFrames[1], 0], [walkFrames[2], -1], [walkFrames[3], 0], [walkFrames[4], 1]]) },
      chest: { rotate: rotate([[walkFrames[0], 4], [walkFrames[1], 0], [walkFrames[2], -4], [walkFrames[3], 0], [walkFrames[4], 4]]) },
      neck: { rotate: rotate([[walkFrames[0], -1], [walkFrames[1], 0], [walkFrames[2], 1], [walkFrames[3], 0], [walkFrames[4], -1]]) },
      head: {
        translate: translate([[walkFrames[0], 0, 1], [walkFrames[1], 0, -2], [walkFrames[2], 0, 1], [walkFrames[3], 0, -2], [walkFrames[4], 0, 1]]),
        rotate: rotate([[walkFrames[0], -1], [walkFrames[1], 0], [walkFrames[2], 1], [walkFrames[3], 0], [walkFrames[4], -1]]),
      },
      legs: { rotate: rotate([[walkFrames[0], 1], [walkFrames[1], 0], [walkFrames[2], -1], [walkFrames[3], 0], [walkFrames[4], 1]]) },
      left_thigh: { rotate: rotate([[walkFrames[0], -142], [walkFrames[1], -176], [walkFrames[2], -214], [walkFrames[3], -164], [walkFrames[4], -142]]) },
      left_shin: { rotate: rotate([[walkFrames[0], -14], [walkFrames[1], 14], [walkFrames[2], 22], [walkFrames[3], 46], [walkFrames[4], -14]]) },
      left_foot: {
        translate: translate([[walkFrames[0], 0, 0], [walkFrames[1], 0, 0], [walkFrames[2], 0, 0], [walkFrames[3], 0, 13], [walkFrames[4], 0, 0]]),
        rotate: rotate([[walkFrames[0], 0], [walkFrames[1], -4], [walkFrames[2], -22], [walkFrames[3], 12], [walkFrames[4], 0]]),
      },
      right_thigh: { rotate: rotate([[walkFrames[0], -214], [walkFrames[1], -164], [walkFrames[2], -142], [walkFrames[3], -176], [walkFrames[4], -214]]) },
      right_shin: { rotate: rotate([[walkFrames[0], 22], [walkFrames[1], 46], [walkFrames[2], -14], [walkFrames[3], 14], [walkFrames[4], 22]]) },
      right_foot: {
        translate: translate([[walkFrames[0], 0, 0], [walkFrames[1], 0, 13], [walkFrames[2], 0, 0], [walkFrames[3], 0, 0], [walkFrames[4], 0, 0]]),
        rotate: rotate([[walkFrames[0], -22], [walkFrames[1], 12], [walkFrames[2], 0], [walkFrames[3], -4], [walkFrames[4], -22]]),
      },
      arms: { rotate: rotate([[walkFrames[0], -2], [walkFrames[1], 0], [walkFrames[2], 2], [walkFrames[3], 0], [walkFrames[4], -2]]) },
      left_upper_arm: { rotate: rotate([[walkFrames[0], 52], [walkFrames[1], 24], [walkFrames[2], 4], [walkFrames[3], 24], [walkFrames[4], 52]]) },
      left_forearm: { rotate: rotate([[walkFrames[0], -10], [walkFrames[1], -14], [walkFrames[2], -24], [walkFrames[3], -14], [walkFrames[4], -10]]) },
      left_hand: {
        translate: translate([[walkFrames[0], 0, 2], [walkFrames[1], 0, 1], [walkFrames[2], 0, 0], [walkFrames[3], 0, 1], [walkFrames[4], 0, 2]]),
        rotate: rotate([[walkFrames[0], 5], [walkFrames[1], 0], [walkFrames[2], -6], [walkFrames[3], 0], [walkFrames[4], 5]]),
      },
      right_upper_arm: { rotate: rotate([[walkFrames[0], -8], [walkFrames[1], -28], [walkFrames[2], -56], [walkFrames[3], -28], [walkFrames[4], -8]]) },
      right_forearm: { rotate: rotate([[walkFrames[0], 24], [walkFrames[1], 14], [walkFrames[2], 8], [walkFrames[3], 14], [walkFrames[4], 24]]) },
      right_hand: {
        translate: translate([[walkFrames[0], 0, 0], [walkFrames[1], 0, 1], [walkFrames[2], 0, 2], [walkFrames[3], 0, 1], [walkFrames[4], 0, 0]]),
        rotate: rotate([[walkFrames[0], -6], [walkFrames[1], 0], [walkFrames[2], 5], [walkFrames[3], 0], [walkFrames[4], -6]]),
      },
    },
  },
  jab: {
    bones: {
      pelvis_root: { translate: translate([[0, 0, 0], [0.12, 8, 0], [0.32, 0, 0]]), rotate: rotate([[0, 0], [0.12, -4], [0.32, 0]]) },
      chest: { rotate: rotate([[0, 0], [0.1, -8], [0.32, 0]]) },
      left_upper_arm: { rotate: rotate([[0, 24], [0.08, -8], [0.16, -12], [0.32, 24]]) },
      left_forearm: { rotate: rotate([[0, -6], [0.08, 2], [0.16, 4], [0.32, -6]]) },
      left_hand: { translate: translate([[0, 0, 0], [0.12, 8, 0], [0.32, 0, 0]]) },
      right_upper_arm: { rotate: rotate([[0, -24], [0.12, -40], [0.32, -24]]) },
    },
  },
  jab_turn: {
    bones: {
      pelvis_root: { translate: translate([[0, 0, 0], [0.1, 9, 1], [0.22, 14, 0], [0.4, 0, 0]]), rotate: rotate([[0, 0], [0.1, -7], [0.22, -10], [0.4, 0]]) },
      abdomen: { rotate: rotate([[0, 0], [0.1, -4], [0.22, -7], [0.4, 0]]) },
      chest: { rotate: rotate([[0, 0], [0.1, -12], [0.22, -16], [0.4, 0]]) },
      arms: { rotate: rotate([[0, 0], [0.1, -10], [0.22, -14], [0.4, 0]]) },
      left_upper_arm: { rotate: rotate([[0, 24], [0.08, -8], [0.18, -18], [0.4, 24]]) },
      left_forearm: { rotate: rotate([[0, -7], [0.08, 3], [0.18, 7], [0.4, -7]]) },
      left_hand: { translate: translate([[0, 0, 0], [0.16, 12, 0], [0.4, 0, 0]]) },
      right_upper_arm: { rotate: rotate([[0, -18], [0.16, -52], [0.4, -18]]) },
      left_thigh: { rotate: rotate([[0, -180], [0.18, -188], [0.4, -180]]) },
      right_thigh: { rotate: rotate([[0, -168], [0.18, -156], [0.4, -168]]) },
    },
  },
  hurt: {
    bones: {
      pelvis_root: { translate: translate([[0, 0, 0], [0.1, -14, 5], [0.42, 0, 0]]), rotate: rotate([[0, 0], [0.1, 7], [0.42, 0]]) },
      abdomen: { rotate: rotate([[0, 0], [0.1, -6], [0.42, 0]]) },
      chest: { rotate: rotate([[0, 0], [0.1, 14], [0.42, 0]]) },
      head: { rotate: rotate([[0, 0], [0.1, 12], [0.42, 0]]) },
      left_upper_arm: { rotate: rotate([[0, 24], [0.1, 52], [0.42, 24]]) },
      right_upper_arm: { rotate: rotate([[0, -24], [0.1, -5], [0.42, -24]]) },
    },
  },
  joint_debug: {
    bones: {
      pelvis_root: { rotate: rotate([[0, 0], [0.25, -10], [0.5, 10], [0.75, 0]]) },
      abdomen: { rotate: rotate([[0, 0], [0.25, 10], [0.5, -10], [0.75, 0]]) },
      chest: { rotate: rotate([[0, 0], [0.25, -12], [0.5, 12], [0.75, 0]]) },
      neck: { rotate: rotate([[0, 0], [0.25, 10], [0.5, -10], [0.75, 0]]) },
      head: { rotate: rotate([[0, 0], [0.25, -12], [0.5, 12], [0.75, 0]]) },
      left_upper_arm: { rotate: rotate([[0, 24], [0.25, 54], [0.5, 4], [0.75, 24]]) },
      left_forearm: { rotate: rotate([[0, -7], [0.25, -42], [0.5, 22], [0.75, -7]]) },
      right_upper_arm: { rotate: rotate([[0, -18], [0.25, -48], [0.5, 8], [0.75, -18]]) },
      right_forearm: { rotate: rotate([[0, 5], [0.25, 38], [0.5, -20], [0.75, 5]]) },
      left_thigh: { rotate: rotate([[0, -180], [0.25, -206], [0.5, -154], [0.75, -180]]) },
      left_shin: { rotate: rotate([[0, 7], [0.25, 34], [0.5, -18], [0.75, 7]]) },
      right_thigh: { rotate: rotate([[0, -168], [0.25, -142], [0.5, -194], [0.75, -168]]) },
      right_shin: { rotate: rotate([[0, -9], [0.25, -34], [0.5, 16], [0.75, -9]]) },
    },
  },
};

const skeleton = {
  skeleton: {
    hash: "codex-humanoid-combat-v3",
    spine: "4.3.02",
    x: -150,
    y: 0,
    width: 300,
    height: 528,
    images: "../images/",
    audio: "",
  },
  bones,
  slots,
  skins: [
    {
      name: "default",
      attachments: attach,
    },
  ],
  animations,
};
fs.writeFileSync(path.join(exportDir, "humanoid-combat.json"), JSON.stringify(skeleton, null, 2));

const manifest = {
  name: "humanoid-combat",
  note: "Runtime-ready Spine JSON/atlas export. Open humanoid-combat.json in Spine to save a proprietary .spine editor file if needed.",
  proportions: {
    totalHeightPx: 528,
    headHeightPx: 70,
    headsTall: 7.54,
    pose: "neutral 30-45 degree three-quarter combat stance with grounded feet",
    style: "average adult male, realistic non-superhero proportions",
  },
  files: {
    json: "export/humanoid-combat.json",
    atlas: "export/humanoid-combat.atlas",
    atlasPng: "export/humanoid-combat.png",
    sourceImages: "images/*.png",
  },
  animations: Object.keys(animations),
};
fs.writeFileSync(path.join(projectDir, "humanoid-combat.spine-project.json"), JSON.stringify(manifest, null, 2));

const readme = `# Spine Humanoid Combat Rig

This folder contains a Spine-runtime-ready humanoid character export for combat animation experiments.

## Runtime Files

- \`export/humanoid-combat.json\` - Spine JSON skeleton export, marked as Spine 4.3.02-compatible JSON.
- \`export/humanoid-combat.atlas\` - PNG atlas descriptor.
- \`export/humanoid-combat.png\` - packed atlas page.
- \`images/*.png\` - individual segmented source body pieces.
- \`humanoid-combat.spine-project.json\` - reproducible project manifest and notes.

## Rig Notes

- Average adult male proportions, approximately 7.5 heads tall.
- Longer lower body: legs occupy nearly half the body height.
- Neutral relaxed A-pose tuned for a 30-45 degree three-quarter combat stance.
- Side-biased movement and attack tests are provided in \`walk_side\` and \`jab_turn\`.
- \`walk_side_v3\` is a rough pose-driven walk cycle: thighs, shins, feet, arms, pelvis, and chest are keyed to test actual limb motion rather than foot sliding.
- \`root_master\` is the world/gameplay root at the ground line between the feet.
- \`pelvis_root\` handles body motion above the gameplay root.
- Spine chain: \`pelvis_root -> abdomen -> chest -> neck -> head\`, with local bone axes pointing up the torso chain.
- Arm grouping: \`chest -> arms -> shoulder -> upper_arm -> forearm -> hand\`.
- Leg grouping: \`pelvis_root -> legs -> thigh -> shin -> foot\`.
- Feet are authored to sit on the y=0 baseline in the setup pose.
- Shoulder and hip cap pieces overlap the limbs and torso to avoid visible gaps during early rotation tests.

## Placeholder Animations

- \`idle\`
- \`idle_3q\`
- \`walk\`
- \`walk_side\`
- \`walk_side_v2\`
- \`walk_side_v3\`
- \`jab\`
- \`jab_turn\`
- \`hurt\`
- \`joint_debug\`

The animations are intentionally plain. They are there to validate hierarchy, pivots, silhouette, and Spine-to-Godot import.

## Spine Editor Note

Spine's native \`.spine\` editor file is a proprietary save format. This package provides the portable Spine JSON/atlas/PNG structure that the Spine editor and spine-godot runtime can consume. To create a native \`.spine\` file, import \`export/humanoid-combat.json\` into Spine and save it from the editor.
`;
fs.writeFileSync(path.join(projectDir, "README.md"), readme);

console.log(`Generated ${projectDir}`);
