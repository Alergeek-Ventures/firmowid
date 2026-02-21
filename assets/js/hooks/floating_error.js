const { computePosition, flip, arrow, offset } = window.FloatingUIDOM;

export const FloatingUIError = {
  mounted() {
    this.initFloating();
  },

  updated() {
    this.initFloating();
  },

  destroyed() {
    this.destroyFloating();
  },

  initFloating() {
    this.floatingEl = this.el;
    this.targetId = this.el.dataset.for;
    this.erroredInput = document.getElementById(this.targetId);
    this.arrowEl = document.getElementById(`arr_${this.targetId}`);

    if (!this.erroredInput || !this.arrowEl) return;

    Object.assign(this.erroredInput.style, {
      border: "solid 2px #A22A2A",
    });

    const getReferenceEl = () => {
      if (this.el.dataset.reference) {
        return document.getElementById(this.el.dataset.reference);
      }
      return this.erroredInput;
    };

    const update = () => {
      const referenceEl = getReferenceEl();
      if (!referenceEl) return;

      computePosition(referenceEl, this.floatingEl, {
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
    };

    const referenceEl = getReferenceEl();
    if (!referenceEl) return;

    update();
  },

  destroyFloating() {
    if (this.erroredInput) {
      Object.assign(this.erroredInput.style, {
        border: "",
      });
    }
  },
};