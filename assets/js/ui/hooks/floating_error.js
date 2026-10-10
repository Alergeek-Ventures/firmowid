import { computePosition, flip, arrow, offset } from "@floating-ui/dom";

export const FloatingUIError = {
  mounted() {
    this.initFloating();
    this.resizeHandler = () => this.update();
    window.addEventListener("resize", this.resizeHandler);
  },

  updated() {
    this.initFloating();
  },

  destroyed() {
    window.removeEventListener("resize", this.resizeHandler);
  },

  initFloating() {
    this.floatingEl = this.el;
    this.targetId = this.el.dataset.for;
    this.targetElement = document.getElementById(this.targetId);
    this.arrowEl = document.getElementById(`arrow_${this.targetId}`);

    if (!this.targetElement || !this.arrowEl) return;

    this.update();
  },

  update() {
    if (!this.targetElement || !this.arrowEl) return;

    computePosition(this.targetElement, this.floatingEl, {
      placement: "top",
      middleware: [
        offset(8),
        flip(),
        arrow({ element: this.arrowEl }),
      ],
    }).then(({ x, y, middlewareData }) => {
      Object.assign(this.floatingEl.style, {
        left: `${x}px`,
        top: `${y}px`,
      });

      if (middlewareData.arrow) {
        const { x: arrowX, y: arrowY } = middlewareData.arrow;

        Object.assign(this.arrowEl.style, {
          left: arrowX != null ? `${arrowX}px` : "",
          top: arrowY != null ? `${arrowY}px` : "",
        });
      }
    });
  },
};
