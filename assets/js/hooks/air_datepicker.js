export const AirDatepicker = {
  mounted() {
    this.picker = this.mountDatepicker();
    this.enabledMonths = this.getEnabledMonths();
    this.picker.setViewDate(this.el.dataset.initialDate);
  },

  updated() {
    if (!this.picker) {
      this.picker = this.mountDatepicker();
    } else {
      this.enabledMonths = this.getEnabledMonths();
      this.picker.selectDate(this.el.dataset.initialDate, { silent: true });
    }
  },

  destroyed() {
    if (this.picker) {
      this.picker.destroy();
      this.picker = null;
    }
  },

  /**
   * @returns {Array<Date>}
   */
  getEnabledMonths() {
    return this.el.dataset.enabledMonths?.split(",").map((m) => {
      const date = new Date(m);
      return new Date(date.getUTCFullYear(), date.getUTCMonth());
    });
  },

  mountDatepicker() {
    return new window.AirDatepicker(this.el, {
      selectedDates: [this.el.dataset.initialDate],
      toggleSelected: false,
      view: "months",
      minView: "months",
      locale: {
        days: [
          "Niedziela",
          "Poniedziałek",
          "Wtorek",
          "Środa",
          "Czwartek",
          "Piątek",
          "Sobota",
        ],
        daysShort: ["Nie", "Pon", "Wto", "Śro", "Czw", "Pią", "Sob"],
        daysMin: ["Nd", "Pn", "Wt", "Śr", "Czw", "Pt", "So"],
        months: [
          "Styczeń",
          "Luty",
          "Marzec",
          "Kwiecień",
          "Maj",
          "Czerwiec",
          "Lipiec",
          "Sierpień",
          "Wrzesień",
          "Październik",
          "Listopad",
          "Grudzień",
        ],
        monthsShort: [
          "Sty",
          "Lut",
          "Mar",
          "Kwi",
          "Maj",
          "Cze",
          "Lip",
          "Sie",
          "Wrz",
          "Paź",
          "Lis",
          "Gru",
        ],
        today: "Dzisiaj",
        clear: "Wyczyść",
        dateFormat: "yyyy-MM-dd",
        timeFormat: "hh:mm:aa",
        firstDay: 1,
      },
      dateFormat: "MMMM yyyy",
      onSelect: ({ date }) => {
        // 'sv' is the Swedish locale - Sweden date formatting uses ISO 8601
        const newDate = date.toLocaleDateString("sv");
        this.pushEvent("change-month", { month: newDate });
      },
      onRenderCell: function ({ date, cellType }) {
        if (cellType === "month" && this.enabledMonths) {
          const isDisabled = !this.enabledMonths.some(
            (m) =>
              m.getUTCMonth() === date.getUTCMonth() &&
              m.getUTCFullYear() === date.getUTCFullYear()
          );

          return isDisabled
            ? {
                disabled: isDisabled,
                classes: "cursor-not-allowed opacity-30 pointer-events-none",
              }
            : {};
        }
      }.bind(this),
    });
  },
};
