import { createElement } from "lwc";
import GxVenueBoard from "c/gxVenueBoard";
import { venueList } from "c/gxDashboardView";

const venues = (n, prefix = "Hotel") =>
  Array.from({ length: n }, (_, i) => ({
    category: "Hotel",
    name: `${prefix} ${i + 1}`,
    average: 9,
    ratings: 5,
    ranked: true
  }));

const flush = () => Promise.resolve().then(() => Promise.resolve());

function mount(board) {
  const el = createElement("c-gx-venue-board", { is: GxVenueBoard });
  el.title = "Hotels";
  el.minRatings = 3;
  el.board = board;
  document.body.appendChild(el);
  return el;
}

const names = (el) =>
  [...el.shadowRoot.querySelectorAll(".venue-name")].map((n) => n.textContent);

describe("c-gx-venue-board", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("shows ten venues at a time, with a pager for the rest", () => {
    const el = mount(venueList(venues(23)));
    expect(names(el)).toHaveLength(10);
    const pager = el.shadowRoot.querySelector("c-gx-pager");
    expect(pager.total).toBe(23);
    expect(pager.page).toBe(1);
  });

  it("turns the page when asked", async () => {
    const el = mount(venueList(venues(23)));
    el.shadowRoot
      .querySelector("c-gx-pager")
      .dispatchEvent(new CustomEvent("pagechange", { detail: { page: 3 } }));
    await flush();
    expect(names(el)).toEqual(["Hotel 21", "Hotel 22", "Hotel 23"]);
  });

  it("starts a new selection back on page one", async () => {
    const el = mount(venueList(venues(23)));
    el.shadowRoot
      .querySelector("c-gx-pager")
      .dispatchEvent(new CustomEvent("pagechange", { detail: { page: 3 } }));
    await flush();

    el.board = venueList(venues(12, "Golf"));
    await flush();

    expect(names(el)[0]).toBe("Golf 1");
  });

  it("colours each score by band: 9 and above green, 8.5 amber", () => {
    const el = mount(
      venueList([
        {
          category: "Hotel",
          name: "Pine Cliffs",
          average: 9.1,
          ratings: 5,
          ranked: true
        },
        {
          category: "Hotel",
          name: "Conrad Algarve",
          average: 8.5,
          ratings: 4,
          ranked: true
        }
      ])
    );
    const scores = [...el.shadowRoot.querySelectorAll(".venue-score")];
    expect(scores[0].classList).toContain("venue-score_good");
    expect(scores[1].classList).toContain("venue-score_mid");
    expect(el.shadowRoot.querySelectorAll(".venue-fill_mid")).toHaveLength(1);
  });
});
