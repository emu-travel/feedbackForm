import { createElement } from "lwc";
import GxFeedbackDashboard from "c/gxFeedbackDashboard";
import getDashboard from "@salesforce/apex/GxFeedbackDashboardController.getDashboard";
import getFilterOptions from "@salesforce/apex/GxFeedbackDashboardController.getFilterOptions";
import findResponses from "@salesforce/apex/GxFeedbackDashboardController.findResponses";
import findWaiting from "@salesforce/apex/GxFeedbackDashboardController.findWaiting";
import exportResponses from "@salesforce/apex/GxFeedbackDashboardController.exportResponses";
import getVenueDetail from "@salesforce/apex/GxFeedbackDashboardController.getVenueDetail";
import updateFollowUp from "@salesforce/apex/GxFeedbackDashboardController.updateFollowUp";
import GxResponseModal from "c/gxResponseModal";

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
  "@salesforce/apex/GxFeedbackDashboardController.findResponses",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/GxFeedbackDashboardController.findWaiting",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/GxFeedbackDashboardController.exportResponses",
  () => ({ default: jest.fn() }),
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
  "@salesforce/apex/GxFeedbackDashboardController.getResponseDetail",
  () => ({ default: jest.fn(() => Promise.resolve(null)) }),
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

describe("c-gx-feedback-dashboard at volume", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.restoreAllMocks();
    jest.clearAllMocks();
  });

  const manyComments = Array.from({ length: 23 }, (_, i) => ({
    key: `c${i + 1}`,
    responseId: `r${i + 1}`,
    text: `Kommentar ${i + 1}`,
    score: 5,
    scoreKind: "score"
  }));

  it("shows a long list ten at a time", async () => {
    const el = mount();
    getDashboard.emit({ ...DATA, comments: manyComments });
    await flush();

    expect(el.shadowRoot.querySelectorAll("li.comment")).toHaveLength(10);
    const pager = el.shadowRoot.querySelector(
      'c-gx-pager[data-list="comments"]'
    );
    expect(pager.total).toBe(23);

    pager.dispatchEvent(new CustomEvent("pagechange", { detail: { page: 3 } }));
    await flush();

    const shown = [...el.shadowRoot.querySelectorAll("li.comment")];
    expect(shown).toHaveLength(3);
    expect(shown[0].textContent).toContain("Kommentar 21");
  });

  it("starts every list again on page one when a filter changes", async () => {
    const el = mount();
    getDashboard.emit({ ...DATA, comments: manyComments });
    await flush();
    el.shadowRoot
      .querySelector('c-gx-pager[data-list="comments"]')
      .dispatchEvent(new CustomEvent("pagechange", { detail: { page: 3 } }));
    await flush();

    const region = [
      ...el.shadowRoot.querySelectorAll("lightning-combobox")
    ].find((c) => c.dataset.field === "region");
    region.dispatchEvent(
      new CustomEvent("change", { detail: { value: "Algarve" } })
    );
    getDashboard.emit({ ...DATA, comments: manyComments });
    await flush();

    expect(
      el.shadowRoot.querySelector('c-gx-pager[data-list="comments"]').page
    ).toBe(1);
  });

  it("says when a list was cut short, and where the rest are", async () => {
    const el = mount();
    getDashboard.emit({
      ...DATA,
      followUpsTotal: 612,
      commentsCapped: true,
      destinationsCapped: true
    });
    await flush();

    expect(text(el)).toContain("Showing 1 of 612 unhappy guests");
    expect(text(el)).toContain("The most recent comments.");
    expect(text(el)).toContain("From the most recent responses.");
  });

  it("says nothing about caps when nothing was left out", async () => {
    const el = mount();
    getDashboard.emit({ ...DATA, followUpsTotal: 1 });
    await flush();
    expect(text(el)).not.toContain("Narrow the dates to");
  });

  it("opens the whole response behind a follow-up, a comment or a wish", async () => {
    const open = jest
      .spyOn(GxResponseModal, "open")
      .mockResolvedValue(undefined);
    const el = mount();
    getDashboard.emit({
      ...DATA,
      comments: [{ ...DATA.comments[0], responseId: "a09" }]
    });
    await flush();

    const buttons = [...el.shadowRoot.querySelectorAll("button.full-btn")];
    expect(buttons.map((b) => b.dataset.responseId)).toEqual([
      "a01",
      "a02",
      "a09"
    ]);

    buttons[0].click();
    await flush();
    expect(open).toHaveBeenCalledWith(
      expect.objectContaining({ responseId: "a01", size: "medium" })
    );
  });
});

