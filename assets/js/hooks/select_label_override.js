export const SelectLabelOverride = {
  mounted() {
    this.el.addEventListener("change", () => this.updateLabel());
  },

  updated() {
    this.updateLabel();
  },

  updateLabel() {
    const label = this.el.nextElementSibling;
    if (!label?.dataset.selectLabelOverride) return;

    const selectedLabels = JSON.parse(this.el.dataset.selectedLabels);

    label.textContent =
      this.el.value === ""
        ? this.el.dataset.prompt
        : selectedLabels[this.el.value] ?? this.el.options[this.el.selectedIndex].text;
  },
};
