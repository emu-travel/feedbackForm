/**
 * gxSurveyFlow
 *
 * Screen routing and payload assembly for the post-trip feedback survey.
 * Pure functions with no DOM and no wire adapters, so the survey's branching
 * can be tested on its own.
 *
 * Ported from SurveyView.tsx (getNextScreen / getPrevScreen) in the prototype,
 * driven by the has* flags GxFeedbackService.getContext returns.
 */

export const SCREEN = {
  OVERALL: 1,
  MOBILITY: 2,
  HOTELS: 3,
  GOLF: 4,
  CONCLUSION: 5,
  THANKS: 6
};

/** Screens that ask questions. The thank-you screen is not a step. */
const QUESTION_SCREENS = [
  SCREEN.OVERALL,
  SCREEN.MOBILITY,
  SCREEN.HOTELS,
  SCREEN.GOLF,
  SCREEN.CONCLUSION
];

/** Score at or below which a follow-up comment box is revealed. */
export const COMMENT_THRESHOLD = 8;

/** Hotel score below which the four sub-ratings expand. */
export const HOTEL_DETAIL_THRESHOLD = 9;

/** Recommendation score at or above which the public review cards appear. */
export const PROMOTER_THRESHOLD = 9;

/**
 * Every scale starts empty. A pre-selected 10 let a guest click straight
 * through and "answer" 10 to everything, and made a real 10 impossible to tell
 * from an untouched one. So a rating only exists once the guest has chosen it:
 * the main ratings on each screen must be chosen before Weiter moves on (see
 * unansweredOn), and anything left empty is simply not sent.
 */
export const SCORE_MIN = 1;

/**
 * The hotel detail panel's four scales. Keys are the Sub_Category__c picklist
 * values, so they live here with the payload contract rather than in the card
 * that draws them - the card supplies the German labels. They are optional.
 */
export const SUB_CATEGORIES = ["Room", "Service", "Catering", "Cleanliness"];

export function hasMobility(context) {
  if (!context) {
    return false;
  }
  return Boolean(
    context.hasFlight || context.hasTransfers || context.hasRentalCar
  );
}

function isScreenVisible(screen, context) {
  if (!context) {
    return false;
  }
  switch (screen) {
    case SCREEN.OVERALL:
    case SCREEN.CONCLUSION:
      return true;
    case SCREEN.MOBILITY:
      return hasMobility(context);
    case SCREEN.HOTELS:
      return Boolean(context.hasHotels);
    case SCREEN.GOLF:
      return Boolean(context.hasGolf);
    default:
      return false;
  }
}

/**
 * The question screens this guest will actually see, in order.
 * Screens 1 and 5 always appear; 2, 3 and 4 depend on what was booked.
 */
export function visibleScreens(context) {
  return QUESTION_SCREENS.filter((s) => isScreenVisible(s, context));
}

export function nextScreen(current, context) {
  const screens = visibleScreens(context);
  const at = screens.indexOf(current);

  if (at === -1) {
    return screens.length ? screens[0] : SCREEN.THANKS;
  }
  if (at === screens.length - 1) {
    return SCREEN.THANKS;
  }
  return screens[at + 1];
}

export function previousScreen(current, context) {
  const screens = visibleScreens(context);

  if (current === SCREEN.THANKS) {
    return screens.length ? screens[screens.length - 1] : SCREEN.OVERALL;
  }

  const at = screens.indexOf(current);
  if (at <= 0) {
    return null; // already at the first screen; there is nowhere back to go
  }
  return screens[at - 1];
}

export function isLastQuestionScreen(current, context) {
  const screens = visibleScreens(context);
  return screens.length > 0 && screens[screens.length - 1] === current;
}

/**
 * Progress counted over the screens this guest actually sees.
 *
 * The prototype hard-coded "Schritt X von 5" and a percentage of 5, which
 * misreports progress whenever a screen is skipped - a hotels-only guest would
 * see three screens but a bar that jumps 20% -> 60% -> 100%.
 */
export function progressFor(current, context) {
  const screens = visibleScreens(context);
  const total = screens.length;
  const at = screens.indexOf(current);

  if (total === 0 || at === -1) {
    return { step: 0, total: 0, percent: 0 };
  }
  return {
    step: at + 1,
    total,
    percent: Math.round(((at + 1) / total) * 100)
  };
}

export function shouldShowComment(score) {
  return isScore(score) && score <= COMMENT_THRESHOLD;
}

export function shouldExpandHotelDetail(score) {
  return isScore(score) && score < HOTEL_DETAIL_THRESHOLD;
}

export function earnsPublicReview(recommendation) {
  return isScore(recommendation) && recommendation >= PROMOTER_THRESHOLD;
}

/** Every scale in the survey, the recommendation included, runs 1-10. */
export function isScore(value) {
  return Number.isInteger(value) && value >= SCORE_MIN && value <= 10;
}

/**
 * The main ratings on a screen the guest has not chosen yet, as keys the form
 * can mark: a field name, or "hotel:<reservationId>" / "golf:<reservationId>".
 * The hotel sub-ratings and every comment stay optional.
 */
