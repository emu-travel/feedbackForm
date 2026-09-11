import { createElement } from "lwc";
import GxResponseModal from "c/gxResponseModal";
import getResponseDetail from "@salesforce/apex/GxFeedbackDashboardController.getResponseDetail";

jest.mock(
  "@salesforce/apex/GxFeedbackDashboardController.getResponseDetail",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const DETAIL = {
  responseId: "a01",
  reference: "FB-00013",
  guest: "Ali Haider",
  bookingId: "b01",
  bookingNumber: "GX-TEST-A1",
  region: "Algarve",
  overall: 6,
  overallComment: "Zu viel Programm",
  consultation: 9,
  services: [],
  hotels: [
    {
      name: "Conrad Algarve",
      score: 5,
      comment: "Laut",
      subScores: [{ subCategory: "Room", average: 4 }]
    }
  ],
  golf: [{ name: "Quinta do Lago", score: 9 }],
  recommendation: 4,
  npsCategory: "Detractor",
  nextDestination: "Schottland"
};

const flush = () =>
  Promise.resolve()
    .then(() => Promise.resolve())
    .then(() => Promise.resolve());

function mount() {
  const el = createElement("c-gx-response-modal", { is: GxResponseModal });
  el.responseId = "a01";
  document.body.appendChild(el);
  return el;
}

const text = (el) => el.shadowRoot.textContent;

describe("c-gx-response-modal", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.restoreAllMocks();
  });

  it("loads the response it was opened for", async () => {
    getResponseDetail.mockResolvedValue(DETAIL);
    mount();
    await flush();
    expect(getResponseDetail).toHaveBeenCalledWith({ responseId: "a01" });
  });

  it("shows the whole answer, screen by screen", async () => {
    getResponseDetail.mockResolvedValue(DETAIL);
    const el = mount();
    await flush();

    const titles = [...el.shadowRoot.querySelectorAll(".section-title")].map(
      (n) => n.textContent
    );
    expect(titles).toEqual([
      "Overall impression",
      "Hotels",
      "Golf courses",
      "Conclusion"
    ]);
    expect(text(el)).toContain("Zu viel Programm");
    expect(text(el)).toContain("Laut");
    expect(text(el)).toContain("Room");
    expect(text(el)).toContain("Schottland");
    expect(text(el)).toContain("Detractor");
    expect(el.shadowRoot.querySelector("lightning-modal-header").label).toBe(
      "FB-00013 · Ali Haider"
    );
  });

  it("says so when the response cannot be loaded", async () => {
    getResponseDetail.mockRejectedValue({
      body: { message: "This feedback could not be found." }
    });
    const el = mount();
    await flush();

    expect(el.shadowRoot.querySelector(".notice").textContent).toBe(
      "This feedback could not be found."
    );
    const [booking, record] =
      el.shadowRoot.querySelectorAll("lightning-button");
    expect(booking.disabled).toBe(true);
    expect(record.disabled).toBe(true);
  });

  it("hands the booking back to the dashboard to open", async () => {
    getResponseDetail.mockResolvedValue(DETAIL);
    const el = mount();
    const closed = [];
    el.addEventListener("modalclose", (e) => closed.push(e.detail));
    await flush();

    const [booking, record] =
      el.shadowRoot.querySelectorAll("lightning-button");
    booking.click();
    record.click();

    expect(closed).toEqual([{ navigate: "b01" }, { navigate: "a01" }]);
  });
});
