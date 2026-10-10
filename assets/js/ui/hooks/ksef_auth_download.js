export const KsefAuthDownload = {
  mounted() {
    this.handleEvent("download-ksef-auth-token-request", ({ content, filename }) => {
      const blob = new Blob([content], { type: "application/xml;charset=utf-8" });
      const url = URL.createObjectURL(blob);
      const link = document.createElement("a");
      link.href = url;
      link.download = filename;
      link.click();
      URL.revokeObjectURL(url);
    });
  },
};
