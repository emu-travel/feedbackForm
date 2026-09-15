import { LightningElement, api } from "lwc";
import { shouldExpandHotelDetail, SUB_CATEGORIES } from "c/gxSurveyFlow";
import { LABELS, formatLabel } from "c/gxSurveyLabels";

/**
 * gxHotelCard
 *
 * One booked hotel on screen 3. Scoring it below 9 expands the detailed
 * evaluation panel: four sub-category scales plus a comment box, matching the
 * survey specification.
 *
 * Stateless - the container owns the answers and passes them back down.
 */

/** Labels only. The keys live in gxSurveyFlow, which has to agree with them
 * when it builds the payload. */
const SUB_LABELS = {
  Room: LABELS.s3SubRoom,
  Service: LABELS.s3SubService,
  Catering: LABELS.s3SubCatering,
  Cleanliness: LABELS.s3SubCleanliness
};

export default class GxHotelCard extends LightningElement {
  labels = LABELS;

  /** A RateableItem from GxFeedbackService.getContext. */
  @api hotel;

  /** { score, comment, sub: { Room, Service, Catering, Cleanliness } } */
  @api answer;

  /** Set when the guest tried to move on without rating this hotel. */
  @api invalid = false;

  /** Empty until the guest chooses; nothing is pre-selected. */
  get score() {
    return this.answer && this.answer.score ? this.answer.score : null;
  }

  get comment() {
    return (this.answer && this.answer.comment) || "";
  }

  get name() {
    return this.hotel ? this.hotel.name : "";
  }

  /** "Almancil, Portugal · 6 Nächte · Deluxe Room" - only the parts we have. */
  get subtitle() {
    if (!this.hotel) {
      return "";
    }
    const parts = [];
    if (this.hotel.location) {
      parts.push(this.hotel.location);
    }
    if (this.hotel.nights) {
      parts.push(
        this.hotel.nights === 1
          ? LABELS.s3NightsOne
          : formatLabel(LABELS.s3NightsMany, this.hotel.nights)
      );
    }
    if (this.hotel.detail) {
      parts.push(this.hotel.detail);
    }
    return parts.join(" · ");
  }

  get showDetail() {
    return shouldExpandHotelDetail(this.score);
  }

  /**
   * The comment box is not bound to a value, so a comment the guest wrote
   * earlier - restored from this device - is put back into it here. Only when
   * it differs, so typing never moves the cursor.
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

  get subRatings() {
    const given = (this.answer && this.answer.sub) || {};
    return SUB_CATEGORIES.map((key) => ({
      key,
      label: SUB_LABELS[key],
      value: given[key] || null
    }));
  }

  get commentPrompt() {
    return formatLabel(LABELS.s3HotelPrompt, this.name);
  }

  get commentPlaceholder() {
    return LABELS.s3HotelHint;
  }

  get ratingAriaLabel() {
    return formatLabel(LABELS.s3HotelAria, this.name);
  }

  handleScore(event) {
    event.stopPropagation();
    this.fire("scorechange", { score: event.detail.value });
  }

  handleSubScore(event) {
    event.stopPropagation();
    this.fire("subchange", {
      category: event.currentTarget.dataset.category,
      score: event.detail.value
    });
  }

  handleComment(event) {
    this.fire("commentchange", { comment: event.target.value });
  }

  fire(name, detail) {
    this.dispatchEvent(
      new CustomEvent(name, {
        detail: {
          reservationId: this.hotel ? this.hotel.reservationId : null,
          ...detail
        }
      })
    );
  }
}
