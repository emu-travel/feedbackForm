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
  npsToneFor,
  pageOf,
  rangeLabel,
  responseView,
  tripDates
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

describe("usability pass", () => {
  it("marks low-scoring comments, whichever scale the number is on", () => {
    const rows = commentRows([
      { key: "a", text: "x", score: 5, scoreKind: "nps" },
      { key: "b", text: "x", score: 7, scoreKind: "score" },
      { key: "c", text: "x", score: 5, scoreKind: "score" },
      { key: "d", text: "x", score: null }
    ]);
    expect(rows.map((r) => r.low)).toEqual([true, false, true, false]);
  });

  it("makes the open follow-ups tile a way into the list", () => {
    const tile = kpiTiles({ openFollowUps: 2 }).find(
      (t) => t.key === "followups"
    );
    expect(tile.target).toBe("followups");
    expect(tile.hint).toBeTruthy();
  });

  it("says who last touched a follow-up, and nothing when nobody has", () => {
    const [touched, untouched] = followUpRows(
      [
        { responseId: "a", nps: 3, followUpBy: "Ali Haider" },
        { responseId: "b", nps: 4 }
      ],
      true
    );
    expect(touched.updatedLabel).toBe("Last updated by Ali Haider");
    expect(untouched.updatedLabel).toBeNull();
  });
});

describe("paging", () => {
  const rows = Array.from({ length: 25 }, (_, i) => ({ key: `r${i + 1}` }));

  it("cuts a list into pages of ten", () => {
    const p = pageOf(rows, 2);
    expect(p.rows.map((r) => r.key)).toEqual([
      "r11",
      "r12",
      "r13",
      "r14",
      "r15",
      "r16",
      "r17",
      "r18",
      "r19",
      "r20"
    ]);
    expect(p.pages).toBe(3);
    expect(p.total).toBe(25);
  });

  it("never lands on a page the list no longer has", () => {
    expect(pageOf(rows.slice(0, 5), 3).page).toBe(1);
    expect(pageOf(rows, 99).page).toBe(3);
    expect(pageOf(rows, undefined).page).toBe(1);
    expect(pageOf(undefined, 2)).toEqual({
      rows: [],
      page: 1,
      pages: 1,
      total: 0
    });
  });

  it("says which rows are showing", () => {
    expect(rangeLabel(2, 57)).toBe("11–20 of 57");
    expect(rangeLabel(6, 57)).toBe("51–57 of 57");
    expect(rangeLabel(1, 0)).toBe("0 of 0");
  });
});

describe("one whole response", () => {
  const DETAIL = {
    responseId: "a01",
    reference: "FB-00013",
    guest: "Ali Haider",
    bookingId: "b01",
    bookingNumber: "GX-TEST-A1",
    region: "Algarve",
    country: "Portugal",
    tripStart: "2026-08-30",
    tripEnd: "2026-09-08",
    overall: 6,
    overallComment: "Zu viel Programm",
    consultation: 9,
    services: [
      { category: "Airline", name: "Lufthansa, Condor", score: 7 },
      { category: "TransferCompany", name: "Algarve Chauffeurs", score: 10 }
    ],
    hotels: [
      {
        name: "Conrad Algarve",
        score: 5,
        comment: "Laut",
        subScores: [
          { subCategory: "Room", average: 4 },
          { subCategory: "Cleanliness", average: 9 }
        ]
      }
    ],
    golf: [],
    generalHotelComment: "   ",
    recommendation: 4,
    npsCategory: "Detractor",
    nextDestination: "Schottland",
    improvementSuggestions: null,
    followUpStatus: "Contacted",
    followUpNote: "Angerufen",
    followUpBy: "Kaan"
  };

  it("lays the answer out screen by screen, leaving out screens the trip did not have", () => {
    const v = responseView(DETAIL);
    expect(v.sections.map((s) => s.key)).toEqual([
      "overall",
      "services",
      "hotels",
      "close"
    ]);
    expect(v.title).toBe("FB-00013 · Ali Haider");
    expect(v.tripLine).toBe(
      "GX-TEST-A1 · Algarve, Portugal · 30 Aug – 8 Sep 2026"
    );
  });

  it("colours each score and keeps the comment beside it", () => {
    const [overall, consult] = responseView(DETAIL).sections[0].items;
    expect(overall.score).toBe("6.0");
    expect(overall.cls).toBe("pill pill_bad");
    expect(overall.comment).toBe("Zu viel Programm");
    expect(consult.cls).toBe("pill pill_good");
    expect(consult.comment).toBeNull();
  });

  it("names each travel service and who provided it", () => {
    const services = responseView(DETAIL).sections[1].items;
    expect(services.map((s) => s.label)).toEqual([
      "Airline · Lufthansa, Condor",
      "Transfer · Algarve Chauffeurs"
    ]);
  });

  it("puts a hotel's detail ratings underneath it", () => {
    const [hotel] = responseView(DETAIL).sections[2].items;
    expect(hotel.subs.map((s) => `${s.label} ${s.value}`)).toEqual([
      "Room 4.0",
      "Cleanliness 9.0"
    ]);
  });

  it("keeps only the free text the guest actually wrote", () => {
    const v = responseView(DETAIL);
    expect(v.sections[2].texts).toEqual([]);
    expect(v.sections[3].texts.map((t) => t.label)).toEqual([
      "Next on their wish list"
    ]);
  });

  it("gives the recommendation its NPS group", () => {
    const [nps] = responseView(DETAIL).sections[3].items;
    expect(nps.score).toBe("4");
    expect(nps.tag).toBe("Detractor");
    expect(nps.cls).toBe("pill pill_bad");
  });

  it("shows what the team did about it, when they did something", () => {
    expect(responseView(DETAIL).followUp).toEqual({
      status: "Contacted",
      note: "Angerufen",
      by: "Kaan",
      on: null
    });
    expect(
      responseView({ ...DETAIL, followUpStatus: null, followUpNote: null })
        .followUp
    ).toBeNull();
  });

  it("writes trip dates briefly", () => {
    expect(tripDates("2026-08-30", "2026-09-08")).toBe("30 Aug – 8 Sep 2026");
    expect(tripDates("2026-12-28", "2027-01-04")).toBe(
      "28 Dec 2026 – 4 Jan 2027"
    );
    expect(tripDates(null, null)).toBe("");
  });

  it("has nothing to show for nothing", () => {
    expect(responseView(null)).toBeNull();
  });
});
