// Cloudflare entry point. The Worker sends each WebSocket to the Durable
// Object for its room (one per code), and the room passes packets between
// the people in it. Sockets use the hibernation API, so an idle room costs
// nothing; who's who lives in each socket's attachment, not in memory.
import { Room, parseRoute, newCode, refuse } from "./room.js";

const HOST_TRIES = 8;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const route = parseRoute(url.pathname);
    if (!route) {
      return new Response("Impossible Creatures relay. Connect with a WebSocket to /host or /join/CODE.\n");
    }
    if (request.headers.get("Upgrade") !== "websocket") {
      return new Response("Expected a WebSocket", { status: 426 });
    }
    if (route.action === "bad_code") return refuseNow("That code doesn't look right. Codes are 4 letters.");
    if (route.action === "join") return toRoom(env, request, route.code, "join");
    for (let i = 0; i < HOST_TRIES; i++) {
      const response = await toRoom(env, request, newCode(), "host");
      if (response.status !== 409) return response;
    }
    return refuseNow("Couldn't open a room, please try again");
  },
};

function toRoom(env, request, code, role) {
  const url = new URL(request.url);
  url.searchParams.set("code", code);
  url.searchParams.set("role", role);
  const stub = env.ROOMS.get(env.ROOMS.idFromName(code));
  return stub.fetch(new Request(url, request));
}

// Accepts the socket just to say why it can't play; browsers don't show the
// reason for a failed WebSocket handshake.
function refuseNow(message) {
  const [client, server] = Object.values(new WebSocketPair());
  server.accept();
  refuse(server, message);
  return new Response(null, { status: 101, webSocket: client });
}

export class RoomObject {
  constructor(state) {
    this.state = state;
  }

  room(code) {
    return new Room(code, () => this.members());
  }

  members() {
    const members = [];
    for (const ws of this.state.getWebSockets()) {
      const info = ws.deserializeAttachment();
      if (info && ws.readyState === 1) members.push({ id: info.id, code: info.code, ws });
    }
    return members;
  }

  async fetch(request) {
    const url = new URL(request.url);
    const code = url.searchParams.get("code");
    const wantsHost = url.searchParams.get("role") === "host";
    if (wantsHost && this.members().length > 0) return new Response("Room taken", { status: 409 });
    const [client, server] = Object.values(new WebSocketPair());
    this.state.acceptWebSocket(server);
    const room = this.room(code);
    const id = room.admit(server, wantsHost);
    if (id !== 0) {
      server.serializeAttachment({ id, code });
      room.welcome(server, id);
    }
    return new Response(null, { status: 101, webSocket: client });
  }

  webSocketMessage(ws, data) {
    const info = ws.deserializeAttachment();
    if (info) this.room(info.code).message(info.id, data);
  }

  webSocketClose(ws, code) {
    this.gone(ws);
    try {
      ws.close(code === 1005 ? 1000 : code, "Bye");
    } catch {
      // Already closed.
    }
  }

  webSocketError(ws) {
    this.gone(ws);
  }

  gone(ws) {
    const info = ws.deserializeAttachment();
    if (!info || info.left) return;
    ws.serializeAttachment({ ...info, left: true });
    this.room(info.code).left(info.id);
  }
}
