const REDUCED_MOTION_QUERY = "(prefers-reduced-motion: reduce)";

const prefersReducedMotion = () =>
  window.matchMedia?.(REDUCED_MOTION_QUERY).matches ?? false;

const replayAnimation = (el) => {
  if (prefersReducedMotion()) return;

  delete el.dataset.animating;
  void el.offsetWidth;
  el.dataset.animating = "";
};

export const NumberPopIn = {
  mounted() {
    this.lastValue = this.el.dataset.value;
  },

  updated() {
    const nextValue = this.el.dataset.value;

    if (nextValue === this.lastValue) return;

    this.lastValue = nextValue;
    replayAnimation(this.el);
  },
};
