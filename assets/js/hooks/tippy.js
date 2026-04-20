function truncateTarget(el) {
  const selector = el.dataset.tippyTruncateSelector;

  if (!selector) return el;

  return el.querySelector(selector) ?? el;
}

function mountTippy(el, { onlyWhenTruncated = false } = {}) {
  el._tippy?.destroy();

  const target = truncateTarget(el);

  if (onlyWhenTruncated && target.scrollWidth <= target.clientWidth) {
    return;
  }

  tippy(el);
}

function truncatedHook() {
  return {
    mounted() {
      this.resizeObserver = new ResizeObserver(() => {
        mountTippy(this.el, { onlyWhenTruncated: true });
      });

      this.resizeObserver.observe(this.el);

      const target = truncateTarget(this.el);

      if (target !== this.el) {
        this.resizeObserver.observe(target);
      }

      mountTippy(this.el, { onlyWhenTruncated: true });
    },

    updated() {
      mountTippy(this.el, { onlyWhenTruncated: true });
    },

    destroyed() {
      this.resizeObserver?.disconnect();
      this.el._tippy?.destroy();
    }
  };
}

export const Tippy = {
  mounted() {
    mountTippy(this.el);
  },

  updated() {
    mountTippy(this.el);
  },

  destroyed() {
    this.el._tippy?.destroy();
  }
};

export const TippyWhenTruncated = truncatedHook();
