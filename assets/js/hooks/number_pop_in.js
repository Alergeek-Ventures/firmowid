const REDUCED_MOTION_QUERY = "(prefers-reduced-motion: reduce)";

const prefersReducedMotion = () =>
  window.matchMedia?.(REDUCED_MOTION_QUERY).matches ?? false;

// With `data-changed-only`, only the digits that differ from the previous value
// (compared from the right, so the units line up) are marked to animate.
const markChangedDigits = (el, previous, next) => {
  const digits = [...el.children];
  const offset = previous.length - next.length;

  digits.forEach((digit, index) => {
    if (previous[index + offset] === next[index]) {
      delete digit.dataset.changed;
    } else {
      digit.dataset.changed = "";
    }
  });
};

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

    if (this.el.dataset.changedOnly !== undefined) {
      markChangedDigits(this.el, this.lastValue, nextValue);
    }

    this.lastValue = nextValue;
    replayAnimation(this.el);
  },
};
