import {
  formatNps,
  formatScore,
  formatPercent,
  toneFor,
  isOpenFollowUp,
  defaultFilters,
  filtersPayload,
  withAll,
  kpiTiles,
  trendBars,
  venueList,
  heatRows,
  followUpRows,
  destinationRows,
  commentRows,
  drillRows,
  bookingUrl,
  monthLabel,
  plural,
  npsToneFor
} from "c/gxDashboardView";

describe("number formatting", () => {
  it("gives NPS its sign, and a dash when there is none", () => {
    expect(formatNps(25)).toBe("+25");
    expect(formatNps(0)).toBe("0");
    expect(formatNps(-10)).toBe("−10");
    expect(formatNps(null)).toBe("—");
    expect(formatNps(undefined)).toBe("—");
  });

  it("shows scores to one decimal and missing ones as a dash", () => {
    expect(formatScore(8)).toBe("8.0");
    expect(formatScore(8.666)).toBe("8.7");
    expect(formatScore(null)).toBe("—");
  });

  it("rounds percentages", () => {
    expect(formatPercent(80)).toBe("80%");
    expect(formatPercent(66.6)).toBe("67%");
    expect(formatPercent(null)).toBe("—");
  });

  it("labels months", () => {
    expect(monthLabel(2026, 7)).toBe("Jul 2026");
  });
});

describe("heatmap bands", () => {
  it("puts below 7 in red, 7 to under 8 in amber, 8 and up in green", () => {
    expect(toneFor(6.9)).toBe("bad");
    expect(toneFor(7)).toBe("mid");
    expect(toneFor(7.9)).toBe("mid");
    expect(toneFor(8)).toBe("good");
    expect(toneFor(null)).toBe("none");
  });
});

describe("follow-up state", () => {
  it("treats blank and Open as open work, Contacted and Resolved as handled", () => {
    expect(isOpenFollowUp(undefined)).toBe(true);
    expect(isOpenFollowUp(null)).toBe(true);
    expect(isOpenFollowUp("Open")).toBe(true);
    expect(isOpenFollowUp("Contacted")).toBe(false);
    expect(isOpenFollowUp("Resolved")).toBe(false);
  });
});

describe("filters", () => {
  it("defaults to the last twelve months of trips", () => {
    const f = defaultFilters(new Date(2026, 8, 11));
    expect(f.fromDate).toBe("2025-09-11");
    expect(f.toDate).toBe("2026-09-11");
    expect(f.region).toBe("");
  });

  it("sends only the filters that are set, so an empty choice means all", () => {
    const json = filtersPayload({
      fromDate: "2026-01-01",
      region: "",
      country: null,
      category: "Hotel"
    });
    expect(JSON.parse(json)).toEqual({
      fromDate: "2026-01-01",
      category: "Hotel"
    });
  });

  it("puts an all option first", () => {
    expect(
      withAll([{ label: "Algarve", value: "Algarve" }], "All regions")
    ).toEqual([
      { label: "All regions", value: "" },
      { label: "Algarve", value: "Algarve" }
    ]);
  });
});

describe("KPI tiles", () => {
  it("formats every tile and flags open follow-ups", () => {
    const tiles = kpiTiles({
      responses: 4,
      invited: 5,
      answeredInvitations: 4,
      responseRate: 80,
      nps: 25,
      promoters: 2,
      detractors: 1,
      avgOverall: 8,
      avgConsultation: 8,
      reminded: 1,
      answeredAfterReminder: 1,
      openFollowUps: 1
    });
    const byKey = Object.fromEntries(tiles.map((t) => [t.key, t]));
    expect(byKey.responses.value).toBe("4");
    expect(byKey.rate.value).toBe("80%");
    expect(byKey.rate.note).toBe("1 still open");
    expect(byKey.nps.value).toBe("+25");
    expect(byKey.followups.alert).toBe(true);
  });

  it("shows an empty selection as dashes and zeros, never as a crash", () => {
    const byKey = Object.fromEntries(
      kpiTiles(undefined).map((t) => [t.key, t])
    );
    expect(byKey.responses.value).toBe("0");
    expect(byKey.nps.value).toBe("—");
    expect(byKey.followups.alert).toBe(false);
  });
});

describe("trend", () => {
  it("sizes each segment by its share of the month, so months stay comparable", () => {
    const [m] = trendBars([
      {
        key: "2026-07",
        year: 2026,
        month: 7,
        promoters: 1,
        passives: 1,
        detractors: 2,
        total: 4,
        nps: -25
      }
    ]);
    expect(m.label).toBe("Jul 2026");
    expect(m.promoterStyle).toBe("width:25%");
    expect(m.detractorStyle).toBe("width:50%");
    expect(m.nps).toBe("−25");
  });
});

describe("venue leaderboard", () => {
  const venues = [
    {
      category: "Hotel",
      name: "Conrad Algarve",
      average: 7.0,
      ratings: 3,
      ranked: true
    },
    {
      category: "Hotel",
      name: "Pine Cliffs",
      average: 8.9,
      ratings: 5,
      ranked: true
    },
    {
      category: "Hotel",
      name: "Finca Serena",
      average: 10,
      ratings: 1,
      ranked: false
    }
  ];

  it("keeps venues with too few ratings out of the ranking without hiding them", () => {
    const { ranked, unranked } = venueList(venues);
    expect(ranked.map((v) => v.name)).toEqual([
      "Conrad Algarve",
      "Pine Cliffs"
    ]);
    expect(unranked.map((v) => v.name)).toEqual(["Finca Serena"]);
    expect(unranked[0].ratingsLabel).toBe("1 rating");
  });

  it("flags only ranked venues scoring under 7.5", () => {
    const { ranked, unranked } = venueList(venues);
    expect(ranked[0].low).toBe(true);
    expect(ranked[1].low).toBe(false);
    expect(unranked[0].low).toBe(false);
  });

  it("draws the bar out of ten", () => {
    expect(venueList(venues).ranked[0].barStyle).toBe("width:70%");
  });
});

