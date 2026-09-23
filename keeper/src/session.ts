/**
 * US equity session state from a UTC timestamp.
 *
 * Regular:    09:30–16:00 ET, Mon–Fri, non-holiday
 * PreMarket:  04:00–09:30 ET
 * PostMarket: 16:00–20:00 ET
 * Overnight:  20:00–04:00 ET on the 24/5 schedule (Sun 20:00 ET → Fri 20:00 ET)
 * Closed:     Fri 20:00 ET → Sun 20:00 ET, and NYSE holidays (all day)
 *
 * Contract enum order: Closed=0, PreMarket=1, Regular=2, PostMarket=3, Overnight=4
 */
export const Session = { Closed: 0, PreMarket: 1, Regular: 2, PostMarket: 3, Overnight: 4 } as const;
export type SessionValue = (typeof Session)[keyof typeof Session];

// NYSE full-day holidays. Extend yearly; early closes (13:00 ET) listed separately.
export const NYSE_HOLIDAYS = new Set([
  "2026-01-01", "2026-01-19", "2026-02-16", "2026-04-03", "2026-05-25", "2026-06-19",
  "2026-07-03", "2026-09-07", "2026-11-26", "2026-12-25",
  "2027-01-01", "2027-01-18", "2027-02-15", "2027-03-26", "2027-05-31", "2027-06-18",
  "2027-07-05", "2027-09-06", "2027-11-25", "2027-12-24",
]);
export const NYSE_EARLY_CLOSE = new Set(["2026-11-27", "2026-12-24", "2027-11-26"]);

function etParts(d: Date) {
  const f = new Intl.DateTimeFormat("en-US", {
    timeZone: "America/New_York", hour12: false,
    year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", weekday: "short",
  });
  const p = Object.fromEntries(f.formatToParts(d).map((x) => [x.type, x.value]));
  const hour = Number(p.hour) % 24;
  return { ymd: `${p.year}-${p.month}-${p.day}`, mins: hour * 60 + Number(p.minute), wd: p.weekday };
}

export function sessionAt(d: Date = new Date()): SessionValue {
  const { ymd, mins, wd } = etParts(d);
  const holiday = NYSE_HOLIDAYS.has(ymd);
  const close = NYSE_EARLY_CLOSE.has(ymd) ? 13 * 60 : 16 * 60;

  if (wd === "Sat") return Session.Closed;
  if (wd === "Sun") return mins >= 20 * 60 ? Session.Overnight : Session.Closed;
  if (wd === "Fri" && mins >= 20 * 60) return Session.Closed;
  if (holiday) {
    // holiday: no regular/pre/post; overnight keeps running on 24/5 rails
    if (mins >= 20 * 60 || mins < 4 * 60) return Session.Overnight;
    return Session.Closed;
  }
  if (mins >= 20 * 60 || mins < 4 * 60) return Session.Overnight;
  if (mins < 9 * 60 + 30) return Session.PreMarket;
  if (mins < close) return Session.Regular;
  return Session.PostMarket;
}

export function sessionName(s: SessionValue) {
  return Object.entries(Session).find(([, v]) => v === s)?.[0] ?? "Unknown";
}
