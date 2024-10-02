// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html";
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import topbar from "../vendor/topbar";
import { createLiveToastHook } from "live_toast";

let csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: {
    LiveToast: createLiveToastHook(),
    FileUploadDragNDrop: {
      updated() {
        this.attachListeners();
      },
      mounted() {
        this.attachListeners();
      },
      attachListeners() {
        const dropArea = this.el;

        const showDropArea = () => {
          dropArea.classList.remove("hidden");
          dropArea.classList.add("opacity-100");
        };

        let hideDropAreaTimeout = null;

        const hideDropArea = () => {
          setTimeout(() => dropArea.classList.add("hidden"), 160);
          dropArea.classList.remove("opacity-100");
        };

        const handleDragover = (e) => {
          e.preventDefault();
          e.stopPropagation();
          showDropArea();
          clearTimeout(hideDropAreaTimeout);
          hideDropAreaTimeout = setTimeout(hideDropArea, 200);
        };

        // Preventing default browser behavior when dragging a file over the container
        dropArea.addEventListener("dragover", handleDragover);
        dropArea.addEventListener("dragenter", handleDragover);

        document.body.addEventListener("dragover", handleDragover);
        document.body.addEventListener("dragenter", handleDragover);
      },
    },
  },
});

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" });
window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300));
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide());

// connect if there are any LiveViews on the page
liveSocket.connect();

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket;
