const CONSENT_COOKIE = "cookie_consent";
const CONSENT_MAX_AGE_DAYS = 365;

function getCookie(name) {
  const match = document.cookie.match(new RegExp(`(^| )${name}=([^;]+)`));
  return match ? match[2] : null;
}

function setCookie(name, value, days) {
  const maxAge = days * 24 * 60 * 60;
  document.cookie = `${name}=${value};path=/;max-age=${maxAge};SameSite=Lax`;
}

export function consentStatus() {
  return getCookie(CONSENT_COOKIE);
}

export function consentAccepted() {
  return consentStatus() === "accepted";
}

export function consentRejected() {
  return consentStatus() === "rejected";
}

export function acceptConsent() {
  setCookie(CONSENT_COOKIE, "accepted", CONSENT_MAX_AGE_DAYS);
}

export function rejectConsent() {
  setCookie(CONSENT_COOKIE, "rejected", CONSENT_MAX_AGE_DAYS);
}
