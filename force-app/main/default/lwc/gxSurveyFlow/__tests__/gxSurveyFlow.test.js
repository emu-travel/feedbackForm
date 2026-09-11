import {
  SCREEN,
  hasMobility,
  visibleScreens,
  nextScreen,
  previousScreen,
  isLastQuestionScreen,
  progressFor,
  shouldShowComment,
  shouldExpandHotelDetail,
  earnsPublicReview,
  buildPayload,
  germanDate,
  isNps,
  unansweredOn
} from "c/gxSurveyFlow";

const context = (overrides = {}) => ({
  hasFlight: false,
  hasTransfers: false,
  hasRentalCar: false,
  hasHotels: false,
  hasGolf: false,
  hotels: [],
  golfCourses: [],
  language: "DE",
  ...overrides
});

const FULL = context({
  hasFlight: true,
  hasTransfers: true,
  hasRentalCar: true,
  hasHotels: true,
  hasGolf: true,
  hotels: [{ reservationId: "h1", name: "Hotel Alpha" }],
  golfCourses: [{ reservationId: "g1", name: "Golf One" }]
});

const HOTELS_ONLY = context({
  hasHotels: true,
  hotels: [{ reservationId: "h1", name: "Hotel Alpha" }]
});

describe("screen visibility", () => {
  it("always shows the overall and conclusion screens", () => {
    expect(visibleScreens(context())).toEqual([
      SCREEN.OVERALL,
      SCREEN.CONCLUSION
    ]);
  });

  it("shows every screen when everything was booked", () => {
    expect(visibleScreens(FULL)).toEqual([
      SCREEN.OVERALL,
      SCREEN.MOBILITY,
      SCREEN.HOTELS,
      SCREEN.GOLF,
      SCREEN.CONCLUSION
    ]);
  });

  it("treats any single mobility service as enough for the mobility screen", () => {
    expect(hasMobility(context({ hasFlight: true }))).toBe(true);
    expect(hasMobility(context({ hasTransfers: true }))).toBe(true);
    expect(hasMobility(context({ hasRentalCar: true }))).toBe(true);
    expect(hasMobility(context())).toBe(false);
  });

  it("survives a missing context", () => {
    expect(hasMobility(null)).toBe(false);
    expect(visibleScreens(null)).toEqual([]);
  });
});

describe("forward navigation", () => {
  it("walks every screen in order for a full itinerary", () => {
    expect(nextScreen(SCREEN.OVERALL, FULL)).toBe(SCREEN.MOBILITY);
    expect(nextScreen(SCREEN.MOBILITY, FULL)).toBe(SCREEN.HOTELS);
    expect(nextScreen(SCREEN.HOTELS, FULL)).toBe(SCREEN.GOLF);
    expect(nextScreen(SCREEN.GOLF, FULL)).toBe(SCREEN.CONCLUSION);
    expect(nextScreen(SCREEN.CONCLUSION, FULL)).toBe(SCREEN.THANKS);
  });

  it("skips straight from overall to hotels when no mobility was booked", () => {
    expect(nextScreen(SCREEN.OVERALL, HOTELS_ONLY)).toBe(SCREEN.HOTELS);
    expect(nextScreen(SCREEN.HOTELS, HOTELS_ONLY)).toBe(SCREEN.CONCLUSION);
  });

  it("skips hotels when only golf was booked", () => {
    const golfOnly = context({
      hasGolf: true,
      golfCourses: [{ reservationId: "g1", name: "Golf One" }]
    });
    expect(nextScreen(SCREEN.OVERALL, golfOnly)).toBe(SCREEN.GOLF);
  });

  it("goes overall straight to conclusion when nothing else applies", () => {
    expect(nextScreen(SCREEN.OVERALL, context())).toBe(SCREEN.CONCLUSION);
  });
});

describe("backward navigation", () => {
  it("reverses the exact forward path", () => {
    expect(previousScreen(SCREEN.THANKS, FULL)).toBe(SCREEN.CONCLUSION);
    expect(previousScreen(SCREEN.CONCLUSION, FULL)).toBe(SCREEN.GOLF);
    expect(previousScreen(SCREEN.GOLF, FULL)).toBe(SCREEN.HOTELS);
    expect(previousScreen(SCREEN.HOTELS, FULL)).toBe(SCREEN.MOBILITY);
    expect(previousScreen(SCREEN.MOBILITY, FULL)).toBe(SCREEN.OVERALL);
  });

  it("skips the same screens going back as going forward", () => {
    expect(previousScreen(SCREEN.CONCLUSION, HOTELS_ONLY)).toBe(SCREEN.HOTELS);
    expect(previousScreen(SCREEN.HOTELS, HOTELS_ONLY)).toBe(SCREEN.OVERALL);
  });

  it("reports null from the first screen so the caller can decide what back means", () => {
    expect(previousScreen(SCREEN.OVERALL, FULL)).toBeNull();
  });
});

