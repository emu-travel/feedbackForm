import { createElement } from "lwc";
import GxPager from "c/gxPager";

function mount(props) {
  const el = createElement("c-gx-pager", { is: GxPager });
  Object.assign(el, props);
  document.body.appendChild(el);
  return el;
}

const buttons = (el) => [
  ...el.shadowRoot.querySelectorAll("lightning-button-icon")
];

describe("c-gx-pager", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("stays out of the way while everything fits on one page", () => {
    const el = mount({ total: 10, page: 1 });
    expect(el.shadowRoot.querySelector("nav")).toBeNull();
  });

  it("says which rows are showing and which page this is", () => {
    const el = mount({ total: 57, page: 2 });
    expect(el.shadowRoot.querySelector(".range").textContent).toBe(
      "11–20 of 57"
    );
    expect(el.shadowRoot.querySelector(".page").textContent).toBe(
      "Page 2 of 6"
    );
  });

  it("cannot go back from the first page or on from the last", () => {
    const first = mount({ total: 25, page: 1 });
    expect(buttons(first).map((b) => b.disabled)).toEqual([true, false]);
    const last = mount({ total: 25, page: 3 });
    expect(buttons(last).map((b) => b.disabled)).toEqual([false, true]);
  });

  it("asks for the next and previous page", () => {
    const el = mount({ total: 25, page: 2 });
    const handler = jest.fn();
    el.addEventListener("pagechange", handler);

    const [previous, next] = buttons(el);
    next.click();
    previous.click();

    expect(handler.mock.calls.map((c) => c[0].detail.page)).toEqual([3, 1]);
  });
});
