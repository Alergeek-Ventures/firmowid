export const CopyToClipboard = {
  mounted() {
    this.handleEvent("copy-to-clipboard", ({ text }) => {
      navigator.clipboard.writeText(text).catch((error) => {
        console.error("Failed to copy to clipboard", error);
      });
    });

    // Elements with data-copy-text copy on click, inside the user gesture,
    // and swap [data-copy-label] for [data-copy-done] only after the write succeeds.
    // Each click resets the status, so a failed attempt never shows an earlier success.
    if (this.el.dataset.copyText) {
      this.el.addEventListener("click", () => {
        // Look the labels up on each click: LiveView may have patched them since mount.
        const label = this.el.querySelector("[data-copy-label]");
        const done = this.el.querySelector("[data-copy-done]");

        label?.classList.remove("hidden");
        done?.classList.add("hidden");

        navigator.clipboard
          .writeText(this.el.dataset.copyText)
          .then(() => {
            label?.classList.add("hidden");
            done?.classList.remove("hidden");
          })
          .catch((error) => {
            console.error("Failed to copy to clipboard", error);
          });
      });
    }
  },
};
