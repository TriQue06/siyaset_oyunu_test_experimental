// Siyaset Oyunu - oda kodu tabanli WebSocket role (relay) sunucusu.
//
// Bu sunucu oyunun kendisini calistirmiyor; sadece ayni oda koduna sahip
// istemciler arasinda ham baytlari iletiyor. CGNAT / statik IP olmadan
// (port yonlendirme yapilamayan durumlarda) oyuncularin birbirine
// baglanabilmesini saglar. Oyun mantigi hala "host" oyuncunun
// bilgisayarinda (peer id = 1) calisir; bu sunucu sadece bir posta kutusu.
//
// Kablo protokolu (her WebSocket binary frame'inin ilk baytı tip):
//   0 CREATE_ROOM  (client->server) payload: isim (utf8)
//   1 JOIN_ROOM    (client->server) payload: 5 bayt kod + isim (utf8)
//   2 ROOM_OK      (server->client) payload: 5 bayt kod + peerId(4 LE) + isHost(1)
//   3 ROOM_ERR     (server->client) payload: sebep (utf8)
//   4 PEER_CONNECTED    (server->client) payload: peerId(4 LE)
//   5 PEER_DISCONNECTED (server->client) payload: peerId(4 LE)
//   6 DATA (client->server) payload: targetPeer(4 LE signed) + oyun verisi
//     DATA (server->client) payload: senderPeer(4 LE) + oyun verisi
//   7 ROOM_CLOSED  (server->client) payload: sebep (utf8)

const { WebSocketServer } = require("ws");

const PORT = process.env.PORT || 8080;
const MAX_PEERS_PER_ROOM = 8;
const CODE_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
const CODE_LENGTH = 5;

const TYPE = {
  CREATE_ROOM: 0,
  JOIN_ROOM: 1,
  ROOM_OK: 2,
  ROOM_ERR: 3,
  PEER_CONNECTED: 4,
  PEER_DISCONNECTED: 5,
  DATA: 6,
  ROOM_CLOSED: 7,
};

/** @type {Map<string, Room>} */
const rooms = new Map();

class Room {
  constructor(code) {
    this.code = code;
    /** @type {Map<number, import('ws').WebSocket>} */
    this.peers = new Map();
    this.nextPeerId = 1;
  }
}

function randomCode() {
  let code = "";
  for (let i = 0; i < CODE_LENGTH; i++) {
    code += CODE_ALPHABET[Math.floor(Math.random() * CODE_ALPHABET.length)];
  }
  return code;
}

function newRoomCode() {
  let code = randomCode();
  while (rooms.has(code)) {
    code = randomCode();
  }
  return code;
}

function sendErr(ws, reason) {
  const body = Buffer.from(reason, "utf8");
  const frame = Buffer.concat([Buffer.from([TYPE.ROOM_ERR]), body]);
  ws.send(frame);
}

function sendOk(ws, code, peerId, isHost) {
  const frame = Buffer.alloc(1 + CODE_LENGTH + 4 + 1);
  frame.writeUInt8(TYPE.ROOM_OK, 0);
  frame.write(code, 1, CODE_LENGTH, "ascii");
  frame.writeInt32LE(peerId, 1 + CODE_LENGTH);
  frame.writeUInt8(isHost ? 1 : 0, 1 + CODE_LENGTH + 4);
  ws.send(frame);
}

function broadcastPeerEvent(room, type, peerId, exceptWs) {
  const frame = Buffer.alloc(5);
  frame.writeUInt8(type, 0);
  frame.writeInt32LE(peerId, 1);
  for (const [, peerWs] of room.peers) {
    if (peerWs !== exceptWs && peerWs.readyState === peerWs.OPEN) {
      peerWs.send(frame);
    }
  }
}

function closeRoom(room, reason) {
  const body = Buffer.from(reason, "utf8");
  const frame = Buffer.concat([Buffer.from([TYPE.ROOM_CLOSED]), body]);
  for (const [, peerWs] of room.peers) {
    if (peerWs.readyState === peerWs.OPEN) {
      peerWs.send(frame);
      peerWs.close();
    }
  }
  rooms.delete(room.code);
}

