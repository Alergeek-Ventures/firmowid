export const KsefSkippedInvoicesBanner = {
  mounted() {
    this.observer = new IntersectionObserver((entries) => {
      if (entries.some((entry) => entry.isIntersecting)) {
        this.pushEvent("skipped-ksef-sales-invoices-viewed", {});
        this.observer.disconnect();
      }
    });
    this.observer.observe(this.el);
  },

  destroyed() {
    this.observer.disconnect();
  },
};
