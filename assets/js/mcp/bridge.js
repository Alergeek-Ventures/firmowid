import { App } from "@modelcontextprotocol/ext-apps";
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";

const root = document.getElementById("mcp-root");
const status = document.getElementById("mcp-status");
const refresh = document.getElementById("mcp-refresh");
const messages = JSON.parse(document.getElementById("mcp-messages").textContent);
const app = new App({ name: "Firmowid", version: "1.0.0" }, {});
let liveSocket;
let mountData;
let pending;
let generation = 0;
let contextGeneration = 0;
let ready = false;
let closed = false;
let suspended = true;

const report = key => { status.textContent = messages[key]; };
const setBusy = busy => { refresh.disabled = busy || !ready || !mountData; };

function mount(result) {
  const data = result?._meta?.["firmowid/app"];
  if (closed) return;
  if (result?.isError || data?.version !== 1 || typeof data.html !== "string") {
    report("failed");
    return;
  }
  generation += 1;
  contextGeneration += 1;
  mountData = data;
  // A single LiveSocket owns document listeners; host remounts replace its roots.
  liveSocket?.destroyAllViews();
  // Only the authenticated tool's private metadata carries this signed native root.
  root.innerHTML = data.html;
  if (!liveSocket) {
    liveSocket = new LiveSocket(data.socket_url, Socket, {
      params: () => ({ query: mountData.arguments.input || {} }),
    });
    const reportConnection = key => { if (!suspended && !closed) report(key); };
    liveSocket.getSocket().onOpen(() => reportConnection("connecting"));
    liveSocket.getSocket().onError(() => reportConnection("disconnected"));
    liveSocket.getSocket().onClose(() => reportConnection("disconnected"));
  }
  suspended = false;
  report("connecting");
  liveSocket.connect();
  setBusy(Boolean(pending));
}

refresh.addEventListener("click", async () => {
  if (!mountData || pending || !ready) return;
  const controller = new AbortController();
  pending = controller;
  const current = generation;
  setBusy(true);
  report("connecting");
  try {
    const result = await app.callServerTool(
      { name: mountData.tool_name, arguments: mountData.arguments },
      { timeout: 15000, signal: controller.signal },
    );
    if (pending === controller && generation === current) mount(result);
  } catch {
    if (!closed && pending === controller) report("failed");
  } finally {
    if (pending === controller) {
      pending = undefined;
      setBusy(false);
    }
  }
});

root.addEventListener("click", event => {
  if (event.target.closest("[data-mcp-remount]")) refresh.click();
});

window.addEventListener("phx:mcp:context", async ({ detail }) => {
  if (!mountData || closed || suspended) return;
  report("connected");
  mountData.arguments = detail.arguments;
  const current = ++contextGeneration;
  try {
    await app.updateModelContext({ structuredContent: detail.structuredContent });
  } catch {
    if (!closed && contextGeneration === current) report("context_failed");
  }
});

window.addEventListener("phx:mcp:expired", () => {
  generation += 1;
  contextGeneration += 1;
  suspended = true;
  liveSocket?.destroyAllViews();
  liveSocket?.disconnect();
  root.replaceChildren();
  report("expired");
});

window.addEventListener("securitypolicyviolation", event => {
  if (event.effectiveDirective === "connect-src") report("blocked");
});

app.ontoolresult = result => {
  pending?.abort();
  pending = undefined;
  mount(result);
};
app.ontoolcancelled = () => { pending?.abort(); pending = undefined; setBusy(false); };
app.onerror = () => report("failed");
app.onteardown = async () => {
  closed = true;
  generation += 1;
  contextGeneration += 1;
  pending?.abort();
  liveSocket?.destroyAllViews();
  liveSocket?.disconnect();
  root.replaceChildren();
  return {};
};
app.connect(undefined, { timeout: 15000 }).then(() => {
  ready = true;
  setBusy(Boolean(pending));
}).catch(() => report("failed"));
