import { createElement } from "lwc";
import { CurrentPageReference } from "lightning/navigation";
import GxFeedbackForm from "c/gxFeedbackForm";
import getContext from "@salesforce/apex/GxFeedbackFormController.getContext";
import submit from "@salesforce/apex/GxFeedbackFormController.submit";

jest.mock(
  "@salesforce/apex/GxFeedbackFormController.getContext",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/GxFeedbackFormController.submit",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const READY_CONTEXT = {
  ok: true,
  bookingNumber: "L000187ES",
  guestName: "Dr. Maximilian von Bern",
  language: "DE",
  trustpilotUrl: "https://trustpilot.example/evaluate",
  googleMapsUrl: "https://maps.example/review",
  hasFlight: true,
  hasTransfers: false,
  hasRentalCar: false,
  hasHotels: true,
  hasGolf: true,
  flightSuppliers: ["AERTicket.de"],
  transferSuppliers: [],
  rentalSuppliers: [],
  hotels: [
    {
      reservationId: "res-hotel-1",
      name: "Conrad Algarve",
      location: "Almancil, Portugal",
      nights: 7,
      detail: "Deluxe Room"
    }
  ],
  golfCourses: [
    { reservationId: "res-golf-1", name: "Golf del Sur", teeTime: "09:30" }
  ]
};

function mount() {
  const element = createElement("c-gx-feedback-form", { is: GxFeedbackForm });
  document.body.appendChild(element);
  return element;
}

/** Drives the URL parameters the way the Experience Cloud page would. */
function withUrl(b = "L000187ES", k = "s3cret") {
  CurrentPageReference.emit({ state: { b, k } });
}

const flush = () => Promise.resolve().then(() => Promise.resolve());

const text = (el) => el.shadowRoot.textContent;
const title = (el) => {
  const node = el.shadowRoot.querySelector(".title");
  return node ? node.textContent.trim() : null;
};
const nextButton = (el) => el.shadowRoot.querySelector(".btn_primary");
const backButton = (el) => el.shadowRoot.querySelector(".btn_ghost");

/**
 * Chooses a score on every main rating of the current screen, as a guest must
 * before Weiter moves on. Nothing is pre-selected any more.
 */
function answerScreen(element, score = 10) {
  const root = element.shadowRoot;
  root
    .querySelectorAll("c-gx-rating-scale")
    .forEach((scale) =>
      scale.dispatchEvent(
        new CustomEvent("valuechange", { detail: { value: score } })
      )
    );
  root.querySelectorAll("c-gx-hotel-card").forEach((card) =>
    card.dispatchEvent(
      new CustomEvent("scorechange", {
        detail: { reservationId: card.hotel.reservationId, score }
      })
    )
  );
  root.querySelectorAll("c-gx-course-card").forEach((card) =>
    card.dispatchEvent(
      new CustomEvent("scorechange", {
        detail: { reservationId: card.course.reservationId, score }
      })
    )
  );
}

/** Answers the current screen, then presses Weiter. */
async function next(element) {
  answerScreen(element);
  await flush();
  nextButton(element).click();
  await flush();
}

/**
 * Steps to the final question screen and answers it. The clicks are
 * deliberately sequential - each screen only exists once the previous one has
 * advanced.
 */
async function walkToEnd(element) {
  /* eslint-disable no-await-in-loop */
  for (let i = 0; i < 4; i++) {
    await next(element);
  }
  /* eslint-enable no-await-in-loop */
  answerScreen(element);
  await flush();
}

