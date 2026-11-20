/**
 * Brings the element into view once it appears, for a row a link points at.
 * @type {import("phoenix_live_view").ViewHook}
 */
export const ScrollIntoView = {
  mounted() {
    const reduce = window.matchMedia(
      "(prefers-reduced-motion: reduce)",
    ).matches;
    this.el.scrollIntoView({
      block: "center",
      behavior: reduce ? "auto" : "smooth",
    });
  },
};
