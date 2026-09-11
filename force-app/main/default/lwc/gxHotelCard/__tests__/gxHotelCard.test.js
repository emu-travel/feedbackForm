import { createElement } from "lwc";
import GxHotelCard from "c/gxHotelCard";

const HOTEL = {
  reservationId: "a01000000000001",
  name: "Conrad Algarve",
  location: "Almancil, Portugal",
  nights: 7,
  detail: "Deluxe Room"
};

function mount(props = {}) {
  const element = createElement("c-gx-hotel-card", { is: GxHotelCard });
  Object.assign(element, { hotel: HOTEL, ...props });
  document.body.appendChild(element);
  return element;
}

const scales = (el) =>
  Array.from(el.shadowRoot.querySelectorAll("c-gx-rating-scale"));
const detail = (el) => el.shadowRoot.querySelector(".detail");

describe("c-gx-hotel-card", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("shows the hotel name and its booking detail", () => {
    const element = mount();
    expect(element.shadowRoot.querySelector(".name").textContent).toBe(
      "Conrad Algarve"
    );
    expect(element.shadowRoot.querySelector(".subtitle").textContent).toBe(
      "Almancil, Portugal · 7 Nächte · Deluxe Room"
    );
  });

  it("says 1 Nacht, not 1 Nächte", () => {
    const element = mount({
      hotel: { ...HOTEL, nights: 1, detail: null }
    });
    expect(element.shadowRoot.querySelector(".subtitle").textContent).toBe(
      "Almancil, Portugal · 1 Nacht"
    );
  });

  it("omits parts of the subtitle the itinerary did not supply", () => {
    const element = mount({
      hotel: { reservationId: "r1", name: "Sparse Hotel" }
    });
    expect(element.shadowRoot.querySelector(".subtitle")).toBeNull();
  });

  it("keeps the detail panel closed at 9 and 10", () => {
    expect(detail(mount({ answer: { score: 10 } }))).toBeNull();
    expect(detail(mount({ answer: { score: 9 } }))).toBeNull();
  });

  it("opens the detail panel below 9, as the spec requires", () => {
    const element = mount({ answer: { score: 8 } });
    expect(detail(element)).not.toBeNull();
  });

  it("offers exactly the four sub-categories when it opens", () => {
    const element = mount({ answer: { score: 5 } });
    const labels = Array.from(
      element.shadowRoot.querySelectorAll(".sub-label")
    ).map((n) => n.textContent);

    expect(labels).toEqual([
      "Zimmer und Ausstattung",
      "Hotelservice und Betreuung vor Ort",
      "Gastronomie",
      "Sauberkeit"
    ]);
  });

  it("defaults sub-ratings to 8, not 10", () => {
    const element = mount({ answer: { score: 6 } });
    // the first scale is the overall rating; the rest are sub-categories
    const subs = scales(element).slice(1);
    expect(subs).toHaveLength(4);
    subs.forEach((s) => expect(s.value).toBe(8));
  });

  it("shows sub-ratings the guest already gave", () => {
    const element = mount({
      answer: { score: 6, sub: { Room: 3, Cleanliness: 9 } }
    });
    const subs = scales(element).slice(1);
    expect(subs[0].value).toBe(3); // Room
    expect(subs[1].value).toBe(8); // Service, untouched
    expect(subs[3].value).toBe(9); // Cleanliness
  });

  it("names the hotel in its improvement question", () => {
    const element = mount({ answer: { score: 4 } });
    expect(
      element.shadowRoot.querySelector(".comment-prompt").textContent
    ).toContain("Conrad Algarve");
  });

  it("reports the overall score with the reservation it belongs to", () => {
    const element = mount();
    const handler = jest.fn();
    element.addEventListener("scorechange", handler);

    scales(element)[0].dispatchEvent(
      new CustomEvent("valuechange", { detail: { value: 7 } })
    );

    expect(handler.mock.calls[0][0].detail).toEqual({
      reservationId: HOTEL.reservationId,
      score: 7
    });
  });

  it("reports which sub-category changed", () => {
    const element = mount({ answer: { score: 6 } });
    const handler = jest.fn();
    element.addEventListener("subchange", handler);

    scales(element)[2].dispatchEvent(
      new CustomEvent("valuechange", { detail: { value: 4 } })
    );

    expect(handler.mock.calls[0][0].detail).toEqual({
      reservationId: HOTEL.reservationId,
      category: "Service",
      score: 4
    });
  });

  it("reports the hotel comment", () => {
    const element = mount({ answer: { score: 5 } });
    const handler = jest.fn();
    element.addEventListener("commentchange", handler);

    const box = element.shadowRoot.querySelector(".comment-box");
    box.value = "Der Spa war geschlossen";
    box.dispatchEvent(new CustomEvent("change"));

    expect(handler.mock.calls[0][0].detail).toEqual({
      reservationId: HOTEL.reservationId,
      comment: "Der Spa war geschlossen"
    });
  });
});
