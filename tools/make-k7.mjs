#!/usr/bin/env node
import fs from "node:fs";

/*
 * Wrap a DECB LOADM payload in Thomson K7 blocks.
 *
 * Block layout emitted here:
 *   leader:  DC followed by fifteen 01 bytes
 *   marker:  3C 5A
 *   header:  block type and body length including framing bytes
 *   body:    at most 254 bytes
 *   trailer: two's-complement checksum of the body
 *
 * Type 00 carries the padded 8.3 file metadata, type 01 carries payload
 * chunks, and type FF terminates the cassette file.
 */
const [, , payloadPath, k7Path, nameArg = "TUTANKHM"] = process.argv;

if (!payloadPath || !k7Path) {
  console.error("usage: make-k7.mjs payload.bin output.k7 [name]");
  process.exit(1);
}

const payload = fs.readFileSync(payloadPath);
const output = [];

function pushBytes(bytes) {
  for (const byte of bytes) {
    output.push(byte & 0xff);
  }
}

function asciiPadded(text, length) {
  // Thomson cassette metadata uses uppercase, space-padded ASCII fields.
  const bytes = Buffer.from(text.toUpperCase(), "ascii");
  const result = new Array(length).fill(0x20);

  for (let index = 0; index < Math.min(bytes.length, length); index += 1) {
    result[index] = bytes[index];
  }

  return result;
}

function leader() {
  pushBytes([0xdc]);
  pushBytes(new Array(15).fill(0x01));
}

function checksum(body) {
  // The body and returned checksum sum to zero modulo 256.
  let sum = 0;

  for (const byte of body) {
    sum = (sum + byte) & 0xff;
  }

  return (-sum) & 0xff;
}

function block(type, body) {
  if (body.length > 254) {
    throw new Error("K7 block body is limited to 254 bytes");
  }

  leader();
  pushBytes([0x3c, 0x5a, type, (body.length + 2) & 0xff]);
  pushBytes(body);
  pushBytes([checksum(body)]);
}

const fileName = asciiPadded(nameArg, 8);
const extension = asciiPadded("BIN", 3);

block(0x00, [...fileName, ...extension, 0x02, 0x00, 0x00]);

for (let offset = 0; offset < payload.length; offset += 254) {
  block(0x01, [...payload.subarray(offset, offset + 254)]);
}

block(0xff, []);

fs.writeFileSync(k7Path, Buffer.from(output));
