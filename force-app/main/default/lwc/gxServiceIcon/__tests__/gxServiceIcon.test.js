import { createElement } from "lwc";
import GxServiceIcon from "c/gxServiceIcon";

function mount(name) {
  const element = createElement("c-gx-service-icon", { is: GxServiceIcon });
  element.name = name;
  document.body.appendChild(element);
  return element;
}

describe("c-gx-service-icon", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it.each(["flight", "transfer", "car", "hotel", "golf"])(
    "draws one icon for %s, hidden from screen readers",
    (name) => {
      const element = mount(name);
      const tile = element.shadowRoot.querySelector(".tile");
      expect(tile.getAttribute("aria-hidden")).toBe("true");
      expect(tile.querySelectorAll("svg")).toHaveLength(1);
    }
  );

  it("has a small size for dense lists", () => {
    const element = mount("hotel");
    element.size = "small";
    return Promise.resolve().then(() => {
      expect(element.shadowRoot.querySelector(".tile").className).toBe(
        "tile tile_small"
      );
    });
  });

  it("draws nothing for a name it does not know", () => {
    const element = mount("boat");
    expect(element.shadowRoot.querySelectorAll("svg")).toHaveLength(0);
  });
});
