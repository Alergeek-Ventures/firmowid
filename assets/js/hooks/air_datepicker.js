import Datepicker from "air-datepicker";

export const AirDatepicker = {
  mounted() {
    this.picker = this.mountDatepicker();
    this.enabledMonths = this.getEnabledMonths();
    this.enabledYears = this.getEnabledYears();
    this.picker.setViewDate(this.el.dataset.initialDate);
    // Safari does not focus buttons on tap or click, and the picker opens on focus.
    this.el.addEventListener("click", () => this.el.focus());
  },

  updated() {
    if (!this.picker) {
      this.picker = this.mountDatepicker();
    } else {
      this.enabledMonths = this.getEnabledMonths();
      this.enabledYears = this.getEnabledYears();
      if (this.isRange()) {
        this.picker.update(this.rangeOptions(), { silent: true });
        this.picker.clear({ silent: true });
        this.picker.selectDate(this.getSelectedDates(), { silent: true });
      } else {
        this.picker.selectDate(this.el.dataset.initialDate, { silent: true });
      }
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

  isRange() {
    return this.el.dataset.range === "true";
  },

  /**
   * @returns {Array<string>}
   */
  getSelectedDates() {
    return this.el.dataset.selectedDates?.split(",").filter(Boolean) || [];
  },

  // A range of months, with a button clearing it; clicking a month twice selects just that month.
  rangeOptions() {
    return {
      range: true,
      toggleSelected: false,
      multipleDatesSeparator: " – ",
      buttons: [{ content: this.el.dataset.clearLabel, onClick: (picker) => picker.clear() }],
    };
  },

  /**
   * @returns {Array<number>}
   */
  getEnabledYears() {
    return this.el.dataset.enabledYears?.split(",").map(Number);
  },

  mountDatepicker() {
    const mode = this.el.dataset.mode || "months";
    // Below Tailwind's md breakpoint the picker opens as a centered modal.
    const isMobile = window.matchMedia("(max-width: 767px)").matches;

    return new Datepicker(this.el, {
      position: this.el.dataset.position || "bottom left",
      isMobile,
      autoClose: isMobile,
      selectedDates: this.isRange() ? this.getSelectedDates() : [this.el.dataset.initialDate],
      ...(this.isRange() ? this.rangeOptions() : {}),
      // Picking the current month or year skips autoClose, so close the modal here;
      // a range leaves its selected ends to the picker.
      ...(this.isRange()
        ? {}
        : {
            toggleSelected: ({ datepicker }) => {
              if (isMobile) datepicker.hide();
              return false;
            },
          }),
      view: mode,
      minView: mode,
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
      dateFormat: mode === "months" ? "MMMM yyyy" : "yyyy",
      onSelect: ({ date }) => {
        if (this.isRange()) {
          // A range is complete with both months; clearing it selects the whole span.
          if (date.length === 2) {
            const [from, to] = date.map((month) => month.toLocaleDateString("sv"));
            this.pushEvent("select-period", { from, to });
          } else if (date.length === 0) {
            this.pushEvent("select-period", {});
          }
          return;
        }

        switch (mode) {
          case "months":
            // 'sv' is the Swedish locale - Sweden date formatting uses ISO 8601
            const newDate = date.toLocaleDateString("sv");
            this.pushEvent("change-month", { month: newDate });   
            break;
          case "years":
            this.pushEvent("change-year", { year: String(date.getFullYear())});
            break;
          default:
            break;
        }
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

        if (cellType === "year" && this.enabledYears) {
          const year = date.getFullYear();
          const isDisabled = !this.enabledYears.includes(year);
          
          return isDisabled
            ? {
                disabled: true,
                classes: "cursor-not-allowed opacity-30 pointer-events-none",
              }
            : {};
        }
      }.bind(this),
    });
  },
};
