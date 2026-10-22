export const LandingPricing = {
  mounted() {
    this.expanded = false;
    this.toggleFeatures = () => {
      this.expanded = !this.expanded;
      this.updateFeatures();
    };
    this.el
      .querySelector("#landing-pricing-toggle")
      .addEventListener("click", this.toggleFeatures);
    this.updateHeader = () => {
      const header = this.el.querySelector("#landing-pricing-plans");
      const cards = this.el.querySelectorAll("[data-pricing-card]");
      const offset = parseFloat(getComputedStyle(header).top);
      header.dataset.stuck = String(
        cards[cards.length - 1].getBoundingClientRect().bottom <= offset,
      );
    };
    this.observer = new ResizeObserver(this.updateHeader);
    this.observer.observe(this.el);
    window.addEventListener("scroll", this.updateHeader, { passive: true });
    this.updateHeader();
  },
  updateFeatures() {
    const button = this.el.querySelector("#landing-pricing-toggle");
    const features = this.el.querySelector("#landing-pricing-features");
    button.setAttribute("aria-expanded", String(this.expanded));
    features.dataset.expanded = String(this.expanded);
    features.setAttribute("aria-hidden", String(!this.expanded));
    features.inert = !this.expanded;
  },
  updated() {
    this.updateFeatures();
    this.updateHeader();
  },
  destroyed() {
    this.el
      .querySelector("#landing-pricing-toggle")
      .removeEventListener("click", this.toggleFeatures);
    this.observer.disconnect();
    window.removeEventListener("scroll", this.updateHeader);
  },
};
