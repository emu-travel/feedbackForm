import { LightningElement, api } from "lwc";
import { germanDate } from "c/gxSurveyFlow";

/**
 * gxCourseCard
 *
 * One played golf course on screen 4. Scoring it at 8 or below reveals the
 * improvement comment, which gxRatingScale handles.
 *
 * The specification also asks for a hole count and a highlight badge. Neither
 * exists on Account, Service__c or Reservation__c, so the card shows the course
 * name, the booked service and the tee time instead.
 */
export default class GxCourseCard extends LightningElement {
  /** A RateableItem from GxFeedbackService.getContext. */
  @api course;

  /** { score, comment } */
  @api answer;

  get score() {
    return this.answer && this.answer.score ? this.answer.score : 10;
  }

  get comment() {
    return (this.answer && this.answer.comment) || "";
  }

  get name() {
    return this.course ? this.course.name : "";
  }

  get subtitle() {
    if (!this.course) {
      return "";
    }
    const parts = [];
    if (this.course.detail) {
      parts.push(this.course.detail);
    }
    if (this.course.teeTime) {
      parts.push(`Startzeit ${this.course.teeTime}`);
    } else if (this.course.startDate) {
      parts.push(germanDate(this.course.startDate));
    }
    return parts.join(" · ");
  }

  get commentPrompt() {
    return `Welche Aspekte des ${this.name} könnten aus Ihrer Sicht verbessert werden? (optional)`;
  }

  get commentPlaceholder() {
    return "z. B. Platzzustand, Service, Clubhaus, …";
  }

  get ratingAriaLabel() {
    return `Bewertung ${this.name}`;
  }

  handleScore(event) {
    event.stopPropagation();
    this.fire("scorechange", { score: event.detail.value });
  }

  handleComment(event) {
    event.stopPropagation();
    this.fire("commentchange", { comment: event.detail.comment });
  }

  fire(name, detail) {
    this.dispatchEvent(
      new CustomEvent(name, {
        detail: {
          reservationId: this.course ? this.course.reservationId : null,
          ...detail
        }
      })
    );
  }
}
