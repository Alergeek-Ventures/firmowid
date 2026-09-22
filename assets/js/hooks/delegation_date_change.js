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
  },
};
