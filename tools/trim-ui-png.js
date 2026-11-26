'use strict';

const {execFile} = require('node:child_process');

function run(command, args, bytes, maxBuffer) {
 return new Promise((resolve, reject) => {
  const child = execFile(command, ['-limit', 'thread', '2', ...args], {
   encoding: 'buffer', maxBuffer, timeout: 120_000,
  }, (error, stdout) => error ? reject(error) : resolve(stdout));
  child.stdin.on('error', reject);
  child.stdin.end(bytes);
 });
}

async function imageMagick(args, bytes, maxBuffer) {
 for (const command of ['magick', 'convert']) {
  try {
   return await run(command, args, bytes, maxBuffer);
  } catch (error) {
   if (error.code !== 'ENOENT') throw error;
  }
 }
 throw new Error('--trim requires ImageMagick (magick or convert on PATH)');
}

async function trimPng(bytes, size, maxBytes) {
 // Keep visible white artwork on transparent canvases. On opaque canvases,
 // use white as the background. A black border stabilizes the mask bounds.
 const maskBounds = ['-threshold', '0', '-bordercolor', 'black', '-border', '1', '-format', '%@', 'info:'];
 const alpha = await imageMagick([
  'png:-', '+repage', '-format', '%[opaque] ', '-write', 'info:',
  '-alpha', 'extract', ...maskBounds,
 ], bytes, 1024);
 const [opaque, alphaBounds] = alpha.toString().trim().split(/\s+/);
 const bounds = opaque === 'true' ? (await imageMagick([
  'png:-', '+repage', '-colorspace', 'gray', '-negate', ...maskBounds,
 ], bytes, 1024)).toString().trim() : alphaBounds;
 const match = /^(\d+)x(\d+)\+(-?\d+)\+(-?\d+)$/.exec(bounds);
 if (!match) throw new Error('Could not determine PNG trim bounds');
 const [, width, height, left, top] = match.map(Number);
 if (!width || !height || (width === size.width && height === size.height)) return bytes;

 // Crop the original pixels, including any white or transparent pixels inside the bounds.
 const crop = `${width}x${height}+${left - 1}+${top - 1}`;
 return imageMagick(['png:-', '+repage', '-crop', crop, '+repage', 'png:-'], bytes, maxBytes);
}

module.exports = {trimPng};
