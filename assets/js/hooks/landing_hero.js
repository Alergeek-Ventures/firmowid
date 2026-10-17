const STATES = 4;
const INTERVAL_MS = 2000;

export const LandingHero = {
  mounted() {
    this.motion = window.matchMedia("(prefers-reduced-motion: reduce)");
    this.state = 0;

    this.show = () => {
      this.el.querySelectorAll("[data-state]").forEach((element) => {
        element.classList.toggle(
          "is-active",
          Number(element.dataset.state) === this.state,
        );
      });
    };

    this.configure = () => {
      clearInterval(this.timer);
      this.state = 0;
      this.show();

      if (!this.motion.matches) {
        this.timer = setInterval(() => {
          this.state = (this.state + 1) % STATES;
          this.show();
        }, INTERVAL_MS);
      }
    };

    this.motion.addEventListener("change", this.configure);
    this.configure();
  },

  destroyed() {
    clearInterval(this.timer);
    this.motion.removeEventListener("change", this.configure);
  },
};