describe("progress", () => {
  it("counts only the screens this guest will see", () => {
    expect(progressFor(SCREEN.OVERALL, HOTELS_ONLY)).toEqual({
      step: 1,
      total: 3,
      percent: 33
    });
    expect(progressFor(SCREEN.HOTELS, HOTELS_ONLY)).toEqual({
      step: 2,
      total: 3,
      percent: 67
    });
    expect(progressFor(SCREEN.CONCLUSION, HOTELS_ONLY)).toEqual({
      step: 3,
      total: 3,
      percent: 100
    });
  });

  it("reaches 100 percent on the last screen of a full itinerary", () => {
    expect(progressFor(SCREEN.CONCLUSION, FULL)).toEqual({
      step: 5,
      total: 5,
      percent: 100
    });
  });

  it("reports nothing for a screen this guest never sees", () => {
    expect(progressFor(SCREEN.GOLF, HOTELS_ONLY)).toEqual({
      step: 0,
      total: 0,
      percent: 0
    });
  });

  it("knows which screen submits", () => {
    expect(isLastQuestionScreen(SCREEN.CONCLUSION, FULL)).toBe(true);
    expect(isLastQuestionScreen(SCREEN.GOLF, FULL)).toBe(false);
  });
});

describe("conditional reveals", () => {
  it("reveals a comment box at 8 and below, never at 9 or 10", () => {
    expect(shouldShowComment(8)).toBe(true);
    expect(shouldShowComment(1)).toBe(true);
    expect(shouldShowComment(9)).toBe(false);
    expect(shouldShowComment(10)).toBe(false);
  });

  it("expands hotel sub-ratings below 9, matching the spec boundary", () => {
    expect(shouldExpandHotelDetail(8)).toBe(true);
    expect(shouldExpandHotelDetail(9)).toBe(false);
  });

  it("offers the public review only to promoters", () => {
    expect(earnsPublicReview(10)).toBe(true);
    expect(earnsPublicReview(9)).toBe(true);
    expect(earnsPublicReview(8)).toBe(false);
  });

  it("ignores values that are not scores", () => {
    [undefined, null, 0, 11, "9"].forEach((v) => {
      expect(shouldShowComment(v)).toBe(false);
    });
    [undefined, null, -1, 11, "9"].forEach((v) => {
      expect(earnsPublicReview(v)).toBe(false);
    });
  });

  it("takes 0 as a real recommendation, as NPS does, but not as a rating", () => {
    expect(isNps(0)).toBe(true);
    expect(earnsPublicReview(0)).toBe(false);
    expect(shouldShowComment(0)).toBe(false);
  });
});

