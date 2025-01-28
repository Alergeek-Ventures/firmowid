export const PDFViewer = {
    mounted() {
        this.loadPdf();
    },

    updated() {
        this.loadPdf();
    },

    loadPdf() {
        const container = this.el;
        const pdfPath = this.el.getAttribute("data-pdf-url");

        pdfjsLib.GlobalWorkerOptions.workerSrc =
            "https://cdn.jsdelivr.net/npm/pdfjs-dist@4.7.76/build/pdf.worker.min.mjs";

        const loadingTask = pdfjsLib.getDocument(pdfPath);
        loadingTask.promise
            .then((pdfDocument) => {
                const renderPage = (pageNum) => {
                    return pdfDocument.getPage(pageNum).then((pdfPage) => {
                        const renderScale = 2.0;
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
            .catch((error) => {
                console.error("Error rendering PDF:", error);
            });
    }
}; 