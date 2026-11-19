// Arrow keys move focus between a dropdown list's buttons, Home and End jump to
// the first and last one; Enter, Space and Escape stay with the buttons.
const KEYS = ["ArrowDown", "ArrowUp", "Home", "End"];

export const ListboxKeys = {
  mounted() {
    this.el.addEventListener("keydown", (event) => {
      if (!KEYS.includes(event.key)) return;

      const options = [...this.el.querySelectorAll("button:not([disabled])")];
      if (options.length === 0) return;

      event.preventDefault();

      const current = options.indexOf(document.activeElement);
      const last = options.length - 1;

      const next = {
        ArrowDown: current < last ? current + 1 : 0,
        ArrowUp: current > 0 ? current - 1 : last,
        Home: 0,
        End: last,
      }[event.key];

      options[next].focus();
    });
  },
};