describe("payload assembly", () => {
  const base = {
    context: FULL,
    bookingNumber: "GX-1",
    secret: "s3cret",
    answers: {
      overallExperience: 10,
      consultation: 10,
      recommendation: 10,
      flight: { score: 10 },
      transfer: { score: 10 },
      rentalCar: { score: 10 },
      hotels: { h1: { score: 10 } },
      golfCourses: { g1: { score: 10 } }
    }
  };

  it("carries the credentials and the core scores", () => {
    const p = buildPayload(base);
    expect(p.bookingNumber).toBe("GX-1");
    expect(p.secret).toBe("s3cret");
    expect(p.overallExperience).toBe(10);
    expect(p.recommendation).toBe(10);
    expect(p.language).toBe("DE");
  });

  /**
   * Nothing is pre-selected any more, so nothing may be invented here either:
   * a rating the guest never chose is left out, not sent as a 10.
   */
  it("sends no score for a rating the guest never chose", () => {
    const p = buildPayload({
      ...base,
      answers: {
        overallExperience: 10,
        consultation: null,
        recommendation: 10,
        hotels: {},
        golfCourses: {}
      }
    });

    expect(p.consultation).toBeNull();
    expect(p.hotels).toEqual([]);
    expect(p.golfCourses).toEqual([]);
    expect(p.flight).toBeNull();
    expect(p.transfer).toBeNull();
    expect(p.rentalCar).toBeNull();
  });

  it("sends a recommendation of 0 as 0, not as missing", () => {
    const p = buildPayload({
      ...base,
      answers: { ...base.answers, recommendation: 0 }
    });
    expect(p.recommendation).toBe(0);
  });

  it("keeps an explicit low score rather than defaulting it", () => {
    const p = buildPayload({
      ...base,
      answers: { ...base.answers, hotels: { h1: { score: 3 } } }
    });
    expect(p.hotels[0].score).toBe(3);
  });

  it("omits sections the guest never saw", () => {
    const p = buildPayload({ ...base, context: HOTELS_ONLY });
    expect(p.flight).toBeUndefined();
    expect(p.transfer).toBeUndefined();
    expect(p.rentalCar).toBeUndefined();
    expect(p.golfCourses).toBeUndefined();
    expect(p.hotels).toHaveLength(1);
  });

  it("sends a comment only when the score earned the follow-up", () => {
    const high = buildPayload({
      ...base,
      answers: {
        ...base.answers,
        overallExperience: 10,
        overallExperienceComment: "never asked for"
      }
    });
    expect(high.overallExperienceComment).toBeUndefined();

    const low = buildPayload({
      ...base,
      answers: {
        ...base.answers,
        overallExperience: 6,
        overallExperienceComment: "Zimmer war laut"
      }
    });
    expect(low.overallExperienceComment).toBe("Zimmer war laut");
  });

  it("includes hotel sub-ratings only below 9", () => {
    const sub = { Room: 5, Service: 6, Catering: 7, Cleanliness: 8 };

    const good = buildPayload({
      ...base,
      answers: { ...base.answers, hotels: { h1: { score: 9, sub } } }
    });
    expect(good.hotels[0].sub).toBeUndefined();

    const poor = buildPayload({
      ...base,
      answers: { ...base.answers, hotels: { h1: { score: 8, sub } } }
    });
    expect(poor.hotels[0].sub).toEqual(sub);
  });

  it("pairs each rating with the reservation it belongs to", () => {
    const p = buildPayload(base);
    expect(p.hotels[0]).toMatchObject({
      reservationId: "h1",
      itemName: "Hotel Alpha",
      score: 10
    });
    expect(p.golfCourses[0]).toMatchObject({
      reservationId: "g1",
      itemName: "Golf One"
    });
  });

  it("normalises blank free text to null rather than empty strings", () => {
    const p = buildPayload({
      ...base,
      answers: {
        ...base.answers,
        nextDestination: "   ",
        improvementSuggestions: "  St Andrews  "
      }
    });
    expect(p.nextDestination).toBeNull();
    expect(p.improvementSuggestions).toBe("St Andrews");
  });

  /** The detail panel is optional: an untouched sub-scale is not a score. */
  it("sends no sub-ratings when none were chosen", () => {
    const p = buildPayload({
      ...base,
      answers: { ...base.answers, hotels: { h1: { score: 5 } } }
    });

    expect(p.hotels[0].score).toBe(5);
    expect(p.hotels[0].sub).toBeUndefined();
  });

  it("sends only the sub-ratings the guest chose", () => {
    const p = buildPayload({
      ...base,
      answers: {
        ...base.answers,
        hotels: { h1: { score: 4, sub: { Room: 2, Catering: 9 } } }
      }
    });

    expect(p.hotels[0].sub).toEqual({ Room: 2, Catering: 9 });
  });
});

describe("ratings still to choose", () => {
  it("names both screen-1 questions until they are answered", () => {
    expect(unansweredOn(SCREEN.OVERALL, FULL, {})).toEqual([
      "overallExperience",
      "consultation"
    ]);
    expect(
      unansweredOn(SCREEN.OVERALL, FULL, {
        overallExperience: 6,
        consultation: 9
      })
    ).toEqual([]);
  });

  it("asks only about the mobility services that were booked", () => {
    expect(
      unansweredOn(SCREEN.MOBILITY, { ...FULL, hasRentalCar: false }, {})
    ).toEqual(["flight", "transfer"]);
  });

  it("names each unrated hotel and course by its reservation", () => {
    expect(unansweredOn(SCREEN.HOTELS, FULL, { hotels: {} })).toEqual([
      "hotel:h1"
    ]);
    expect(
      unansweredOn(SCREEN.GOLF, FULL, { golfCourses: { g1: { score: 8 } } })
    ).toEqual([]);
  });

  it("accepts 0 for the recommendation, but needs an answer", () => {
    expect(unansweredOn(SCREEN.CONCLUSION, FULL, {})).toEqual([
      "recommendation"
    ]);
    expect(
      unansweredOn(SCREEN.CONCLUSION, FULL, { recommendation: 0 })
    ).toEqual([]);
  });

  it("never asks about the hotel sub-ratings or any comment", () => {
    expect(
      unansweredOn(SCREEN.HOTELS, FULL, { hotels: { h1: { score: 4 } } })
    ).toEqual([]);
  });
});

describe("dates shown to the guest", () => {
  it("writes an ISO date the way a German guest reads it", () => {
    expect(germanDate("2026-09-04")).toBe("4. September 2026");
    expect(germanDate("2026-03-21")).toBe("21. März 2026");
  });

  it("passes anything that is not an ISO date through unchanged", () => {
    expect(germanDate("04.09.2026")).toBe("04.09.2026");
    expect(germanDate(null)).toBe("");
  });
});
