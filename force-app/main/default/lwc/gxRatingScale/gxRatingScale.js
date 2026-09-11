import { LightningElement, api } from "lwc";
import { shouldShowComment } from "c/gxSurveyFlow";

const MIN = 1;
const MAX = 10;

/**
 * gxRatingScale
 *
 * The rating scale used on every screen of the survey: a slider paired with a
 * button row, and a follow-up comment box that appears once the score drops to
 * 8 or below.
 *
 * It starts empty - nothing is selected until the guest chooses. Every scale
 * in the survey, the recommendation question included, runs 1 to 10.
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

  /** Set by the container when the guest tried to move on without choosing. */
  @api invalid = false;

  _value = null;

  @api
  get value() {
    return this.hasValue ? this._value : null;
  }
  set value(incoming) {
    const parsed =
      incoming === null || incoming === undefined || incoming === ""
        ? NaN
        : Number(incoming);
    this._value = Number.isInteger(parsed) ? parsed : null;
  }

  get hasValue() {
    return this._value !== null && this._value >= MIN && this._value <= MAX;
  }

  get valueLabel() {
    return `${this._value} / ${MAX}`;
  }

  get showInvalid() {
    return Boolean(this.invalid) && !this.hasValue;
  }

  get scaleClass() {
    return this.showInvalid ? "scale scale_invalid" : "scale";
  }

  get choices() {
    const out = [];
    for (let value = MIN; value <= MAX; value++) {
      const selected = this.hasValue && value === this._value;
      out.push({
        value,
        selected,
        className: selected ? "choice choice_selected" : "choice"
      });
    }
    return out;
  }

  get rangeValue() {
    return this.hasValue ? this._value : MIN;
  }

  /** Until a score is chosen the slider shows no thumb and no fill. */
  get trackClass() {
    return this.hasValue ? "track" : "track track_unset";
  }

  get trackStyle() {
    const percent = this.hasValue
      ? ((this._value - MIN) / (MAX - MIN)) * 100
      : 0;
    return `--gx-fill: ${percent}%`;
  }

  get showComment() {
    return (
      !this.noComment &&
      Boolean(this.commentPrompt) &&
      this.hasValue &&
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

  /**
   * An empty slider rests at 1, and tapping the spot it already rests on fires
   * no change event. A click still arrives, so take the value from that.
   */
  handleSliderClick(event) {
    if (!this.hasValue) {
      this.publishValue(Number(event.target.value));
    }
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
    if (!Number.isInteger(value) || (this.hasValue && value === this._value)) {
      return;
    }
    this._value = value;
    this.dispatchEvent(new CustomEvent("valuechange", { detail: { value } }));
  }
}