export function unansweredOn(screen, context, answers) {
  const a = answers || {};
  const ctx = context || {};
  const missing = [];
  const chosen = (entry) => (entry ? entry.score : null);

  switch (screen) {
    case SCREEN.OVERALL:
      if (!isScore(a.overallExperience)) {
        missing.push("overallExperience");
      }
      if (!isScore(a.consultation)) {
        missing.push("consultation");
      }
      break;
    case SCREEN.MOBILITY:
      [
        ["hasFlight", "flight"],
        ["hasTransfers", "transfer"],
        ["hasRentalCar", "rentalCar"]
      ].forEach(([flag, field]) => {
        if (ctx[flag] && !isScore(chosen(a[field]))) {
          missing.push(field);
        }
      });
      break;
    case SCREEN.HOTELS:
      (ctx.hotels || []).forEach((h) => {
        if (!isScore(chosen((a.hotels || {})[h.reservationId]))) {
          missing.push(`hotel:${h.reservationId}`);
        }
      });
      break;
    case SCREEN.GOLF:
      (ctx.golfCourses || []).forEach((c) => {
        if (!isScore(chosen((a.golfCourses || {})[c.reservationId]))) {
          missing.push(`golf:${c.reservationId}`);
        }
      });
      break;
    case SCREEN.CONCLUSION:
      if (!isScore(a.recommendation)) {
        missing.push("recommendation");
      }
      break;
    default:
      break;
  }
  return missing;
}

const GERMAN_MONTHS = [
  "Januar",
  "Februar",
  "März",
  "April",
  "Mai",
  "Juni",
  "Juli",
  "August",
  "September",
  "Oktober",
  "November",
  "Dezember"
];

/**
 * "2026-09-04" as a German guest reads it: "4. September 2026". Anything that
 * is not an ISO date comes back unchanged rather than as a wrong date.
 */
export function germanDate(iso) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso || "");
  if (!match) {
    return iso || "";
  }
  const [, year, month, day] = match;
  const name = GERMAN_MONTHS[Number(month) - 1];
  return name ? `${Number(day)}. ${name} ${year}` : iso;
}

/**
 * Builds the JSON body GxFeedbackService.submit expects.
 *
 * Only sections the guest was actually shown are included, and a comment is
 * only sent when its score earned the follow-up - so a screen the survey
 * skipped can never contribute a stray rating.
 */
export function buildPayload({ context, bookingNumber, secret, answers }) {
  const a = answers || {};
  // Only what the guest actually chose. Nothing is filled in on their behalf.
  const overall = isScore(a.overallExperience) ? a.overallExperience : null;
  const consultation = isScore(a.consultation) ? a.consultation : null;
  const recommendation = isScore(a.recommendation) ? a.recommendation : null;

  const payload = {
    bookingNumber,
    secret,
    language: (context && context.language) || "DE",
    overallExperience: overall,
    consultation,
    recommendation,
    nextDestination: emptyToNull(a.nextDestination),
    improvementSuggestions: emptyToNull(a.improvementSuggestions)
  };

  if (shouldShowComment(overall)) {
    payload.overallExperienceComment = emptyToNull(a.overallExperienceComment);
  }
  if (shouldShowComment(consultation)) {
    payload.consultationComment = emptyToNull(a.consultationComment);
  }

  if (context && context.hasFlight) {
    payload.flight = singleRating(a.flight);
  }
  if (context && context.hasTransfers) {
    payload.transfer = singleRating(a.transfer);
  }
  if (context && context.hasRentalCar) {
    payload.rentalCar = singleRating(a.rentalCar);
  }

  if (context && context.hasHotels) {
    payload.hotels = itemRatings(context.hotels, a.hotels, true);
    payload.generalHotelComment = emptyToNull(a.generalHotelComment);
  }
  if (context && context.hasGolf) {
    payload.golfCourses = itemRatings(
      context.golfCourses,
      a.golfCourses,
      false
    );
    payload.generalGolfComment = emptyToNull(a.generalGolfComment);
  }

  return payload;
}

function scoreOf(entry) {
  const score = entry ? entry.score : null;
  return isScore(score) ? score : null;
}

/** The sub-ratings the guest chose; the ones left empty are not sent. */
function subScores(given) {
  const g = given || {};
  const out = {};
  SUB_CATEGORIES.forEach((key) => {
    if (isScore(g[key])) {
      out[key] = g[key];
    }
  });
  return Object.keys(out).length ? out : null;
}

function singleRating(entry) {
  const e = entry || {};
  const score = scoreOf(e);
  if (score === null) {
    return null;
  }
  const rating = { score };
  if (shouldShowComment(score)) {
    rating.comment = emptyToNull(e.comment);
  }
  return rating;
}

function itemRatings(items, answersByReservation, withSubRatings) {
  if (!Array.isArray(items)) {
    return [];
  }
  const byReservation = answersByReservation || {};

  const rated = items.filter(
    (item) => scoreOf(byReservation[item.reservationId]) !== null
  );
  return rated.map((item) => {
    const given = byReservation[item.reservationId] || {};
    const score = scoreOf(given);
    const entry = {
      reservationId: item.reservationId,
      itemName: item.name,
      score
    };

    if (shouldShowComment(score)) {
      entry.comment = emptyToNull(given.comment);
    }
    const sub = withSubRatings && shouldExpandHotelDetail(score);
    if (sub && subScores(given.sub)) {
      entry.sub = subScores(given.sub);
    }
    return entry;
  });
}

function emptyToNull(value) {
  if (typeof value !== "string") {
    return value === undefined ? null : value;
  }
  const trimmed = value.trim();
  return trimmed.length ? trimmed : null;
}
