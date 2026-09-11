import { createElement } from "lwc";
import GxFeedbackDashboard from "c/gxFeedbackDashboard";
import getDashboard from "@salesforce/apex/GxFeedbackDashboardController.getDashboard";
import getFilterOptions from "@salesforce/apex/GxFeedbackDashboardController.getFilterOptions";
import getVenueDetail from "@salesforce/apex/GxFeedbackDashboardController.getVenueDetail";
import updateFollowUp from "@salesforce/apex/GxFeedbackDashboardController.updateFollowUp";

jest.mock(
  "@salesforce/apex/GxFeedbackDashboardController.getDashboard",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/GxFeedbackDashboardController.getFilterOptions",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/GxFeedbackDashboardController.getVenueDetail",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/GxFeedbackDashboardController.updateFollowUp",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex",
  () => ({ refreshApex: jest.fn(() => Promise.resolve()) }),
  { virtual: true }
);

const DATA = {
  minRatings: 3,
  kpis: {
    responses: 4,
    invited: 5,
    answeredInvitations: 4,
    responseRate: 80,
    promoters: 2,
    passives: 1,
    detractors: 1,
    nps: 25,
    avgOverall: 8,
    avgConsultation: 8,
    reminded: 1,
    answeredAfterReminder: 1,
    openFollowUps: 1
  },
  trend: [
    {
      key: "2026-07",
      year: 2026,
      month: 7,
      promoters: 1,
      passives: 0,
      detractors: 0,
      total: 1,
      nps: 100
    }
  ],
  hotels: [
    {
      category: "Hotel",
      name: "Conrad Algarve",
      average: 7,
      ratings: 3,
      ranked: true
    }
  ],
  golf: [],
  suppliers: [
    {
      category: "Airline",
      name: "Lufthansa",
      average: 7,
      ratings: 2,
      ranked: false
    }
  ],
  hotelDetail: [
    {
      hotel: "Conrad Algarve",
      cells: [
        { subCategory: "Room", average: 6, ratings: 2 },
        { subCategory: "Service", average: 7.5, ratings: 2 },
        { subCategory: "Catering", average: 8, ratings: 2 },
        { subCategory: "Cleanliness", average: 7.5, ratings: 2 }
      ]
    }
  ],
  followUps: [
    {
      responseId: "a01",
      bookingId: "b01",
      bookingNumber: "GXD-2",
      guest: "Test Gast",
      nps: 3,
      overall: 5,
      comment: "Zu laut",
      followUpStatus: null
    }
  ],
  nextDestinations: [
    {
      responseId: "a02",
      bookingId: "b02",
      bookingNumber: "GXD-1",
      guest: "Test Gast",
      nps: 10,
      nextDestination: "Schottland"
    }
  ],
  comments: [
    {
      key: "c1",
      text: "Laut",
      about: "Conrad Algarve",
      score: 5,
      bookingId: "b01",
      bookingNumber: "GXD-2",
      guest: "Test Gast"
    }
  ]
};

/** Several microtask turns: enough for a wire emit, or an awaited Apex call and the re-render after it. */
const flush = () =>
  Promise.resolve()
    .then(() => Promise.resolve())
    .then(() => Promise.resolve())
    .then(() => Promise.resolve());

function mount() {
  const el = createElement("c-gx-feedback-dashboard", {
    is: GxFeedbackDashboard
  });
  document.body.appendChild(el);
  return el;
}

function text(el) {
  return el.shadowRoot.textContent;
}

