export const CopyToClipboard = {
  mounted() {
    this.handleEvent("copy-to-clipboard", ({ text }) => {
      navigator.clipboard.writeText(text).catch((error) => {
        console.error("Failed to copy to clipboard", error);
      });
    });

    // Elements with data-copy-text copy on click, inside the user gesture,
    // and swap [data-copy-label] for [data-copy-done] only after the write succeeds.
    if (this.el.dataset.copyText) {
      this.el.addEventListener("click", () => {
        navigator.clipboard
          .writeText(this.el.dataset.copyText)
          .then(() => {
            this.el.querySelector("[data-copy-label]")?.classList.add("hidden");
            this.el.querySelector("[data-copy-done]")?.classList.remove("hidden");
          })
          .catch((error) => {
            console.error("Failed to copy to clipboard", error);
          });
      });
    }
  },
};
