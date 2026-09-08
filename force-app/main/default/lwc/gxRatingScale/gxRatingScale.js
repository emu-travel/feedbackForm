import { LightningElement, api } from "lwc";
import { shouldShowComment } from "c/gxSurveyFlow";

const CHOICES = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
const DEFAULT_SCORE = 10;

/**
 * gxRatingScale
 *
 * The 1-10 scale used on every screen of the survey: a slider paired with a
 * button row, and a follow-up comment box that appears once the score drops to
 * 8 or below.
 *
 * Emits `valuechange` and `commentchange`; it holds no state of its own, so the
 * container stays the single source of truth for the guest's answers.
 */
export default class GxRatingScale extends LightningElement {
  @api minLabel = "Unzureichend";
  @api maxLabel = "Ausgezeichnet";
  @api commentPrompt;
  @api commentPlaceholder;
  @api comment;
  @api ariaLabel;

  /** Tighter styling for the hotel sub-ratings. */
  @api compact = false;

  /** Suppresses the comment box even below 9, for scales that take no comment. */
  @api noComment = false;

  _value = DEFAULT_SCORE;

  @api
  get value() {
    return this._value;
  }
  set value(incoming) {
    const parsed = Number(incoming);
    this._value =
      Number.isFinite(parsed) && parsed >= 1 && parsed <= 10
        ? Math.round(parsed)
        : DEFAULT_SCORE;
  }

  get currentValue() {
    return this._value;
  }

  get valueLabel() {
    return `${this._value} / 10`;
  }

  get choices() {
    return CHOICES.map((value) => {
      const selected = value === this._value;
      return {
        value,
        selected,
        className: selected ? "choice choice_selected" : "choice"
      };
    });
  }

  /** Fills the slider track up to the current score. */
  get trackStyle() {
    const percent = ((this._value - 1) / 9) * 100;
    return `--gx-fill: ${percent}%`;
  }

  get showComment() {
    return (
      !this.noComment &&
      Boolean(this.commentPrompt) &&
      shouldShowComment(this._value)
    );
  }

  /**
   * A textarea carries its value as content, not as an attribute, so it cannot
   * be bound in the template. Sync it here instead, and only when it differs -
   * writing on every render would move the caret while the guest is typing.
   */
  renderedCallback() {
    const box = this.template.querySelector(".comment-box");
    if (!box) {
      return;
    }
    const incoming = this.comment || "";
    if (box.value !== incoming) {
      box.value = incoming;
    }
  }

  handleSlider(event) {
    this.publishValue(Number(event.target.value));
  }

  handleChoice(event) {
    this.publishValue(Number(event.currentTarget.dataset.value));
  }

  handleComment(event) {
    this.dispatchEvent(
      new CustomEvent("commentchange", {
        detail: { comment: event.target.value }
      })
    );
  }

  publishValue(value) {
    if (!Number.isFinite(value) || value === this._value) {
      return;
    }
    this._value = value;
    this.dispatchEvent(new CustomEvent("valuechange", { detail: { value } }));
  }
}
