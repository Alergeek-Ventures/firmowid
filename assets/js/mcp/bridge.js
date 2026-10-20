import { App } from "@modelcontextprotocol/ext-apps";
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import { createLiveToastHook } from "live_toast";
import tippy from "tippy.js";
import { UIHooks } from "../ui/hooks";
import { Tippy } from "../hooks/tippy";

const root = document.getElementById("mcp-root");
const status = document.getElementById("mcp-status");
const messages = JSON.parse(document.getElementById("mcp-messages").textContent);
const app = new App({ name: "Firmowid", version: "1.0.0" }, {});
const lifetime = new AbortController();
let liveSocket;
let mountData;
let currentView;

const report = key => {
  if (lifetime.signal.aborted) return;
  status.textContent = messages[key] ?? "";
  status.hidden = !status.textContent;
};

function destroyView() {
  // LiveView finishes hook cleanup after the channel leave acknowledgement.
  currentView?.contextRequest?.abort();
  currentView = undefined;
  liveSocket?.destroyAllViews();
}

function unmount() {
  destroyView();
  liveSocket?.disconnect();
  root.replaceChildren();
}

const McpContext = {
  mounted() {
    currentView = this;
    report();
    this.handleEvent("mcp:context", async detail => {
      if (currentView !== this) return;
      this.contextRequest?.abort();
      const controller = new AbortController();
      this.contextRequest = controller;
      try {
        await connection;
        if (controller.signal.aborted) return;
        await app.updateModelContext(
          { structuredContent: detail.structuredContent },
          { signal: controller.signal },
        );
        if (!controller.signal.aborted) report();
      } catch {
        if (!controller.signal.aborted) report("context_failed");
      }
    });
    this.handleEvent("mcp:expired", () => {
      if (currentView !== this) return;
      unmount();
      report("expired");
    });
  },
  disconnected() {
    this.contextRequest?.abort();
  },
  reconnected() {
    if (currentView === this) report();
  },
  destroyed() {
    this.contextRequest?.abort();
    if (currentView === this) currentView = undefined;
  },
};

const McpKsefDownload = {
  mounted() {
    this.handleEvent("download-ksef-auth-token-request", async ({ content, filename }) => {
      this.request?.abort();
      const controller = new AbortController();
      this.request = controller;
      try {
        await connection;
        if (controller.signal.aborted) return;
        const result = await app.downloadFile({
          contents: [{
            type: "resource",
            resource: { uri: `file:///${encodeURIComponent(filename)}`, mimeType: "application/xml", text: content },
          }],
        }, { signal: controller.signal });
        if (result.isError && !controller.signal.aborted) report("download_failed");
      } catch {
        if (!controller.signal.aborted) report("download_failed");
      }
    });
  },
  disconnected() { this.request?.abort(); },
  destroyed() { this.request?.abort(); },
};

// Offers fullscreen while the widget is inline; the host provides its own exit.
const McpFullscreen = {
  mounted() {
    this.sync = () => {
      const context = app.getHostContext();
      this.el.hidden = !(context?.displayMode === "inline" &&
        context.availableDisplayModes?.includes("fullscreen"));
    };
    this.el.addEventListener("click", () => {
      app.requestDisplayMode({ mode: "fullscreen" }, { signal: lifetime.signal })
        .then(this.sync)
        .catch(() => {});
    });
    tippy(this.el, { arrow: false });
    displayModeListeners.add(this.sync);
    connection.then(this.sync, () => {});
  },
  destroyed() {
    displayModeListeners.delete(this.sync);
    this.el._tippy?.destroy();
  },
};

const displayModeListeners = new Set();
const syncDisplayMode = () => displayModeListeners.forEach(sync => sync());
app.onhostcontextchanged = syncDisplayMode;

function mount(result) {
  const data = result?._meta?.["firmowid/app"];
  if (lifetime.signal.aborted) return;
  if (result?.isError || data?.version !== 1 || typeof data.html !== "string") {
    unmount();
    report("failed");
    return;
  }
  // A single LiveSocket owns document listeners; host remounts replace its roots.
  destroyView();
  mountData = data;
  // Only the authenticated tool's private metadata carries this signed native root.
  root.innerHTML = data.html;
  if (!liveSocket) {
    liveSocket = new LiveSocket(data.socket_url, Socket, {
      hooks: { ...UIHooks, Tippy, McpContext, McpKsefDownload, McpFullscreen, LiveToast: createLiveToastHook() },
    });
  }
  report();
  liveSocket.connect();
}

root.addEventListener("click", event => {
  const link = event.target.closest('a[target="_blank"][href]');
  if (link) {
    event.preventDefault();
    app.openLink({ url: link.href }, { signal: lifetime.signal })
      .then(result => { if (result.isError) report("link_failed"); })
      .catch(() => report("link_failed"));
  }
}, { signal: lifetime.signal });

window.addEventListener("securitypolicyviolation", event => {
  if (event.effectiveDirective === "connect-src") report("blocked");
}, { signal: lifetime.signal });

app.ontoolresult = mount;
app.ontoolcancelled = () => {
  report(currentView ? undefined : "failed");
};
app.onerror = () => report("failed");
function dispose() {
  lifetime.abort();
  unmount();
}
app.onclose = () => {
  report("failed");
  dispose();
};
app.onteardown = async () => {
  dispose();
  return {};
};
const connection = app.connect();
connection.then(syncDisplayMode, () => report("failed"));
