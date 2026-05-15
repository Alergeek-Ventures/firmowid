export const DownloadPdf = {
  mounted() {
    this.el.addEventListener("click", (e) => {
      e.preventDefault();
      e.stopPropagation();
      const btn = this.el;
      const idle = btn.querySelector("[data-download-idle]");
      const loading = btn.querySelector("[data-download-loading]");
      const url = btn.dataset.downloadUrl;
      const modalId = btn.dataset.modalId;
      const successEvent = btn.dataset.downloadSuccessEvent;
      const successTarget = btn.dataset.downloadTarget;

      if (idle) idle.classList.add("hidden");
      if (loading) {
        loading.classList.remove("hidden");
        loading.classList.add("inline-flex");
      }
      btn.disabled = true;

      fetch(url)
        .then((r) => {
          if (!r.ok) {
            throw new Error(`PDF generation failed: ${r.status}`);
          }
          const cd = r.headers.get("content-disposition") || "";
          const match = cd.match(/filename="?([^"]+)"?/);
          const filename = match ? match[1] : "faktura.pdf";
          return r.blob().then((blob) => ({ blob, filename }));
        })
        .then(({ blob, filename }) => {
          const a = document.createElement("a");
          a.href = URL.createObjectURL(blob);
          a.download = filename;
          document.body.appendChild(a);
          a.click();
          a.remove();
          URL.revokeObjectURL(a.href);

          const modal = document.getElementById(modalId);
          if (modal) {
            window.liveSocket.execJS(modal, modal.dataset.cancel);
          }

          if (successEvent) {
            if (successTarget) {
              this.pushEventTo(successTarget, successEvent, {});
            } else {
              this.pushEvent(successEvent, {});
            }
          }
        })
        .catch(() => {
          this.pushEvent("pdf-download-error", {});
        })
        .finally(() => {
          if (idle) idle.classList.remove("hidden");
          if (loading) {
            loading.classList.add("hidden");
            loading.classList.remove("inline-flex");
          }
          btn.disabled = false;
        });
    });
  },
};
