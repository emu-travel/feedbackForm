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
    category: "",
    designer: ""
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

/** One promoter, two promoters. */
export function plural(n, one, many) {
  return `${n} ${n === 1 ? one : many}`;
}

/**
 * NPS answers use NPS bands, not score bands: 9-10 promoter, 7-8 passive,
 * 0-6 detractor. Coloured as a score, an 8 would read green when it is a
 * passive.
 */
export function npsToneFor(value) {
  if (value === null || value === undefined) {
    return "none";
  }
  if (value >= 9) {
    return "good";
  }
  return value >= 7 ? "mid" : "bad";
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
      note: `${k.invited || 0} invited`,
      target: "responses",
      hint: "See every response"
    },
    {
      key: "rate",
      label: "Response rate",
      value: formatPercent(k.responseRate),
      note: `${Math.max((k.invited || 0) - (k.answeredInvitations || 0), 0)} still open`,
      target: "waiting",
      hint: "See who has not answered yet"
    },
    {
      key: "nps",
      label: "NPS",
      value: formatNps(k.nps),
      note: `${plural(k.promoters || 0, "promoter", "promoters")} · ${plural(
        k.detractors || 0,
        "detractor",
        "detractors"
      )}`
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
      note:
        (k.openFollowUps || 0) === 1
          ? "unhappy guest not yet contacted"
          : "unhappy guests not yet contacted",
      alert: (k.openFollowUps || 0) > 0,
      // The one tile that is also a to-do list: it takes you there.
      target: "followups",
      hint: "Go to the unhappy guests to follow up"
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
      detail: `${r.guest || "Guest"} · overall ${formatScore(r.overall)}`,
      url: bookingUrl(r.bookingId),
      status: r.followUpStatus || "Open",
      handled: !isOpenFollowUp(r.followUpStatus),
      updatedLabel: r.followUpBy ? `Last updated by ${r.followUpBy}` : null,
      comment: r.comment || "No comment left."
    }));
}

export function destinationRows(rows) {
  return (rows || []).map((r) => ({
    key: r.responseId,
    responseId: r.responseId,
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
    responseId: c.responseId,
    text: c.text,
    about: c.about,
    score: commentScoreLabel(c),
    cls: `pill pill_${commentTone(c)}`,
    low: commentTone(c) === "bad",
    guest: c.guest || "Guest",
    bookingNumber: c.bookingNumber,
    url: bookingUrl(c.bookingId)
  }));
}

function commentTone(c) {
  return c.scoreKind === "nps" ? npsToneFor(c.score) : toneFor(c.score);
}

function commentScoreLabel(c) {
  if (c.score === null || c.score === undefined) {
    return null;
  }
  return c.scoreKind === "nps"
    ? `NPS ${Math.round(c.score)}`
    : formatScore(c.score);
}