describe("c-gx-feedback-dashboard for the people who use it", () => {
  const PAGE = {
    total: 2,
    page: 1,
    pageSize: 10,
    searching: false,
    rows: [
      {
        responseId: "r1",
        reference: "FB-00016",
        bookingId: "b1",
        bookingNumber: "GX-TEST-A1",
        guest: "Ali Haider",
        designer: "Silke Bellgardt",
        region: "Algarve",
        tripEnd: "2026-09-08",
        nps: 10,
        overall: 9,
        lowestLabel: "Sixt GmbH & Co KG",
        lowestScore: 4,
        comments: 4
      },
      {
        responseId: "r2",
        reference: "FB-00015",
        bookingNumber: "GX-TEST-A3",
        guest: "Ali Haider",
        nps: 3,
        overall: 5,
        lowestScore: 5,
        lowestLabel: "Overall",
        comments: 0
      }
    ]
  };

  beforeEach(() => {
    jest.useFakeTimers();
  });

  afterEach(() => {
    jest.useRealTimers();
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.restoreAllMocks();
    jest.clearAllMocks();
  });

  const settle = async () => {
    for (let i = 0; i < 6; i++) {
      // eslint-disable-next-line no-await-in-loop
      await Promise.resolve();
    }
  };

  it("lists every response with what stood out in each", async () => {
    const el = mount();
    getDashboard.emit(DATA);
    findResponses.emit(PAGE);
    await settle();

    const rows = [...el.shadowRoot.querySelectorAll("li.rrow")];
    expect(rows).toHaveLength(2);
    expect(rows[0].textContent).toContain("Ali Haider");
    expect(rows[0].textContent).toContain("Silke Bellgardt");
    expect(rows[0].textContent).toContain("Lowest: Sixt GmbH & Co KG");
    expect(rows[0].textContent).toContain("4 comments");
    expect(rows[1].textContent).toContain("Follow-up: Open");
    expect(el.shadowRoot.querySelector(".panel-count").textContent).toBe(
      "2 responses"
    );
  });

  it("searches once typing pauses, from page one", async () => {
    const el = mount();
    getDashboard.emit(DATA);
    findResponses.emit(PAGE);
    await settle();

    const search = el.shadowRoot.querySelector("lightning-input.finder-search");
    search.dispatchEvent(
      new CustomEvent("change", { detail: { value: "Hai" } })
    );
    search.dispatchEvent(
      new CustomEvent("change", { detail: { value: "Haider " } })
    );
    await settle();
    expect(findResponses.getLastConfig().search).toBe("");

    jest.advanceTimersByTime(400);
    await settle();
    expect(findResponses.getLastConfig()).toEqual(
      expect.objectContaining({ search: "Haider", pageNumber: 1 })
    );
  });

  it("narrows the list to one group of guests", async () => {
    const el = mount();
    getDashboard.emit(DATA);
    findResponses.emit(PAGE);
    await settle();

    const chip = [...el.shadowRoot.querySelectorAll("button.chip")].find(
      (b) => b.dataset.value === "open"
    );
    chip.click();
    await settle();

    expect(findResponses.getLastConfig().groupName).toBe("open");
    expect(chip.getAttribute("aria-pressed")).toBe("true");
  });

  it("puts the unhappiest guests first on request", async () => {
    const el = mount();
    getDashboard.emit(DATA);
    await settle();

    el.shadowRoot
      .querySelector("lightning-combobox.finder-sort")
      .dispatchEvent(
        new CustomEvent("change", { detail: { value: "lowest" } })
      );
    await settle();

    expect(findResponses.getLastConfig().sortBy).toBe("lowest");
  });

  it("opens a listed response in full", async () => {
    const open = jest
      .spyOn(GxResponseModal, "open")
      .mockResolvedValue(undefined);
    const el = mount();
    getDashboard.emit(DATA);
    findResponses.emit(PAGE);
    await settle();

    el.shadowRoot.querySelector("li.rrow button.full-btn").click();
    await settle();

    expect(open).toHaveBeenCalledWith(
      expect.objectContaining({ responseId: "r1" })
    );
  });

  it("narrows the whole dashboard to one travel designer, and back", async () => {
    const el = mount();
    getDashboard.emit({
      ...DATA,
      designers: [
        {
          id: "005A",
          name: "Silke Bellgardt",
          responses: 3,
          consultation: 9,
          nps: 33
        },
        { id: "none", name: "No travel designer", responses: 1 }
      ]
    });
    await settle();

    const silke = [...el.shadowRoot.querySelectorAll(".dtable button")].find(
      (b) => b.dataset.id === "005A"
    );
    silke.click();
    await settle();
    expect(JSON.parse(getDashboard.getLastConfig().filtersJson).designer).toBe(
      "005A"
    );
    expect(JSON.parse(findResponses.getLastConfig().filtersJson).designer).toBe(
      "005A"
    );

    silke.click();
    await settle();
    expect(
      JSON.parse(getDashboard.getLastConfig().filtersJson).designer
    ).toBeUndefined();
  });
});

