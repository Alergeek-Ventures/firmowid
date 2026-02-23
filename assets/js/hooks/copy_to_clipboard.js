export const CopyToClipboard = {
  mounted() {
    this.handleEvent("copy-to-clipboard", ({ text }) => {
      navigator.clipboard.writeText(text).catch((error) => {
        console.error("Failed to copy to clipboard", error);
      });
    });
  },
};
