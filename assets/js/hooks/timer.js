/**
 * @type {import("phoenix_live_view").ViewHook}
 */
export const Timer = {
  mounted() {
    this.start_time = new Date(this.el.dataset.start_time);
    this.startTimer();
  },

  updated() {
    this.start_time = new Date(this.el.dataset.start_time);

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

    return `${hours.toString().padStart(2, "0")}:${(minutes % 60)
      .toString()
      .padStart(2, "0")}:${(seconds % 60).toString().padStart(2, "0")}`;
  },

  updateElement() {
    const elapsed = new Date() - this.start_time;
    this.el.textContent = this.formatTime(elapsed);
  },

  startTimer() {
    clearInterval(this.interval);
    this.updateElement();
    this.interval = setInterval(this.updateElement.bind(this), 1000);
  },

  destroyed() {
    clearInterval(this.interval);
  },
};