describe("c-gx-feedback-dashboard exports and chases", () => {
  const originalCreate = URL.createObjectURL;
  const originalRevoke = URL.revokeObjectURL;

  beforeEach(() => {
    URL.createObjectURL = jest.fn(() => "blob:feedback");
    URL.revokeObjectURL = jest.fn();
  });

  afterEach(() => {
    URL.createObjectURL = originalCreate;
    URL.revokeObjectURL = originalRevoke;
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.restoreAllMocks();
    jest.clearAllMocks();
  });

  const PAGE = {
    total: 1,
    page: 1,
    pageSize: 10,
    rows: [{ responseId: "r1", guest: "Ali Haider", nps: 10 }]
  };

  function exportButton(el) {
    return el.shadowRoot.querySelector("lightning-button.export-btn");
  }

  it("exports what the list is showing, all of it, as a download", async () => {
    exportResponses.mockResolvedValue({
      csv: '"Feedback number"\r\n"FB-1"',
      fileName: "golf-extra-feedback-2026-09-11.csv",
      rows: 1,
      total: 1
    });
    const clicked = jest
      .spyOn(HTMLAnchorElement.prototype, "click")
      .mockImplementation(() => {});
    const el = mount();
    getDashboard.emit(DATA);
    findResponses.emit(PAGE);
    await flush();

    const chip = [...el.shadowRoot.querySelectorAll("button.chip")].find(
      (b) => b.dataset.value === "detractors"
    );
    chip.click();
    await flush();
    exportButton(el).click();
    await flush();

    expect(exportResponses).toHaveBeenCalledWith(
      expect.objectContaining({ groupName: "detractors", sortBy: "newest" })
    );
    expect(URL.createObjectURL).toHaveBeenCalled();
    expect(clicked).toHaveBeenCalled();
  });

  it("offers no export when there is nothing to export", async () => {
    const el = mount();
    getDashboard.emit(DATA);
    findResponses.emit({ ...PAGE, total: 0, rows: [] });
    await flush();
    expect(exportButton(el).disabled).toBe(true);
  });

  it("lists the guests still to answer, and what happens next", async () => {
    const el = mount();
    getDashboard.emit(DATA);
    findWaiting.emit({
      total: 1,
      page: 1,
      pageSize: 10,
      rows: [
        {
          bookingId: "b9",
          bookingNumber: "GX-TEST-A2",
          guest: "Ali Haider",
          lastSent: "2026-09-11T14:02:27.000Z",
          reminded: false,
          reminderDue: "2026-09-21",
          expiresOn: "2026-09-25",
          state: "waiting"
        }
      ]
    });
    await flush();

    const row = el.shadowRoot.querySelector("li.wrow");
    expect(row.textContent).toContain("GX-TEST-A2");
    expect(row.textContent).toContain("Reminder due 21 Sep 2026");
    expect(text(el)).toContain("1 guest not answered yet");
  });

  it("follows the dashboard filters, from page one", async () => {
    const el = mount();
    getDashboard.emit(DATA);
    await flush();

    const region = [
      ...el.shadowRoot.querySelectorAll("lightning-combobox")
    ].find((c) => c.dataset.field === "region");
    region.dispatchEvent(
      new CustomEvent("change", { detail: { value: "Algarve" } })
    );
    await flush();

    const config = findWaiting.getLastConfig();
    expect(JSON.parse(config.filtersJson).region).toBe("Algarve");
    expect(config.pageNumber).toBe(1);
  });
});
