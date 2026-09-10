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
 * What every scale reads before the guest touches it. Defined here, next to the
 * payload builder, because the two have to agree: the cards show this number
 * from the moment they render, so a guest who is happy and clicks straight
 * through has answered 10 - and their answer must be recorded, not dropped for
 * never having moved a slider.
 */
export const DEFAULT_SCORE = 10;

/**
 * The hotel detail panel's four scales, and what they read before the guest
 * touches them. Keys are the Sub_Category__c picklist values, so they live here
 * with the payload contract rather than in the card that draws them - the card
 * supplies the German labels.
 */
export const SUB_CATEGORIES = ["Room", "Service", "Catering", "Cleanliness"];

/** The spec defaults sub-ratings to 8, not 10. */
export const DEFAULT_SUB_SCORE = 8;

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

function isScore(value) {
  return typeof value === "number" && value >= 1 && value <= 10;
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
  // Every scale on screen has an answer from the moment it renders, so nothing
  // here may fall back to undefined just because a slider was never moved.
  const overall = orDefault(a.overallExperience, DEFAULT_SCORE);
  const consultation = orDefault(a.consultation, DEFAULT_SCORE);
  const recommendation = orDefault(a.recommendation, DEFAULT_SCORE);

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

/** An untouched scale still has the answer it is showing. */
function scoreOf(entry) {
  return orDefault(entry && entry.score, DEFAULT_SCORE);
}

function orDefault(value, fallback) {
  return value === undefined || value === null ? fallback : value;
}

/**
 * The whole detail panel, whether or not the guest moved its scales. Once a
 * hotel scores low enough to open the panel, all four scales are on screen
 * showing a value - and an unhappy guest's breakdown is the most useful thing
 * in the survey, so none of it may depend on their having touched a slider.
 */
function subScores(given) {
  const g = given || {};
  const out = {};
  SUB_CATEGORIES.forEach((key) => {
    out[key] = orDefault(g[key], DEFAULT_SUB_SCORE);
  });
  return out;
}

function singleRating(entry) {
  const e = entry || {};
  const score = scoreOf(e);
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

  return items.map((item) => {
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
    if (withSubRatings && shouldExpandHotelDetail(score)) {
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
