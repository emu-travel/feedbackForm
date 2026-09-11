/**
 * gxDashboardView
 *
 * Pure functions behind the feedback dashboard: formatting, filter handling
 * and the shaping of server data into what the template draws. No DOM and no
 * Apex, so every rule here is tested directly.
 *
 * The numbers themselves are computed server-side in
 * GxFeedbackDashboardController. Nothing here recalculates a score - it only
 * decides how one is shown.
 */

/** Heatmap bands: below 7 needs attention, 8 and above is good. */
export const LOW_SCORE = 7;
export const GOOD_SCORE = 8;

/** A ranked venue averaging under this gets a warning marker. */
export const FLAG_BELOW = 7.5;

const CLOSED_FOLLOW_UP = new Set(["Contacted", "Resolved"]);

const MONTHS = [
  "Jan",
  "Feb",
  "Mar",
  "Apr",
  "May",
  "Jun",
  "Jul",
  "Aug",
  "Sep",
  "Oct",
  "Nov",
  "Dec"
];

const SUB_LABELS = {
  Room: "Room",
  Service: "Service",
  Catering: "Catering",
  Cleanliness: "Cleanliness"
};

const CATEGORY_LABELS = {
  Hotel: "Hotel",
  Golfclub: "Golf course",
  Airline: "Airline",
  TransferCompany: "Transfer",
  CarRentalCompany: "Rental car"
};

export const CATEGORY_OPTIONS = [
  { label: "All categories", value: "" },
  { label: "Hotels", value: "Hotel" },
  { label: "Golf courses", value: "Golfclub" },
  { label: "Airlines", value: "Airline" },
  { label: "Transfers", value: "TransferCompany" },
  { label: "Rental cars", value: "CarRentalCompany" }
];

export const FOLLOW_UP_OPTIONS = [
  { label: "Open", value: "Open" },
  { label: "Contacted", value: "Contacted" },
  { label: "Resolved", value: "Resolved" }
];

// ------------------------------------------------------------------
// Filters

