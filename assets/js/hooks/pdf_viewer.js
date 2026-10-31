import { version as pdfjsVersion } from "pdfjs-dist/package.json";

const MAX_PAGE_PIXELS = 16_000_000;
const MAX_DOCUMENT_PIXELS = 64_000_000;

export const PDFViewer = {
  mounted() {
    this.loadPdf();
  },

  updated() {
    this.loadPdf();
  },

  async loadPdf() {
    if (this.loaded === true) {
      return;
    }

    const container = this.el;
    const pdfPath = this.el.getAttribute("data-pdf-url");

    // The `esbuild pdfjs` profile serves PDF.js separately, so only the viewer downloads it.
    // The version query stops browsers from reusing a module or worker cached from another release.
    const pdfjsLib = await import(`/assets/pdfjs/pdf.min.mjs?v=${pdfjsVersion}`);
    pdfjsLib.GlobalWorkerOptions.workerSrc = `/assets/pdfjs/pdf.worker.min.mjs?v=${pdfjsVersion}`;

    const loadingTask = pdfjsLib.getDocument({ url: pdfPath, wasmUrl: "/assets/pdfjs/" });
    loadingTask.promise
      .then((pdfDocument) => {
        const renderPage = (pageNum) => {
          return pdfDocument.getPage(pageNum).then((pdfPage) => {
            const baseViewport = pdfPage.getViewport({ scale: 1 });
            const pixelBudget = Math.min(MAX_PAGE_PIXELS, MAX_DOCUMENT_PIXELS / pdfDocument.numPages);
            const renderScale = Math.min(2, Math.sqrt(pixelBudget / (baseViewport.width * baseViewport.height)));
            let viewport = pdfPage.getViewport({ scale: renderScale });
            const aspectRatio = viewport.width / viewport.height;

            const canvas = document.createElement("canvas");
            canvas.width = viewport.width;
            canvas.height = viewport.height;
            canvas.style.width = `${container.clientWidth}px`;
            canvas.style.height = `${container.clientWidth / aspectRatio}px`;
            container.appendChild(canvas);

            const ctx = canvas.getContext("2d");

            return pdfPage.render({
              canvasContext: ctx,
              viewport: viewport,
            }).promise;
          });
        };

        const renderAllPages = async () => {
          container.innerHTML = "";
          for (let pageNum = 1; pageNum <= pdfDocument.numPages; pageNum++) {
            await renderPage(pageNum);
          }
        };

        return renderAllPages();
      })
      .then(() => {
        this.loaded = true;
      })
      .catch((error) => {
        console.error("Error rendering PDF:", error);
      });
  },
};
