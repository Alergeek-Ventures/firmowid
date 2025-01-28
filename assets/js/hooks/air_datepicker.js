export const AirDatepicker = {
    mounted() {
        this.picker = this.mountDatepicker();
        this.picker.setViewDate(new Date(this.el.getAttribute("data-initial-date")));
    },

    updated() {
        if (!this.picker) {
            this.picker = this.mountDatepicker();
        } else {
            const initialDate = new Date(this.el.getAttribute("data-initial-date"));
            this.picker.selectDate(initialDate, { silent: true });
        }
    },

    destroyed() {
        if (this.picker) {
            this.picker.destroy();
            this.picker = null;
        }
    },

    mountDatepicker() {
        const initialDate = new Date(this.el.getAttribute("data-initial-date"));
        // Using global AirDatepicker from CDN
        return new window.AirDatepicker(this.el, {
            selectedDates: [initialDate],
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
                const newDate = new Date(date);
                newDate.setTime(newDate.getTime() + 12 * 60 * 60 * 1000);
                this.pushEvent("change-month", {
                    month: newDate.toISOString().split("T")[0],
                });
            },
        });
    }
}; 