/** ISO yyyy-mm-dd in local time, as lightning-input type=date expects. */
export function isoDate(d) {
  const pad = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

/**
 * The last twelve months of trips, by trip end date. Long enough for a
 * trend, short enough that last year's problems do not drown this year's.
 */
export function defaultFilters(today = new Date()) {
  const from = new Date(
    today.getFullYear() - 1,
    today.getMonth(),
    today.getDate()
  );
  return {
    fromDate: isoDate(from),
    toDate: isoDate(today),
    region: "",
    country: "",
    travelType: "",
    category: ""
  };
}

/** Only the filters actually set, so an empty choice means "all", not "blank". */
export function filtersPayload(filters) {
  const out = {};
  Object.keys(filters || {}).forEach((key) => {
    const value = filters[key];
    if (value !== undefined && value !== null && value !== "") {
      out[key] = value;
    }
  });
  return JSON.stringify(out);
}

/** Picklist options for a combobox, with an "all" choice first. */
export function withAll(options, allLabel) {
  return [{ label: allLabel, value: "" }, ...(options || [])];
}

// ------------------------------------------------------------------
// Numbers

export function formatScore(value) {
  return value === null || value === undefined ? "—" : Number(value).toFixed(1);
}

/** NPS carries its sign: +25, 0, −10. A missing NPS is a dash, not zero. */
export function formatNps(value) {
  if (value === null || value === undefined) {
    return "—";
  }
  const n = Math.round(Number(value));
  if (n > 0) {
    return `+${n}`;
  }
  return n < 0 ? `−${Math.abs(n)}` : "0";
}

export function formatPercent(value) {
  return value === null || value === undefined
    ? "—"
    : `${Math.round(Number(value))}%`;
}

export function monthLabel(year, month) {
  return `${MONTHS[month - 1]} ${year}`;
}

export function categoryLabel(category) {
  return CATEGORY_LABELS[category] || category || "";
}

/** 'bad' below 7, 'mid' from 7, 'good' from 8 - the heatmap's three bands. */
export function toneFor(score) {
  if (score === null || score === undefined) {
    return "none";
  }
  if (score < LOW_SCORE) {
    return "bad";
  }
  return score < GOOD_SCORE ? "mid" : "good";
}

export function isOpenFollowUp(status) {
  return !CLOSED_FOLLOW_UP.has(status);
}

export function bookingUrl(bookingId) {
  return bookingId ? `/lightning/r/Booking__c/${bookingId}/view` : null;
}

// ------------------------------------------------------------------
// Shaping server data for the template

/** KPI tiles in display order, each already formatted. */
export function kpiTiles(kpis) {
  const k = kpis || {};
  return [
    {
      key: "responses",
      label: "Responses",
      value: String(k.responses || 0),
      note: `${k.invited || 0} invited`
    },
    {
      key: "rate",
      label: "Response rate",
      value: formatPercent(k.responseRate),
      note: `${Math.max((k.invited || 0) - (k.answeredInvitations || 0), 0)} still open`
    },
    {
      key: "nps",
      label: "NPS",
      value: formatNps(k.nps),
      note: `${k.promoters || 0} promoters · ${k.detractors || 0} detractors`
    },
    {
      key: "overall",
      label: "Overall experience",
      value: formatScore(k.avgOverall),
      note: "average out of 10"
    },
    {
      key: "consult",
      label: "Our consultation",
      value: formatScore(k.avgConsultation),
      note: "our advice, not the venues"
    },
    {
      key: "reminder",
      label: "Answered after reminder",
      value: String(k.answeredAfterReminder || 0),
      note: `of ${k.reminded || 0} reminded`
    },
    {
      key: "followups",
      label: "Open follow-ups",
      value: String(k.openFollowUps || 0),
      note: "unhappy guests not yet contacted",
      alert: (k.openFollowUps || 0) > 0
    }
  ];
}

/**
 * One stacked bar per month. Each segment's width is its share of that
 * month's responses, so months with different totals are still comparable.
 */
export function trendBars(trend) {
  return (trend || []).map((m) => {
    const total = m.total || 0;
    const share = (n) => (total ? Math.round((n / total) * 1000) / 10 : 0);
    return {
      key: m.key,
      label: monthLabel(m.year, m.month),
      total,
      nps: formatNps(m.nps),
      promoterStyle: `width:${share(m.promoters)}%`,
      passiveStyle: `width:${share(m.passives)}%`,
      detractorStyle: `width:${share(m.detractors)}%`,
      summary: `${m.promoters} promoters, ${m.passives} passives, ${m.detractors} detractors`
    };
  });
}

/**
 * Split into ranked and not-yet-ranked, keeping the server's order. The bar
 * is out of 10, so its length reads as the score itself.
 */
export function venueList(venues) {
  const rows = (venues || []).map((v) => ({
    key: `${v.category}|${v.name}`,
    name: v.name,
    category: v.category,
    categoryLabel: categoryLabel(v.category),
    score: formatScore(v.average),
    ratings: v.ratings,
    ratingsLabel: v.ratings === 1 ? "1 rating" : `${v.ratings} ratings`,
    barStyle: `width:${Math.max(0, Math.min(100, (v.average || 0) * 10))}%`,
    ranked: Boolean(v.ranked),
    low: Boolean(v.ranked) && v.average < FLAG_BELOW
  }));
  return {
    ranked: rows.filter((r) => r.ranked),
    unranked: rows.filter((r) => !r.ranked)
  };
}

export function heatRows(rows) {
  return (rows || []).map((row) => ({
    key: row.hotel,
    hotel: row.hotel,
    cells: (row.cells || []).map((c) => ({
      key: `${row.hotel}|${c.subCategory}`,
      label: SUB_LABELS[c.subCategory] || c.subCategory,
      value: formatScore(c.average),
      cls: `heat heat_${toneFor(c.average)}`,
      title: c.ratings
        ? `${c.ratings} rating${c.ratings === 1 ? "" : "s"}`
        : "No ratings"
    }))
  }));
}

export function followUpRows(rows, showHandled) {
  return (rows || [])
    .filter((r) => showHandled || isOpenFollowUp(r.followUpStatus))
    .map((r) => ({
      ...r,
      key: r.responseId,
      npsLabel: `NPS ${r.nps === null || r.nps === undefined ? "—" : r.nps}`,
      overallLabel: formatScore(r.overall),
      url: bookingUrl(r.bookingId),
      status: r.followUpStatus || "Open",
      handled: !isOpenFollowUp(r.followUpStatus),
      comment: r.comment || "No comment left."
    }));
}

export function destinationRows(rows) {
  return (rows || []).map((r) => ({
    key: r.responseId,
    guest: r.guest || "Guest",
    wish: r.nextDestination,
    npsLabel: `NPS ${r.nps}`,
    promoter: r.nps >= 9,
    url: bookingUrl(r.bookingId),
    bookingNumber: r.bookingNumber
  }));
}

export function commentRows(rows) {
  return (rows || []).map((c) => ({
    key: c.key,
    text: c.text,
    about: c.about,
    score:
      c.score === null || c.score === undefined ? null : formatScore(c.score),
    cls: `pill pill_${toneFor(c.score)}`,
    guest: c.guest || "Guest",
    bookingNumber: c.bookingNumber,
    url: bookingUrl(c.bookingId)
  }));
}

export function drillRows(rows) {
  return (rows || []).map((r) => ({
    key: r.responseId,
    guest: r.guest || "Guest",
    bookingNumber: r.bookingNumber,
    url: bookingUrl(r.bookingId),
    score: formatScore(r.score),
    cls: `pill pill_${toneFor(r.score)}`,
    comment: r.comment,
    subs: (r.subScores || []).map((s) => ({
      key: `${r.responseId}|${s.subCategory}`,
      label: SUB_LABELS[s.subCategory] || s.subCategory,
      value: formatScore(s.average)
    }))
  }));
}
