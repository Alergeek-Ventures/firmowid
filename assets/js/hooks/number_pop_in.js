const ANIMATING_CLASS = "is-animating";
const REDUCED_MOTION_QUERY = "(prefers-reduced-motion: reduce)";

const prefersReducedMotion = () =>
  window.matchMedia?.(REDUCED_MOTION_QUERY).matches ?? false;

const replayAnimation = (el) => {
  if (prefersReducedMotion()) return;

  el.classList.remove(ANIMATING_CLASS);
  void el.offsetWidth;
  el.classList.add(ANIMATING_CLASS);
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
