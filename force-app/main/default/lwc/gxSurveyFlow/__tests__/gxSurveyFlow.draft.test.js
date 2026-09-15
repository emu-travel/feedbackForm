import {
  SCREEN,
  DRAFT_MAX_AGE_DAYS,
  draftKey,
  makeDraft,
  readDraft
} from "c/gxSurveyFlow";

const DAY = 24 * 60 * 60 * 1000;
const NOW = Date.UTC(2026, 8, 15, 9, 0, 0);

const CTX = {
  hasFlight: true,
  hasTransfers: false,
  hasRentalCar: false,
  hasHotels: true,
  hasGolf: false,
  flightSuppliers: ["Lufthansa"],
  hotels: [{ reservationId: "h1", name: "Hotel Alpha" }],
  golfCourses: []
};

const ANSWERS = {
  overallExperience: 9,
  overallExperienceComment: "",
  consultation: 7,
  consultationComment: "Mehr Auswahl",
  flight: { score: 8, comment: "Verspätet" },
  transfer: { score: null, comment: "" },
  rentalCar: { score: null, comment: "" },
  hotels: {
    h1: { score: 6, comment: "Laut", sub: { Room: 5, Bogus: 3 } },
    gone: { score: 4 }
  },
  golfCourses: {},
  generalHotelComment: "Frühstück gut",
  generalGolfComment: "",
  recommendation: null,
  nextDestination: "Schottland",
  improvementSuggestions: ""
};

const saved = (overrides = {}) =>
  makeDraft({
    secret: "s3cret",
    screen: SCREEN.HOTELS,
    answers: ANSWERS,
    now: NOW,
    ...overrides
  });

describe("answers saved on the guest's device", () => {
  it("keys the draft by booking number", () => {
    expect(draftKey("GX-TEST-D1")).toBe("gxFeedbackDraft:GX-TEST-D1");
  });

  it("does not keep the link's secret on the device", () => {
    expect(saved()).not.toContain("s3cret");
  });

  it("comes back as it was saved, on the step the guest was on", () => {
    const draft = readDraft(saved(), {
      secret: "s3cret",
      context: CTX,
      now: NOW + DAY
    });
    expect(draft.screen).toBe(SCREEN.HOTELS);
    expect(draft.answers.overallExperience).toBe(9);
    expect(draft.answers.consultationComment).toBe("Mehr Auswahl");
    expect(draft.answers.flight).toEqual({ score: 8, comment: "Verspätet" });
    expect(draft.answers.hotels.h1).toEqual({
      score: 6,
      comment: "Laut",
      sub: { Room: 5 }
    });
    expect(draft.answers.generalHotelComment).toBe("Frühstück gut");
    expect(draft.answers.nextDestination).toBe("Schottland");
  });

  it("drops hotels and courses no longer on the booking", () => {
    const draft = readDraft(saved(), {
      secret: "s3cret",
      context: CTX,
      now: NOW
    });
    expect(Object.keys(draft.answers.hotels)).toEqual(["h1"]);
  });

  it("is not restored for another link to the same booking", () => {
    expect(
      readDraft(saved(), { secret: "other", context: CTX, now: NOW })
    ).toBeNull();
  });

  it("lasts as long as the link, and no longer", () => {
    const opts = (days) => ({
      secret: "s3cret",
      context: CTX,
      now: NOW + days * DAY
    });
    expect(readDraft(saved(), opts(DRAFT_MAX_AGE_DAYS - 1))).not.toBeNull();
    expect(readDraft(saved(), opts(DRAFT_MAX_AGE_DAYS + 1))).toBeNull();
  });

  it("goes back to the first step that still misses a rating", () => {
    const draft = readDraft(
      saved({
        screen: SCREEN.CONCLUSION,
        answers: { ...ANSWERS, consultation: null }
      }),
      { secret: "s3cret", context: CTX, now: NOW }
    );
    expect(draft.screen).toBe(SCREEN.OVERALL);
  });

  it("starts at the first step when the saved step is not part of this trip", () => {
    const draft = readDraft(saved({ screen: SCREEN.GOLF }), {
      secret: "s3cret",
      context: CTX,
      now: NOW
    });
    expect(draft.screen).toBe(SCREEN.OVERALL);
  });

  it("keeps nothing that is not a valid score", () => {
    const draft = readDraft(
      saved({
        answers: { ...ANSWERS, overallExperience: 11, consultation: "7" }
      }),
      { secret: "s3cret", context: CTX, now: NOW }
    );
    expect(draft.answers.overallExperience).toBeNull();
    expect(draft.answers.consultation).toBeNull();
  });

  it("has nothing to restore for an untouched survey", () => {
    expect(
      readDraft(saved({ answers: {} }), {
        secret: "s3cret",
        context: CTX,
        now: NOW
      })
    ).toBeNull();
  });

  it("ignores anything that is not a saved survey", () => {
    const opts = { secret: "s3cret", context: CTX, now: NOW };
    expect(readDraft(null, opts)).toBeNull();
    expect(readDraft("not json", opts)).toBeNull();
    expect(readDraft('{"v":1}', opts)).toBeNull();
  });
});