export function drillRows(rows) {
  return (rows || []).map((r) => ({
    key: r.responseId,
    responseId: r.responseId,
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

// ------------------------------------------------------------------
// Paging

/** Every list on the dashboard shows this many rows at a time. */
export const PAGE_SIZE = 10;

/**
 * One page of a list, with the page number clamped to what exists - so a
 * list that shrinks (a filter, "Hide handled") never lands on an empty page.
 */
export function pageOf(rows, page, size = PAGE_SIZE) {
  const all = rows || [];
  const pages = Math.max(1, Math.ceil(all.length / size));
  const current = Math.min(Math.max(1, Number(page) || 1), pages);
  return {
    rows: all.slice((current - 1) * size, current * size),
    page: current,
    pages,
    total: all.length
  };
}

/** "11–20 of 57" */
export function rangeLabel(page, total, size = PAGE_SIZE) {
  if (!total) {
    return "0 of 0";
  }
  const from = (page - 1) * size + 1;
  const to = Math.min(page * size, total);
  return `${from}–${to} of ${total}`;
}

// ------------------------------------------------------------------
// One whole response

/** "30 Aug – 8 Sep 2026" from two ISO dates. */
export function tripDates(start, end) {
  const parse = (iso) => {
    const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso || "");
    return m
      ? { y: m[1], mo: MONTHS[Number(m[2]) - 1], d: Number(m[3]) }
      : null;
  };
  const a = parse(start);
  const b = parse(end);
  if (a && b) {
    return a.y === b.y
      ? `${a.d} ${a.mo} – ${b.d} ${b.mo} ${b.y}`
      : `${a.d} ${a.mo} ${a.y} – ${b.d} ${b.mo} ${b.y}`;
  }
  const one = a || b;
  return one ? `${one.d} ${one.mo} ${one.y}` : "";
}

function scored(key, label, score, comment, extra = {}) {
  return {
    key,
    label,
    score: formatScore(score),
    cls: `pill pill_${toneFor(score)}`,
    comment: comment || null,
    subs: [],
    ...extra
  };
}

/**
 * A response laid out the way the guest filled it in: one section per survey
 * screen, skipping the screens their trip did not have.
 */
export function responseView(detail) {
  if (!detail) {
    return null;
  }
  const d = detail;
  const sections = [];

  sections.push({
    key: "overall",
    title: "Overall impression",
    items: [
      scored("overall", "The trip overall", d.overall, d.overallComment),
      scored(
        "consult",
        "Our consultation and product choice",
        d.consultation,
        d.consultationComment
      )
    ],
    texts: []
  });

  if ((d.services || []).length) {
    sections.push({
      key: "services",
      title: "Flights, transfers and rental cars",
      items: d.services.map((s, i) =>
        scored(
          `service-${i}`,
          `${categoryLabel(s.category)} · ${s.name}`,
          s.score,
          s.comment
        )
      ),
      texts: []
    });
  }

  if ((d.hotels || []).length || d.generalHotelComment) {
    sections.push({
      key: "hotels",
      title: "Hotels",
      items: (d.hotels || []).map((h, i) =>
        scored(`hotel-${i}`, h.name, h.score, h.comment, {
          subs: (h.subScores || []).map((c) => ({
            key: `hotel-${i}-${c.subCategory}`,
            label: SUB_LABELS[c.subCategory] || c.subCategory,
            value: formatScore(c.average)
          }))
        })
      ),
      texts: textRows([["About the hotels in general", d.generalHotelComment]])
    });
  }

  if ((d.golf || []).length || d.generalGolfComment) {
    sections.push({
      key: "golf",
      title: "Golf courses",
      items: (d.golf || []).map((g, i) =>
        scored(`golf-${i}`, g.name, g.score, g.comment)
      ),
      texts: textRows([["About the golf in general", d.generalGolfComment]])
    });
  }

  const nps =
    d.recommendation === null || d.recommendation === undefined
      ? null
      : Math.round(d.recommendation);
  sections.push({
    key: "close",
    title: "Conclusion",
    items: [
      {
        key: "nps",
        label: "Would recommend golf.extra",
        score: nps === null ? "—" : String(nps),
        cls: `pill pill_${npsToneFor(nps)}`,
        comment: null,
        subs: [],
        tag: d.npsCategory || null
      }
    ],
    texts: textRows([
      ["Next on their wish list", d.nextDestination],
      ["Suggestions and personal notes", d.improvementSuggestions],
      ["Anything else", d.generalFeedback]
    ])
  });

  const where = [d.region, d.country].filter(Boolean).join(", ");
  const standout = standoutOf(sections);
  return {
    title: `${d.reference || "Feedback"} · ${d.guest || "Guest"}`,
    designer: d.designer || null,
    standout,
    hasStandout: standout.length > 0,
    tripLine: [d.bookingNumber, where, tripDates(d.tripStart, d.tripEnd)]
      .filter(Boolean)
      .join(" · "),
    submittedOn: d.submittedOn,
    bookingId: d.bookingId,
    responseId: d.responseId,
    reviewPrompted: Boolean(d.publicReviewPrompted),
    sections,
    followUp:
      d.followUpStatus || d.followUpNote
        ? {
            status: d.followUpStatus || "Open",
            note: d.followUpNote || null,
            by: d.followUpBy || null,
            on: d.followUpOn || null
          }
        : null
  };
}

function textRows(pairs) {
  return pairs
    .filter(([, text]) => text && String(text).trim())
    .map(([label, text], i) => ({ key: `text-${i}-${label}`, label, text }));
}

/**
 * Everything in a response scored below 7, for the strip at the top of the
 * full view: what someone reading it for the first time should see first.
 */
function standoutOf(sections) {
  const out = [];
  sections.forEach((section) => {
    section.items.forEach((item) => {
      const n = Number(item.score);
      const low =
        item.key === "nps" ? n <= 6 : Number.isFinite(n) && n < LOW_SCORE;
      if (item.score !== "—" && low) {
        out.push({
          key: `standout-${item.key}`,
          label: item.key === "nps" ? "Would recommend" : item.label,
          score: item.score,
          cls: item.cls
        });
      }
    });
  });
  return out;
}

// ------------------------------------------------------------------
// The response list

export const GROUP_OPTIONS = [
  { label: "All", value: "all" },
  { label: "Promoters", value: "promoters" },
  { label: "Passives", value: "passives" },
  { label: "Detractors", value: "detractors" },
  { label: "Open follow-ups", value: "open" }
];

export const SORT_OPTIONS = [
  { label: "Newest first", value: "newest" },
  { label: "Lowest scores first", value: "lowest" }
];

/** "8 Sep 2026" from an ISO date. */
export function shortDate(iso) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso || "");
  return m ? `${Number(m[3])} ${MONTHS[Number(m[2]) - 1]} ${m[1]}` : "";
}

/**
 * A page of responses as list rows: who and which trip on the left, and on
 * the right the few facts that decide whether to open it - the lowest score
 * when it is 8 or below, how much the guest wrote, and where a follow-up
 * stands.
 */
export function responseListRows(rows) {
  return (rows || []).map((r) => {
    const nps =
      r.nps === null || r.nps === undefined ? null : Math.round(r.nps);
    const detractor = nps !== null && nps <= 6;
    const lowest =
      r.lowestScore !== null &&
      r.lowestScore !== undefined &&
      r.lowestScore <= 8
        ? {
            label: r.lowestLabel,
            score: formatScore(r.lowestScore),
            cls: `pill pill_${toneFor(r.lowestScore)}`
          }
        : null;
    const status = detractor ? r.followUpStatus || "Open" : null;
    return {
      key: r.responseId,
      responseId: r.responseId,
      guest: r.guest || "Guest",
      bookingNumber: r.bookingNumber,
      url: bookingUrl(r.bookingId),
      reference: r.reference,
      trip: [r.region, shortDate(r.tripEnd)].filter(Boolean).join(" · "),
      designer: r.designer || null,
      npsLabel: nps === null ? "NPS —" : `NPS ${nps}`,
      npsCls: `pill pill_${npsToneFor(nps)}`,
      overall: formatScore(r.overall),
      overallCls: `pill pill_${toneFor(r.overall)}`,
      lowest,
      commentsLabel: r.comments
        ? plural(r.comments, "comment", "comments")
        : null,
      statusLabel: status ? `Follow-up: ${status}` : null,
      statusCls:
        status && isOpenFollowUp(status) ? "status status_open" : "status",
      reviewPrompted: Boolean(r.reviewPrompted)
    };
  });
}

/** What the list is showing, in words. */
export function responsesSummary(page, term) {
  const p = page || {};
  const total = p.total || 0;
  if (p.searching) {
    return total
      ? `${plural(total, "response", "responses")} matching "${term}", from all dates and filters`
      : `No response matches "${term}". Search looks at guest name, email, booking number and FB number.`;
  }
  return total
    ? plural(total, "response", "responses")
    : "No responses in this selection";
}

/** Travel designers, with the one being filtered on marked. */
export function designerRows(rows, activeId) {
  return (rows || []).map((d) => ({
    key: d.id,
    id: d.id,
    name: d.name,
    responses: d.responses,
    consultation: formatScore(d.consultation),
    consultCls: `pill pill_${toneFor(d.consultation)}`,
    nps: formatNps(d.nps),
    active: d.id === activeId,
    rowCls: d.id === activeId ? "drow drow_active" : "drow"
  }));
}

// ------------------------------------------------------------------
// Waiting for an answer

const WAITING_STATES = {
  waiting: "wtag wtag_waiting",
  reminded: "wtag wtag_reminded",
  expired: "wtag wtag_expired"
};

/**
 * Invited guests who have not answered: who, which trip, when they were last
 * asked, and what happens next - a reminder, or nothing, because the link
 * has run out.
 */
export function waitingRows(rows) {
  return (rows || []).map((w) => {
    const sent = shortDate(String(w.lastSent || "").slice(0, 10));
    let stateLabel;
    if (w.state === "expired") {
      stateLabel = `Link expired ${shortDate(w.expiresOn)}`;
    } else if (w.state === "reminded") {
      stateLabel = w.expiresOn
        ? `Reminded · link open until ${shortDate(w.expiresOn)}`
        : "Reminded";
    } else {
      stateLabel = w.reminderDue
        ? `Reminder due ${shortDate(w.reminderDue)}`
        : "No reminder planned";
    }
    return {
      key: w.bookingId,
      guest: w.guest || "Guest",
      bookingNumber: w.bookingNumber,
      url: bookingUrl(w.bookingId),
      designer: w.designer || null,
      trip: [w.region, shortDate(w.tripEnd)].filter(Boolean).join(" · "),
      sentLabel: `${w.reminded ? "Last asked" : "Invited"} ${sent}`,
      stateLabel,
      stateCls: WAITING_STATES[w.state] || WAITING_STATES.waiting
    };
  });
}

/** What the export did, for the toast. */
export function exportMessage(result) {
  const r = result || {};
  if (!r.rows) {
    return "There are no responses in this selection to export.";
  }
  const saved = `${plural(r.rows, "response", "responses")} saved to ${r.fileName}.`;
  return r.capped
    ? `${saved} That is the first ${r.rows} of ${r.total}; narrow the dates or search to export the rest.`
    : saved;
}
