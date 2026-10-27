const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");

// Exercise the production packet routing without opening a public listener.
function relayFixture() {
  const context = {
    Buffer, process: { env: {} }, console: { log() {} },
    setInterval() { return 1; }, clearInterval() {},
    require(name) {
      if (name === "http") return { createServer() { return { listen() {} }; } };
      if (name === "ws") return { WebSocketServer: class { on() {} } };
      throw new Error(`Unexpected dependency: ${name}`);
    },
  };
  vm.runInNewContext(fs.readFileSync(`${__dirname}/server.js`, "utf8") +
    "\nglobalThis.fixture = { rooms, Room, handleData };", context);
  const { rooms, Room, handleData } = context.fixture;
  const room = new Room("TESTS");
  rooms.set(room.code, room);
  const peers = [1, 2, 3, 4].map(peerId => ({
    peerId, roomCode: room.code, OPEN: 1, readyState: 1, frames: [],
    send(frame) { this.frames.push(frame); },
  }));
  for (const peer of peers) room.peers.set(peer.peerId, peer);
  return { peers, handleData };
}

test("relay preserves exact bytes, sender and routing for a packet burst", () => {
  const { peers, handleData } = relayFixture();
  for (let i = 0; i < 4096; i++) {
    const body = Buffer.alloc(i % 1024, i % 256);
    const payload = Buffer.alloc(4 + body.length);
    payload.writeInt32LE(0);
    body.copy(payload, 4);
    handleData(peers[0], payload);
    for (const recipient of peers.slice(1)) {
      const frame = recipient.frames[i];
      assert.equal(frame[0], 6);
      assert.equal(frame.readInt32LE(1), 1);
      assert.deepEqual(frame.subarray(5), body);
    }
  }
  assert.equal(peers[0].frames.length, 0);
  const targeted = Buffer.alloc(4);
  targeted.writeInt32LE(3);
  handleData(peers[1], targeted);
  assert.equal(peers[2].frames.at(-1).readInt32LE(1), 2);
  assert.equal(peers[1].frames.length, 4096);
  targeted.writeInt32LE(-3);
  handleData(peers[1], targeted);
  assert.equal(peers[0].frames.length, 1);
  assert.equal(peers[2].frames.length, 4097);
  assert.equal(peers[3].frames.length, 4097);
});
