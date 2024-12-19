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
    PDFViewer: {
      mounted() {
        this.loadPdf();
      },
      updated() {
        this.loadPdf();
      },
      loadPdf() {
        const container = this.el; // Make sure this is a container div, not the canvas
        const pdfPath = this.el.getAttribute("data-pdf-url");

        pdfjsLib.GlobalWorkerOptions.workerSrc =
          "https://cdn.jsdelivr.net/npm/pdfjs-dist@4.7.76/build/pdf.worker.min.mjs";

        // Loading the PDF document.
        const loadingTask = pdfjsLib.getDocument(pdfPath);
        loadingTask.promise
          .then((pdfDocument) => {
            // Loop through all pages
            const renderPage = (pageNum) => {
              return pdfDocument.getPage(pageNum).then((pdfPage) => {
                const renderScale = 2.0;
                let viewport = pdfPage.getViewport({ scale: renderScale });
                const aspectRatio = viewport.width / viewport.height;

                // Create a canvas for each page
                const canvas = document.createElement("canvas");
                canvas.width = viewport.width;
                canvas.height = viewport.height;
                canvas.style.width = `${container.clientWidth}px`;
                canvas.style.height = `${
                  container.clientWidth / aspectRatio
                }px`;
                container.appendChild(canvas);

                // Render the page into the canvas context
                const ctx = canvas.getContext("2d");

                return pdfPage.render({
                  canvasContext: ctx,
                  viewport: viewport,
                }).promise;
              });
            };

            // Render each page in sequence
            const renderAllPages = async () => {
              container.innerHTML = "";
              for (
                let pageNum = 1;
                pageNum <= pdfDocument.numPages;
                pageNum++
              ) {
                await renderPage(pageNum);
              }
            };

            return renderAllPages();
          })
          .catch((error) => {
            console.error("Error rendering PDF:", error);
          });
      },
    },
    tippy: {
      mounted() {
        tippy(this.el);
      },
      updated() {
        tippy(this.el);
      },
    },
    AirDatepicker: {
      mounted() {
        this.mountDatepicker();
      },
      updated() {
        this.mountDatepicker();
      },
      mountDatepicker() {
        const initialDate = new Date(this.el.getAttribute("data-initial-date"));

        new AirDatepicker(this.el, {
          selectedDates: [initialDate],
          toggleSelected: false,
          view: "months",
          minView: "months",
          locale: {
            days: [
              "Niedziela",
              "Poniedziałek",
              "Wtorek",
              "Środa",
              "Czwartek",
              "Piątek",
              "Sobota",
            ],
            daysShort: ["Nie", "Pon", "Wto", "Śro", "Czw", "Pią", "Sob"],
            daysMin: ["Nd", "Pn", "Wt", "Śr", "Czw", "Pt", "So"],
            months: [
              "Styczeń",
              "Luty",
              "Marzec",
              "Kwiecień",
              "Maj",
              "Czerwiec",
              "Lipiec",
              "Sierpień",
              "Wrzesień",
              "Październik",
              "Listopad",
              "Grudzień",
            ],
            monthsShort: [
              "Sty",
              "Lut",
              "Mar",
              "Kwi",
              "Maj",
              "Cze",
              "Lip",
              "Sie",
              "Wrz",
              "Paź",
              "Lis",
              "Gru",
            ],
            today: "Dzisiaj",
            clear: "Wyczyść",
            dateFormat: "yyyy-MM-dd",
            timeFormat: "hh:mm:aa",
            firstDay: 1,
          },
          dateFormat: "MMMM yyyy",
          onSelect: ({ date }) => {
            // set time to mid-day to avoid timezone issues
            const newDate = new Date(date);
            newDate.setTime(newDate.getTime() + 12 * 60 * 60 * 1000);
            this.pushEvent("change-month", {
              month: newDate.toISOString().split("T")[0],
            });
          },
        });
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
