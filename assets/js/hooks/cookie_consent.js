/**
 * CookieConsent Hook
 *
 * Shows the cookie consent banner if no preference has been stored yet.
 * On accept/reject, sets a `cookie_consent` cookie (max-age: 1 year)
 * readable by the server for analytics gating.
 *
 * Values: "accepted" | "rejected"
 *
 * @type {import("phoenix_live_view").ViewHook}
 */
export const CookieConsent = {
  mounted() {
    const existing = getCookie("cookie_consent");

    if (!existing) {
      this.el.classList.remove("hidden");
    }

    this.el
      .querySelector("#cookie-consent-accept")
      .addEventListener("click", () => {
        setCookie("cookie_consent", "accepted", 365);
        this.el.classList.add("hidden");
      });

    this.el
      .querySelector("#cookie-consent-reject")
      .addEventListener("click", () => {
        setCookie("cookie_consent", "rejected", 365);
        this.el.classList.add("hidden");
      });
  },
};

function getCookie(name) {
  const match = document.cookie.match(
    new RegExp("(^| )" + name + "=([^;]+)")
  );
  return match ? match[2] : null;
}

function setCookie(name, value, days) {
  const maxAge = days * 24 * 60 * 60;
  document.cookie = `${name}=${value};path=/;max-age=${maxAge};SameSite=Lax`;
}
