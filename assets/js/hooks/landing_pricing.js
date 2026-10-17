export const LandingPricing = {
  mounted() {
    this.updateHeader = () => {
      const header = this.el.querySelector(".landing-pricing__plans");
      const cards = this.el.querySelectorAll(".landing-pricing__card");
      const offset = parseFloat(getComputedStyle(header).top);
      header.classList.toggle(
        "is-stuck",
        cards[cards.length - 1].getBoundingClientRect().bottom <= offset,
      );
    };
    this.observer = new ResizeObserver(this.updateHeader);
    this.observer.observe(this.el);
    window.addEventListener("scroll", this.updateHeader, { passive: true });
    this.updateHeader();
  },
  destroyed() {
    this.observer.disconnect();
    window.removeEventListener("scroll", this.updateHeader);
  },
};