function handleCreate(ws, payload) {
  if (ws.roomCode) return;
  const room = new Room(newRoomCode());
  const peerId = room.nextPeerId++; // host her zaman 1
  room.peers.set(peerId, ws);
  rooms.set(room.code, room);

  ws.roomCode = room.code;
  ws.peerId = peerId;
  ws.isHost = true;

  sendOk(ws, room.code, peerId, true);
}

function handleJoin(ws, payload) {
  if (ws.roomCode) return;
  if (payload.length < CODE_LENGTH) {
    sendErr(ws, "Gecersiz istek.");
    return;
  }
  const code = payload.toString("ascii", 0, CODE_LENGTH).toUpperCase();
  const room = rooms.get(code);
  if (!room) {
    sendErr(ws, "Oda bulunamadi.");
    return;
  }
  if (room.peers.size >= MAX_PEERS_PER_ROOM) {
    sendErr(ws, "Oda dolu.");
    return;
  }

  const peerId = room.nextPeerId++;
  ws.roomCode = room.code;
  ws.peerId = peerId;
  ws.isHost = false;

  // Yeni oyuncuya: kendi id'si + odadaki mevcut herkesin id'si (peer_connected sinyali icin).
  sendOk(ws, room.code, peerId, false);
  for (const [existingId] of room.peers) {
    const frame = Buffer.alloc(5);
    frame.writeUInt8(TYPE.PEER_CONNECTED, 0);
    frame.writeInt32LE(existingId, 1);
    ws.send(frame);
  }

  room.peers.set(peerId, ws);
  broadcastPeerEvent(room, TYPE.PEER_CONNECTED, peerId, ws);
}

function handleData(ws, payload) {
  const room = rooms.get(ws.roomCode);
  if (!room) return;
  if (payload.length < 4) return;

  const target = payload.readInt32LE(0);
  const gameData = payload.subarray(4);

  const outFrame = Buffer.concat([
    Buffer.from([TYPE.DATA]),
    (() => {
      const b = Buffer.alloc(4);
      b.writeInt32LE(ws.peerId, 0);
      return b;
    })(),
    gameData,
  ]);

  if (target === 0) {
    for (const [id, peerWs] of room.peers) {
      if (id !== ws.peerId && peerWs.readyState === peerWs.OPEN) peerWs.send(outFrame);
    }
  } else if (target < 0) {
    const excluded = -target;
    for (const [id, peerWs] of room.peers) {
      if (id !== ws.peerId && id !== excluded && peerWs.readyState === peerWs.OPEN) {
        peerWs.send(outFrame);
      }
    }
  } else {
    const peerWs = room.peers.get(target);
    if (peerWs && peerWs.readyState === peerWs.OPEN) peerWs.send(outFrame);
  }
}

function handleClose(ws) {
  if (!ws.roomCode) return;
  const room = rooms.get(ws.roomCode);
  if (!room) return;

  room.peers.delete(ws.peerId);

  if (ws.isHost) {
    closeRoom(room, "Oda sahibi ayrildi.");
    return;
  }

  if (room.peers.size === 0) {
    rooms.delete(room.code);
    return;
  }

  broadcastPeerEvent(room, TYPE.PEER_DISCONNECTED, ws.peerId, ws);
}

const wss = new WebSocketServer({ port: PORT });

wss.on("connection", (ws) => {
  ws.roomCode = null;
  ws.peerId = 0;
  ws.isHost = false;

  ws.on("message", (data) => {
    if (!Buffer.isBuffer(data) || data.length < 1) return;
    const type = data.readUInt8(0);
    const payload = data.subarray(1);

    switch (type) {
      case TYPE.CREATE_ROOM:
        handleCreate(ws, payload);
        break;
      case TYPE.JOIN_ROOM:
        handleJoin(ws, payload);
        break;
      case TYPE.DATA:
        handleData(ws, payload);
        break;
      default:
        break;
    }
  });

  ws.on("close", () => handleClose(ws));
  ws.on("error", () => {});
});

console.log(`Siyaset Oyunu role sunucusu ${PORT} portunda calisiyor.`);
