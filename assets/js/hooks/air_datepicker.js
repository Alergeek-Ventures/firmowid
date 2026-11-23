import Datepicker from "air-datepicker";
import localeEn from "air-datepicker/locale/en";
import localePl from "air-datepicker/locale/pl";
import localeUk from "air-datepicker/locale/uk";

const LOCALES = { en: localeEn, pl: localePl, uk: localeUk };

export const AirDatepicker = {
  mounted() {
    this.picker = this.mountDatepicker();
    this.enabledMonths = this.getEnabledMonths();
    this.enabledYears = this.getEnabledYears();
    this.picker.setViewDate(this.el.dataset.initialDate);
    // Safari does not focus buttons on tap or click, and the picker opens on focus.
    this.el.addEventListener("click", () => this.el.focus());
    // A range trigger shows its label in the placeholder, worded like the server's
    // (Periods.label/1), instead of the picker's own text.
    this.el.addEventListener("change", () => this.isRange() && (this.el.value = ""));
    if (this.isRange()) {
      this.el.value = "";
      this.committed = this.selectedMonths();
    }
  },

  beforeUpdate() {
    this.triggerWidth = this.el.closest("label")?.getBoundingClientRect().width;
  },

  updated() {
    this.animateLabelChange(this.triggerWidth);
    // LiveView leaves a focused input unpatched, so its data still holds the previous
    // period; the open picker already shows the one just chosen.
    if (this.isRange() && document.activeElement === this.el) return;
    if (!this.picker) {
      this.picker = this.mountDatepicker();
    } else {
      this.enabledMonths = this.getEnabledMonths();
      this.enabledYears = this.getEnabledYears();
      if (this.isRange()) {
        this.committed = this.selectedMonths();
        this.picker.update(this.rangeOptions(), { silent: true });
        this.picker.clear({ silent: true });
        this.picker.selectDate(this.getSelectedDates(), { silent: true });
      } else {
        this.picker.selectDate(this.el.dataset.initialDate, { silent: true });
      }
    }
  },

  // Shows the chosen months on the trigger at once, before the server answers.
  showRangeLabel(dates) {
    const label = this.rangeLabel(dates);
    if (label === this.el.placeholder) return;
    const width = this.el.closest("label")?.getBoundingClientRect().width;
    this.el.placeholder = label;
    this.animateLabelChange(width);
  },

  // Mirrors FirmowidWeb.Analysis.Utilities.Periods.label/1.
  rangeLabel([from, to = from]) {
    const lang = document.documentElement.lang || "pl";
    const name = (date) => {
      const month = new Intl.DateTimeFormat(lang, { month: "long" }).format(date);
      return month.charAt(0).toLocaleUpperCase(lang) + month.slice(1);
    };
    const [fromYear, toYear] = [from.getFullYear(), to.getFullYear()];

    if (fromYear === toYear && from.getMonth() === to.getMonth()) return `${name(from)} ${fromYear}`;
    if (fromYear === toYear && from.getMonth() === 0 && to.getMonth() === 11) return `${fromYear}`;
    if (fromYear === toYear) return `${name(from)} – ${name(to)} ${toYear}`;
    return `${name(from)} ${fromYear} – ${name(to)} ${toYear}`;
  },

  // The trigger eases to the width of its new label as the text fades in (DESIGN.md "Motion").
  animateLabelChange(from) {
    const trigger = this.el.closest("label");
    const to = trigger?.getBoundingClientRect().width;
    if (!from || Math.abs(to - from) < 1) return;
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

    const options = { duration: 200, easing: "ease-out" };
    const restore = () => (trigger.style.overflow = "");
    trigger.style.overflow = "clip";
    trigger
      .animate([{ width: `${from}px` }, { width: `${to}px` }], options)
      .finished.then(restore, restore);
    this.el.animate([{ opacity: 0 }, { opacity: 1 }], options);
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

  // The selected months as local dates, like the picker's own.
  selectedMonths() {
    return this.getSelectedDates().map((date) => new Date(`${date}T00:00`));
  },

  // A range of months, with a button choosing this whole year (Navigation.year_period/1);
  // clicking a month twice selects just that month.
  rangeOptions() {
    const thisYear = (picker) => {
      const year = new Date().getFullYear();
      picker.clear({ silent: true });
      picker.setViewDate(new Date(year, 0, 1));
      picker.selectDate([new Date(year, 0, 1), new Date(year, 11, 1)]);
    };

    return {
      range: true,
      toggleSelected: false,
      multipleDatesSeparator: " – ",
      buttons: [{ content: this.el.dataset.clearLabel, onClick: thisYear }],
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
      // Follow the interface language; weeks start on Monday as in Poland.
      locale: { ...LOCALES[document.documentElement.lang] ?? localePl, firstDay: 1 },
      dateFormat: mode === "months" ? "MMMM yyyy" : "yyyy",
      // Closing on a half-chosen range goes back to the period in use.
      onHide: (isFinished) => {
        if (isFinished || !this.isRange() || this.picker.selectedDates.length !== 1) return;
        this.picker.clear({ silent: true });
        this.picker.selectDate(this.committed, { silent: true });
        this.showRangeLabel(this.committed);
      },
      onSelect: ({ date }) => {
        if (this.isRange()) {
          // A range is complete with both months. One month comes as a lone date.
          const dates = [date].flat().filter(Boolean);
          if (dates.length > 0) this.showRangeLabel(dates);
          if (dates.length === 2) {
            this.committed = dates;
            const [from, to] = dates.map((month) => month.toLocaleDateString("sv"));
            this.pushEvent("select-period", { from, to });
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
