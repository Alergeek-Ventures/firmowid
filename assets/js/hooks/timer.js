/**
 * @type {import("phoenix_live_view").ViewHook}
 */
export const Timer = {
  mounted() {
    this.start_time = new Date(this.el.dataset.start_time);
    this.format = this.el.dataset.format;
    this.disabled = this.el.dataset.disabled === "";
    this.startTimer();
  },

  updated() {
    this.start_time = new Date(this.el.dataset.start_time);
    this.format = this.el.dataset.format;
    this.disabled = this.el.dataset.disabled === "";

    if (this.start_time) {
      this.startTimer();
    }
  },

  beforeUpdate() {
    this.updateElement();
  },

  formatTime(elapsed) {
    const seconds = Math.floor(elapsed / 1000);
    const minutes = Math.floor(seconds / 60);
    const hours = Math.floor(minutes / 60);

    if (this.format === "short") {
      return `${hours.toString().padStart(2, "0")}:${(minutes % 60)
        .toString()
        .padStart(2, "0")}`;
    } else if (this.format === "pretty") {
      return `${hours}h ${minutes % 60}min`;
    }

    return `${hours.toString().padStart(2, "0")}:${(minutes % 60)
      .toString()
      .padStart(2, "0")}:${(seconds % 60).toString().padStart(2, "0")}`;
  },

  updateElement() {
    const elapsed = Math.max(new Date() - this.start_time, 0);
    this.el.textContent = this.formatTime(elapsed);
  },

  startTimer() {
    clearInterval(this.interval);

    if (this.disabled) {
      return;
    }

    this.updateElement();
    this.interval = setInterval(this.updateElement.bind(this), 1000);
  },

  destroyed() {
    clearInterval(this.interval);
  },
};
