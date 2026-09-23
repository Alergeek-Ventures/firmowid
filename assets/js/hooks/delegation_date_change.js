export const DelegationDateChange = {
  mounted() {
    this.handleEvent("scroll-to-date-change", () => {
      document.getElementById("delegation-date-change")?.scrollIntoView({
        behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches
          ? "auto"
          : "smooth",
        block: "center",
      });
    });

    this.handleEvent("preserve-statement-upload-scroll", () => {
      this.statementUploadScrollY = window.scrollY;
    });
  },
  updated() {
    if (this.statementUploadScrollY !== undefined) {
      window.scrollTo({ top: this.statementUploadScrollY });
      this.statementUploadScrollY = undefined;
    }
  },
};