describe("c-gx-feedback-form", () => {
  beforeEach(() => {
    getContext.mockResolvedValue({ ...READY_CONTEXT });
    submit.mockResolvedValue({ ok: true, reference: "FB-00007" });
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  describe("opening the link", () => {
    it("asks Apex using the booking number and secret from the URL", async () => {
      mount();
      withUrl("L000187ES", "abc123");
      await flush();

      expect(getContext).toHaveBeenCalledWith({
        bookingNumber: "L000187ES",
        secret: "abc123"
      });
    });

    it("refuses to call Apex when the link carries no credentials", async () => {
      const element = mount();
      CurrentPageReference.emit({ state: {} });
      await flush();

      expect(getContext).not.toHaveBeenCalled();
      expect(text(element)).toContain("ungültig oder abgelaufen");
    });

    it("tells a guest who already answered that we have their feedback", async () => {
      getContext.mockResolvedValue({ ok: false, message: "submitted" });
      const element = mount();
      withUrl();
      await flush();

      expect(text(element)).toContain("bereits erhalten");
    });

    it("explains an itinerary with nothing to rate", async () => {
      getContext.mockResolvedValue({ ok: false, message: "empty" });
      const element = mount();
      withUrl();
      await flush();

      expect(text(element)).toContain("keine bewertbaren Leistungen");
    });

    it("distinguishes an expired link from a broken one", async () => {
      getContext.mockResolvedValue({ ok: false, message: "expired" });
      const element = mount();
      withUrl();
      await flush();

      expect(text(element)).toContain("abgelaufen");
      expect(text(element)).toContain("Reiseberater");
    });

    it("shows a neutral message when Apex fails outright", async () => {
      getContext.mockRejectedValue(new Error("boom"));
      const element = mount();
      withUrl();
      await flush();

      expect(text(element)).toContain("ungültig oder abgelaufen");
    });
  });

  describe("navigating the guest itinerary", () => {
    it("opens on the overall impression screen", async () => {
      const element = mount();
      withUrl();
      await flush();

      expect(title(element)).toBe("Gesamteindruck Ihrer Golfreise");
    });

    it("walks only the screens this booking earned", async () => {
      const element = mount();
      withUrl();
      await flush();

      // flight only, no transfer or rental car
      await next(element);
      expect(title(element)).toBe("Transfer- und Mobilitätsleistungen");

      await next(element);
      expect(title(element)).toBe("Hotel und Unterkunft");

      await next(element);
      expect(title(element)).toBe("Golfplätze");

      await next(element);
      expect(title(element)).toBe("Fazit");
    });

    it("skips the mobility screen when nothing was booked for it", async () => {
      getContext.mockResolvedValue({
        ...READY_CONTEXT,
        hasFlight: false,
        flightSuppliers: []
      });
      const element = mount();
      withUrl();
      await flush();

      await next(element);
      expect(title(element)).toBe("Hotel und Unterkunft");
    });

    it("counts progress over the screens actually shown", async () => {
      getContext.mockResolvedValue({
        ...READY_CONTEXT,
        hasFlight: false,
        hasGolf: false,
        flightSuppliers: [],
        golfCourses: []
      });
      const element = mount();
      withUrl();
      await flush();

      // overall + hotels + conclusion
      expect(element.shadowRoot.querySelector(".step").textContent).toBe(
        "Schritt 1 von 3"
      );
    });

    it("reverses the same path going back", async () => {
      const element = mount();
      withUrl();
      await flush();

      await next(element);
      await next(element);
      expect(title(element)).toBe("Hotel und Unterkunft");

      backButton(element).click();
      await flush();
      expect(title(element)).toBe("Transfer- und Mobilitätsleistungen");
    });

    it("offers no Zurück on the first screen, where it has nowhere to go", async () => {
      const element = mount();
      withUrl();
      await flush();
      expect(backButton(element)).toBeNull();

      await next(element);
      expect(backButton(element)).not.toBeNull();
    });

    it("labels the last question screen as the submit action", async () => {
      const element = mount();
      withUrl();
      await flush();
      expect(nextButton(element).textContent.trim()).toBe("Weiter");

      await walkToEnd(element);
      expect(nextButton(element).textContent.trim()).toBe(
        "Feedback jetzt absenden"
      );
    });

    it("names the screen for a single hotel in the singular", async () => {
      const element = mount();
      withUrl();
      await flush();
      await next(element);
      await next(element);

      expect(title(element)).toBe("Hotel und Unterkunft");
    });
  });

  describe("nothing is answered for the guest", () => {
    it("starts every rating empty", async () => {
      const element = mount();
      withUrl();
      await flush();

      const scales = element.shadowRoot.querySelectorAll("c-gx-rating-scale");
      expect(scales).toHaveLength(2);
      scales.forEach((s) => expect(s.value).toBeNull());
    });

    it("keeps the guest on the screen and marks what is missing", async () => {
      const element = mount();
      withUrl();
      await flush();

      nextButton(element).click();
      await flush();

      expect(title(element)).toBe("Gesamteindruck Ihrer Golfreise");
      expect(element.shadowRoot.querySelector(".missing-note")).not.toBeNull();
      const scales = [
        ...element.shadowRoot.querySelectorAll("c-gx-rating-scale")
      ];
      expect(scales.map((s) => s.invalid)).toEqual([true, true]);
    });

    it("clears the mark as soon as the rating is chosen", async () => {
      const element = mount();
      withUrl();
      await flush();
      nextButton(element).click();
      await flush();

      answerScreen(element, 7);
      await flush();

      expect(element.shadowRoot.querySelector(".missing-note")).toBeNull();
      nextButton(element).click();
      await flush();
      expect(title(element)).toBe("Transfer- und Mobilitätsleistungen");
    });

    it("asks for a hotel rating before leaving the hotel screen", async () => {
      const element = mount();
      withUrl();
      await flush();
      await next(element);
      await next(element);
      expect(title(element)).toBe("Hotel und Unterkunft");

      nextButton(element).click();
      await flush();

      expect(title(element)).toBe("Hotel und Unterkunft");
      expect(element.shadowRoot.querySelector("c-gx-hotel-card").invalid).toBe(
        true
      );
    });

    it("runs the recommendation question from 0, as NPS does", async () => {
      const element = mount();
      withUrl();
      await flush();
      await walkToEnd(element);

      const scale = element.shadowRoot.querySelector(
        'c-gx-rating-scale[data-field="recommendation"]'
      );
      expect(scale.min).toBe(0);

      scale.dispatchEvent(
        new CustomEvent("valuechange", { detail: { value: 0 } })
      );
      await flush();
      nextButton(element).click();
      await flush();

      const payload = JSON.parse(submit.mock.calls[0][0].payloadJson);
      expect(payload.recommendation).toBe(0);
    });
  });

  describe("rendering what was booked", () => {
    it("shows one card per hotel and per course", async () => {
      const element = mount();
      withUrl();
      await flush();
      await next(element);
      await next(element);

      expect(
        element.shadowRoot.querySelectorAll("c-gx-hotel-card")
      ).toHaveLength(1);

      await next(element);
      expect(
        element.shadowRoot.querySelectorAll("c-gx-course-card")
      ).toHaveLength(1);
    });

    it("badges the flight question with the airline", async () => {
      const element = mount();
      withUrl();
      await flush();
      await next(element);

      expect(element.shadowRoot.querySelector(".badge").textContent).toBe(
        "AERTicket.de"
      );
    });
  });

  describe("submitting", () => {
    it("sends the credentials and the answers", async () => {
      const element = mount();
      withUrl("L000187ES", "abc123");
      await flush();
      await walkToEnd(element);

      await next(element);

      expect(submit).toHaveBeenCalledTimes(1);
      const payload = JSON.parse(submit.mock.calls[0][0].payloadJson);
      expect(payload.bookingNumber).toBe("L000187ES");
      expect(payload.secret).toBe("abc123");
      expect(payload.overallExperience).toBe(10);
      expect(payload.recommendation).toBe(10);
      expect(payload.hotels[0].reservationId).toBe("res-hotel-1");
      expect(payload.golfCourses[0].reservationId).toBe("res-golf-1");
    });

    it("never sends a section the guest was not shown", async () => {
      const element = mount();
      withUrl();
      await flush();
      await walkToEnd(element);

      await next(element);

      const payload = JSON.parse(submit.mock.calls[0][0].payloadJson);
      expect(payload.flight).toBeDefined();
      expect(payload.transfer).toBeUndefined();
      expect(payload.rentalCar).toBeUndefined();
    });

    it("shows the thank-you screen once accepted", async () => {
      const element = mount();
      withUrl();
      await flush();
      await walkToEnd(element);

      await next(element);

      expect(title(element)).toBe("Vielen Dank!");
      expect(text(element)).toContain("FB-00007");
      // Said once, in the heading - not again in the first and last lines.
      expect(text(element).match(/Vielen Dank/g)).toHaveLength(1);
    });

    it("offers the public review cards to a promoter", async () => {
      const element = mount();
      withUrl();
      await flush();
      await walkToEnd(element);

      await next(element);

      const links = element.shadowRoot.querySelectorAll(".review-card");
      expect(links).toHaveLength(2);
      expect(links[0].href).toBe("https://trustpilot.example/evaluate");
    });

    it("suppresses the review cards below 9", async () => {
      const element = mount();
      withUrl();
      await flush();

      // walk to the conclusion screen and drop the recommendation to 6
      await walkToEnd(element);
      const scale = element.shadowRoot.querySelector(
        'c-gx-rating-scale[data-field="recommendation"]'
      );
      scale.dispatchEvent(
        new CustomEvent("valuechange", { detail: { value: 6 } })
      );
      await flush();

      nextButton(element).click();
      await flush();

      expect(element.shadowRoot.querySelector(".review-card")).toBeNull();
      expect(text(element)).toContain("dankend erhalten");
    });

    it("keeps the guest on the form when the server rejects it", async () => {
      submit.mockResolvedValue({ ok: false, message: "Nicht gespeichert." });
      const element = mount();
      withUrl();
      await flush();
      await walkToEnd(element);

      await next(element);

      expect(title(element)).toBe("Fazit");
      expect(element.shadowRoot.querySelector(".error").textContent).toBe(
        "Nicht gespeichert."
      );
    });

    it("reports a transport failure without losing the answers", async () => {
      submit.mockRejectedValue(new Error("network"));
      const element = mount();
      withUrl();
      await flush();
      await walkToEnd(element);

      await next(element);

      expect(title(element)).toBe("Fazit");
      expect(text(element)).toContain("nicht gesendet werden");
    });

    it("does not submit twice on a double click", async () => {
      const element = mount();
      withUrl();
      await flush();
      await walkToEnd(element);

      nextButton(element).click();
      nextButton(element).click();
      await flush();

      expect(submit).toHaveBeenCalledTimes(1);
    });
  });
});
