import { createElement } from "lwc";
import GxRatingScale from "c/gxRatingScale";

function mount(props = {}) {
  const element = createElement("c-gx-rating-scale", { is: GxRatingScale });
  Object.assign(element, props);
  document.body.appendChild(element);
  return element;
}

function choices(element) {
  return Array.from(element.shadowRoot.querySelectorAll("button.choice"));
}

function commentBox(element) {
  return element.shadowRoot.querySelector(".comment-box");
}

describe("c-gx-rating-scale", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("renders all ten scores", () => {
    const element = mount();
    expect(choices(element).map((b) => b.textContent.trim())).toEqual([
      "1",
      "2",
      "3",
      "4",
      "5",
      "6",
      "7",
      "8",
      "9",
      "10"
    ]);
  });

  it("defaults to 10, matching the prototype", () => {
    const element = mount();
    expect(element.value).toBe(10);
    expect(element.shadowRoot.querySelector(".badge").textContent).toContain(
      "10 / 10"
    );
  });

  it("marks only the selected score as pressed", () => {
    const element = mount({ value: 7 });
    return Promise.resolve().then(() => {
      const pressed = choices(element).filter(
        (b) => b.getAttribute("aria-pressed") === "true"
      );
      expect(pressed).toHaveLength(1);
      expect(pressed[0].textContent.trim()).toBe("7");
    });
  });

  it("falls back to 10 when handed a value outside the scale", () => {
    [0, 11, -3, "abc", null, undefined].forEach((bad) => {
      expect(mount({ value: bad }).value).toBe(10);
    });
  });

  it("emits valuechange when a score button is clicked", () => {
    const element = mount();
    const handler = jest.fn();
    element.addEventListener("valuechange", handler);

    choices(element)[5].click(); // the "6" button

    expect(handler).toHaveBeenCalledTimes(1);
    expect(handler.mock.calls[0][0].detail).toEqual({ value: 6 });
  });

  it("emits valuechange when the slider moves", () => {
    const element = mount();
    const handler = jest.fn();
    element.addEventListener("valuechange", handler);

    const slider = element.shadowRoot.querySelector('input[type="range"]');
    slider.value = 3;
    slider.dispatchEvent(new CustomEvent("change"));

    expect(handler.mock.calls[0][0].detail).toEqual({ value: 3 });
  });

  it("does not re-emit when the same score is chosen again", () => {
    const element = mount({ value: 4 });
    const handler = jest.fn();

    return Promise.resolve().then(() => {
      element.addEventListener("valuechange", handler);
      choices(element)[3].click(); // "4" again
      expect(handler).not.toHaveBeenCalled();
    });
  });

  describe("the follow-up comment box", () => {
    const withPrompt = { commentPrompt: "Was können wir verbessern?" };

    it("stays hidden at 9 and 10", () => {
      expect(commentBox(mount({ ...withPrompt, value: 10 }))).toBeNull();
      expect(commentBox(mount({ ...withPrompt, value: 9 }))).toBeNull();
    });

    it("appears at 8 and below", () => {
      expect(commentBox(mount({ ...withPrompt, value: 8 }))).not.toBeNull();
      expect(commentBox(mount({ ...withPrompt, value: 1 }))).not.toBeNull();
    });

    it("appears as soon as the guest lowers the score", () => {
      const element = mount(withPrompt);
      expect(commentBox(element)).toBeNull();

      choices(element)[6].click(); // "7"

      return Promise.resolve().then(() => {
        expect(commentBox(element)).not.toBeNull();
      });
    });

    it("stays hidden without a prompt, even at a low score", () => {
      expect(commentBox(mount({ value: 3 }))).toBeNull();
    });

    it("can be suppressed entirely", () => {
      const element = mount({ ...withPrompt, value: 3, noComment: true });
      expect(commentBox(element)).toBeNull();
    });

    it("shows a comment the container already holds", () => {
      const element = mount({
        ...withPrompt,
        value: 5,
        comment: "Schon geschrieben"
      });
      return Promise.resolve().then(() => {
        expect(commentBox(element).value).toBe("Schon geschrieben");
      });
    });

    it("emits commentchange when the guest types", () => {
      const element = mount({ ...withPrompt, value: 5 });
      const handler = jest.fn();
      element.addEventListener("commentchange", handler);

      const box = commentBox(element);
      box.value = "Zimmer war laut";
      box.dispatchEvent(new CustomEvent("change"));

      expect(handler.mock.calls[0][0].detail).toEqual({
        comment: "Zimmer war laut"
      });
    });
  });

  it("shows the scale end labels it was given", () => {
    const element = mount({
      minLabel: "Sehr unwahrscheinlich",
      maxLabel: "Sehr wahrscheinlich"
    });
    const text = element.shadowRoot.querySelector(".ends").textContent;
    expect(text).toContain("Sehr unwahrscheinlich");
    expect(text).toContain("Sehr wahrscheinlich");
  });
});
