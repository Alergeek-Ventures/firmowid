export default {
  mounted() {
    this.scrollToBottom();
  },
  updated() {
    this.scrollToBottom();
  },
  scrollToBottom() {
    this.el.scrollTo({ top: this.el.scrollHeight, behavior: "smooth" });
  }
} 