describe("c-gx-feedback-dashboard", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("shows the headline numbers once data arrives", async () => {
    const el = mount();
    getFilterOptions.emit({ regions: [], countries: [], travelTypes: [] });
    getDashboard.emit(DATA);
    await flush();

    const values = [...el.shadowRoot.querySelectorAll(".kpi-value")].map(
      (n) => n.textContent
    );
    expect(values).toContain("80%");
    expect(values).toContain("+25");
  });

  it("marks open follow-ups as needing attention", async () => {
    const el = mount();
    getDashboard.emit(DATA);
    await flush();
    expect(el.shadowRoot.querySelector(".kpi_alert")).not.toBeNull();
  });

  it("asks for the last twelve months by default", async () => {
    mount();
    await flush();
    const filters = JSON.parse(getDashboard.getLastConfig().filtersJson);
    expect(filters.fromDate).toBeDefined();
    expect(filters.toDate).toBeDefined();
    expect(filters.region).toBeUndefined();
  });

  it("explains an empty selection instead of drawing empty charts", async () => {
    const el = mount();
    getDashboard.emit({ ...DATA, kpis: { ...DATA.kpis, responses: 0 } });
    await flush();
    expect(text(el)).toContain("No feedback for these trips yet");
    expect(el.shadowRoot.querySelector(".trend")).toBeNull();
  });

  it("shows a readable error rather than a blank page", async () => {
    const el = mount();
    getDashboard.error({ message: "Insufficient access" });
    await flush();
    expect(el.shadowRoot.querySelector(".notice").textContent).toContain(
      "Insufficient access"
    );
  });

  it("lists the hotel detail, the unhappy guest and the next-destination wish", async () => {
    const el = mount();
    getDashboard.emit(DATA);
    await flush();
    const t = text(el);
    expect(t).toContain("Zu laut");
    expect(t).toContain("Schottland");
    expect(el.shadowRoot.querySelectorAll("td.heat").length).toBe(4);
  });

  it("saves a follow-up with the status and note the user set", async () => {
    updateFollowUp.mockResolvedValue();
    const el = mount();
    getDashboard.emit(DATA);
    await flush();

    const status = el.shadowRoot.querySelector("lightning-combobox.fu-status");
    status.dispatchEvent(
      new CustomEvent("change", { detail: { value: "Contacted" } })
    );
    const note = el.shadowRoot.querySelector("lightning-input.fu-note");
    note.dispatchEvent(
      new CustomEvent("change", { detail: { value: "Angerufen" } })
    );
    await flush();

    const save = [...el.shadowRoot.querySelectorAll("lightning-button")].find(
      (b) => b.label === "Save"
    );
    save.click();
    await flush();

    expect(updateFollowUp).toHaveBeenCalledWith({
      responseId: "a01",
      status: "Contacted",
      note: "Angerufen"
    });
  });

  it("opens every rating for a venue when it is selected", async () => {
    getVenueDetail.mockResolvedValue([
      {
        responseId: "r1",
        bookingId: "b01",
        bookingNumber: "GXD-2",
        guest: "Test Gast",
        score: 5,
        comment: "Laut",
        subScores: []
      }
    ]);
    const el = mount();
    getDashboard.emit(DATA);
    await flush();

    const board = el.shadowRoot.querySelector("c-gx-venue-board");
    board.dispatchEvent(
      new CustomEvent("select", {
        detail: { name: "Conrad Algarve", category: "Hotel" }
      })
    );
    await flush();
    await flush();

    expect(getVenueDetail).toHaveBeenCalledWith(
      expect.objectContaining({ category: "Hotel", itemName: "Conrad Algarve" })
    );
    expect(el.shadowRoot.querySelector(".drill-title").textContent).toContain(
      "Conrad Algarve"
    );
  });
});

describe("c-gx-feedback-dashboard usability", () => {
  const originalScroll = Element.prototype.scrollIntoView;

  beforeEach(() => {
    Element.prototype.scrollIntoView = jest.fn();
  });

  afterEach(() => {
    Element.prototype.scrollIntoView = originalScroll;
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("does not stamp a follow-up that nothing was changed on", async () => {
    const el = mount();
    getDashboard.emit(DATA);
    await flush();

    const save = [...el.shadowRoot.querySelectorAll("lightning-button")].find(
      (b) => b.label === "Save"
    );
    save.click();
    await flush();

    expect(updateFollowUp).not.toHaveBeenCalled();
  });

  it("takes you to the follow-up list from the open follow-ups tile", async () => {
    const el = mount();
    getDashboard.emit(DATA);
    await flush();

    el.shadowRoot.querySelector("button.kpi").click();
    await flush();

    expect(Element.prototype.scrollIntoView).toHaveBeenCalled();
  });

  it("opens a hotel from the detail grid as well as the leaderboard", async () => {
    getVenueDetail.mockResolvedValue([]);
    const el = mount();
    getDashboard.emit(DATA);
    await flush();

    el.shadowRoot.querySelector("button.link-btn").click();
    await flush();

    expect(getVenueDetail).toHaveBeenCalledWith(
      expect.objectContaining({ category: "Hotel", itemName: "Conrad Algarve" })
    );
  });

  it("filters the comments down to the low scores on request", async () => {
    const el = mount();
    getDashboard.emit({
      ...DATA,
      comments: [
        { key: "low", text: "Laut", score: 4, scoreKind: "score" },
        { key: "high", text: "Toll", score: 9, scoreKind: "score" }
      ]
    });
    await flush();
    expect(el.shadowRoot.querySelectorAll("li.comment").length).toBe(2);

    const toggle = [...el.shadowRoot.querySelectorAll("lightning-button")].find(
      (b) => b.label === "Only low scores"
    );
    toggle.click();
    await flush();

    const left = [...el.shadowRoot.querySelectorAll("li.comment")];
    expect(left.length).toBe(1);
    expect(left[0].textContent).toContain("Laut");
  });
});