describe("hotel detail heatmap", () => {
  it("colours each cell by its band", () => {
    const [row] = heatRows([
      {
        hotel: "Conrad Algarve",
        cells: [
          { subCategory: "Room", average: 6, ratings: 2 },
          { subCategory: "Service", average: 7.5, ratings: 2 },
          { subCategory: "Catering", average: 8, ratings: 2 },
          { subCategory: "Cleanliness", average: null, ratings: 0 }
        ]
      }
    ]);
    expect(row.cells.map((c) => c.cls)).toEqual([
      "heat heat_bad",
      "heat heat_mid",
      "heat heat_good",
      "heat heat_none"
    ]);
    expect(row.cells[3].title).toBe("No ratings");
  });
});

describe("follow-up list", () => {
  const rows = [
    { responseId: "a", nps: 3, followUpStatus: null, bookingId: "b1" },
    { responseId: "b", nps: 5, followUpStatus: "Resolved", bookingId: "b2" }
  ];

  it("shows only open cases unless asked for handled ones too", () => {
    expect(followUpRows(rows, false).map((r) => r.key)).toEqual(["a"]);
    expect(followUpRows(rows, true).map((r) => r.key)).toEqual(["a", "b"]);
  });

  it("treats a blank status as Open and links the booking", () => {
    const [r] = followUpRows(rows, false);
    expect(r.status).toBe("Open");
    expect(r.url).toBe("/lightning/r/Booking__c/b1/view");
    expect(r.comment).toBe("No comment left.");
  });
});

describe("other lists", () => {
  it("marks promoters among next-destination wishes", () => {
    const rows = destinationRows([
      { responseId: "a", nps: 10, nextDestination: "Schottland" },
      { responseId: "b", nps: 6, nextDestination: "Japan" }
    ]);
    expect(rows[0].promoter).toBe(true);
    expect(rows[1].promoter).toBe(false);
  });

  it("colours a comment by the score it came with", () => {
    const [c] = commentRows([
      { key: "k", text: "Laut", score: 5, about: "Conrad" }
    ]);
    expect(c.cls).toBe("pill pill_bad");
    expect(c.score).toBe("5.0");
  });

  it("keeps a comment with no score uncoloured", () => {
    const [c] = commentRows([{ key: "k", text: "Toll", score: null }]);
    expect(c.score).toBeNull();
    expect(c.cls).toBe("pill pill_none");
  });

  it("lists each guest's sub-scores in the drill-down", () => {
    const [r] = drillRows([
      {
        responseId: "r1",
        score: 5,
        subScores: [{ subCategory: "Room", average: 4 }]
      }
    ]);
    expect(r.score).toBe("5.0");
    expect(r.subs[0]).toEqual({ key: "r1|Room", label: "Room", value: "4.0" });
  });

  it("has no link without a booking", () => {
    expect(bookingUrl(null)).toBeNull();
  });
});

describe("copy and labelling fixes from the first review", () => {
  it("uses singular and plural correctly", () => {
    expect(plural(1, "detractor", "detractors")).toBe("1 detractor");
    expect(plural(2, "detractor", "detractors")).toBe("2 detractors");
    expect(plural(0, "detractor", "detractors")).toBe("0 detractors");
  });

  it("says 1 detractor and 1 unhappy guest, not 1 detractors", () => {
    const byKey = Object.fromEntries(
      kpiTiles({ promoters: 2, detractors: 1, openFollowUps: 1 }).map((t) => [
        t.key,
        t
      ])
    );
    expect(byKey.nps.note).toBe("2 promoters · 1 detractor");
    expect(byKey.followups.note).toBe("unhappy guest not yet contacted");
  });

  it("never leaves a gap where a follow-up guest's name should be", () => {
    const [r] = followUpRows([{ responseId: "a", nps: 5, overall: 6 }], false);
    expect(r.detail).toBe("Guest · overall 6.0");
  });

  it("labels an NPS answer as NPS, not as a 1-10 score", () => {
    const [c] = commentRows([
      { key: "k", text: "Zu laut", score: 5, scoreKind: "nps" }
    ]);
    expect(c.score).toBe("NPS 5");
  });

  it("colours NPS answers by NPS bands, so an 8 is a passive", () => {
    expect(npsToneFor(8)).toBe("mid");
    expect(npsToneFor(9)).toBe("good");
    expect(npsToneFor(6)).toBe("bad");
    const [passive] = commentRows([
      { key: "k", text: "Ok", score: 8, scoreKind: "nps" }
    ]);
    expect(passive.cls).toBe("pill pill_mid");
    const [rating] = commentRows([
      { key: "k", text: "Ok", score: 8, scoreKind: "score" }
    ]);
    expect(rating.cls).toBe("pill pill_good");
  });
});
