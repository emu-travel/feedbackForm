import { LightningElement, api } from "lwc";
import { shouldExpandHotelDetail, SUB_CATEGORIES } from "c/gxSurveyFlow";

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
  Room: "Zimmer und Ausstattung",
  Service: "Hotelservice und Betreuung vor Ort",
  Catering: "Gastronomie",
  Cleanliness: "Sauberkeit"
};

export default class GxHotelCard extends LightningElement {
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
        this.hotel.nights === 1 ? "1 Nacht" : `${this.hotel.nights} Nächte`
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

  get subRatings() {
    const given = (this.answer && this.answer.sub) || {};
    return SUB_CATEGORIES.map((key) => ({
      key,
      label: SUB_LABELS[key],
      value: given[key] || null
    }));
  }

  get commentPrompt() {
    return `Welche Aspekte Ihres Aufenthalts im ${this.name} könnten aus Ihrer Sicht verbessert werden? (optional)`;
  }

  get commentPlaceholder() {
    return "z. B. Zimmerausstattung, Service, Verpflegung, Sauberkeit, Spa, …";
  }

  get ratingAriaLabel() {
    return `Gesamtbewertung ${this.name}`;
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
