// Development-only MCP Apps host for /development/mcp: plays ChatGPT's role for each frame.
import { AppBridge, PostMessageTransport } from "@modelcontextprotocol/ext-apps/app-bridge";

const DISPLAY_MODES = ["inline", "fullscreen"];
const WIDTHS = { inline: 760, fullscreen: 1060 };
const FULLSCREEN_HEIGHT = "max(40rem, 85vh)";
const INITIAL_INLINE_HEIGHT = 320;

const host = JSON.parse(document.getElementById("mcp-dev-host").dataset.host);

const hostContext = mode => ({
  displayMode: mode,
  availableDisplayModes: DISPLAY_MODES,
  theme: "light",
  locale: "pl-PL",
  timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone,
  platform: "web",
});

async function connectFrame(frame) {
  const scenario = host.scenarios[frame.dataset.scenario];
  const iframe = frame.querySelector("iframe");
  const label = frame.querySelector("[data-mode-label]");
  const exit = frame.querySelector("[data-exit-fullscreen]");
  const tag = `[mcp ${frame.dataset.scenario}/${frame.dataset.mode}]`;
  let mode = frame.dataset.mode;
  let inlineHeight = INITIAL_INLINE_HEIGHT;

  const layout = () => {
    frame.dataset.mode = mode;
    label.textContent = mode;
    exit.hidden = mode !== "fullscreen";
    iframe.style.width = `${WIDTHS[mode]}px`;
    iframe.style.height = mode === "fullscreen" ? FULLSCREEN_HEIGHT : `${inlineHeight}px`;
  };

  const bridge = new AppBridge(
    null,
    { name: "Firmowid dev host", version: "1.0.0" },
    { openLinks: {}, updateModelContext: { structuredContent: {} }, logging: {} },
    { hostContext: hostContext(mode) },
  );

  const switchMode = requested => {
    if (DISPLAY_MODES.includes(requested)) mode = requested;
    layout();
    bridge.setHostContext(hostContext(mode));
    return mode;
  };

  bridge.addEventListener("initialized", () => {
    bridge.sendToolInput({ arguments: scenario.arguments });
    bridge.sendToolResult(scenario.result);
  });
  bridge.addEventListener("sizechange", ({ height }) => {
    if (height === undefined) return;
    inlineHeight = height;
    layout();
  });
  bridge.addEventListener("loggingmessage", params => console.info(tag, "log", params));
  bridge.onrequestdisplaymode = async ({ mode: requested }) => ({ mode: switchMode(requested) });
  bridge.onupdatemodelcontext = async params => {
    console.info(tag, "update-model-context", params);
    return {};
  };
  bridge.onopenlink = async ({ url }) => {
    window.open(url, "_blank", "noopener");
    return {};
  };
  exit.addEventListener("click", () => switchMode("inline"));

  layout();
  // The bridge listens before the document loads so it receives the view's initialize request.
  await bridge.connect(new PostMessageTransport(iframe.contentWindow, iframe.contentWindow));
  iframe.srcdoc = host.document;
}

document.querySelectorAll("[data-mcp-frame]").forEach(connectFrame);
