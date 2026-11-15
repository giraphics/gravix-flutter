import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  COMMAND_PAUSE,
  decodeServerMessage,
  encodeControl,
  type SimMap,
  type SimSnapshot,
} from '../src/lib/simproto.ts';

// Hand-built frames, byte for byte what prost writes for these messages.

function varintBytes(n: number): number[] {
  const out: number[] = [];
  let v = n;
  while (v >= 128) {
    out.push((v % 128) | 0x80);
    v = Math.floor(v / 128);
  }
  out.push(v);
  return out;
}
const f32 = (n: number): number[] => [...new Uint8Array(new Float32Array([n]).buffer)];
const f64 = (n: number): number[] => [...new Uint8Array(new Float64Array([n]).buffer)];
const field = (num: number, wire: number): number[] => varintBytes(num * 8 + wire);
const lenField = (num: number, body: number[]): number[] => [
  ...field(num, 2),
  ...varintBytes(body.length),
  ...body,
];

test('decodes a map frame', () => {
  const node = (id: number, x: number, y: number): number[] => [
    ...field(1, 0), ...varintBytes(id),
    ...field(2, 5), ...f32(x),
    ...field(3, 5), ...f32(y),
  ];
  const edge = (from: number, to: number): number[] => [
    ...field(1, 0), ...varintBytes(from),
    ...field(2, 0), ...varintBytes(to),
  ];
  const map = [
    ...lenField(1, node(0, 0, 0)),
    ...lenField(1, node(1, 100, 0)),
    ...lenField(2, edge(0, 1)),
    ...lenField(2, edge(1, 0)),
  ];
  const frame = Uint8Array.from(lenField(1, map));
  const msg = decodeServerMessage(frame) as SimMap;
  assert.equal(msg.kind, 'map');
  assert.deepEqual([...msg.nodeX], [0, 100]);
  assert.deepEqual([...msg.nodeY], [0, 0]);
  assert.deepEqual([...msg.edgeFrom], [0, 1]);
  assert.deepEqual([...msg.edgeTo], [1, 0]);
});

test('decodes a snapshot frame, including large varints and a zero field', () => {
  const sentAt = 1_794_000_000_123_456; // microseconds, above 2^32
  const vehicle = (id: number, x: number, y: number, h: number, s: number): number[] => [
    ...(id ? [...field(1, 0), ...varintBytes(id)] : []),
    ...field(2, 5), ...f32(x),
    ...(y ? [...field(3, 5), ...f32(y)] : []), // proto3 omits 0.0
    ...field(4, 5), ...f32(h),
    ...field(5, 5), ...f32(s),
  ];
  const snap = [
    ...field(1, 0), ...varintBytes(7),
    ...field(2, 1), ...f64(0.35),
    ...field(3, 0), ...varintBytes(sentAt),
    ...lenField(4, vehicle(1, 10.5, 20.25, 1.5, 12)),
    ...lenField(4, vehicle(0, 5, 0, 0, 9)),
  ];
  const msg = decodeServerMessage(Uint8Array.from(lenField(2, snap))) as SimSnapshot;
  assert.equal(msg.kind, 'snapshot');
  assert.equal(msg.tick, 7);
  assert.ok(Math.abs(msg.simTimeS - 0.35) < 1e-12);
  assert.equal(msg.sentAtMicros, sentAt);
  assert.equal(msg.count, 2);
  assert.deepEqual([...msg.x], [10.5, 5]);
  assert.deepEqual([...msg.y], [20.25, 0]);
  assert.deepEqual([...msg.speed], [12, 9]);
});

test('ignores unknown fields', () => {
  const snap = [
    ...field(1, 0), ...varintBytes(3),
    ...field(99, 0), ...varintBytes(5), // a field this decoder has never heard of
    ...lenField(98, [1, 2, 3]),
  ];
  const msg = decodeServerMessage(Uint8Array.from(lenField(2, snap))) as SimSnapshot;
  assert.equal(msg.tick, 3);
  assert.equal(msg.count, 0);
});

test('an empty frame decodes to nothing', () => {
  assert.equal(decodeServerMessage(new Uint8Array(0)), null);
});

test('a truncated frame throws instead of reading past the end', () => {
  const good = lenField(2, [...field(1, 0), ...varintBytes(300)]);
  assert.throws(() => decodeServerMessage(Uint8Array.from(good.slice(0, good.length - 1))));
});

test('control messages encode as field 1', () => {
  assert.deepEqual([...encodeControl(COMMAND_PAUSE)], [0x08, 0x01]);
});
