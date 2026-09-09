import { LightningElement, track, wire } from "lwc";
import { CurrentPageReference } from "lightning/navigation";
import LOGO from "@salesforce/resourceUrl/golfextra_logo";
import getContext from "@salesforce/apex/GxFeedbackFormController.getContext";
import submit from "@salesforce/apex/GxFeedbackFormController.submit";
import {
  SCREEN,
  nextScreen,
  previousScreen,
  isLastQuestionScreen,
  progressFor,
  earnsPublicReview,
  buildPayload
} from "c/gxSurveyFlow";

/**
 * gxFeedbackForm
 *
 * Public post-trip feedback survey. Reads ?b= and ?k= from the URL, exactly as
 * the Reiseanmeldung form does, and asks only about what the guest booked.
 */

const LOAD = {
  LOADING: "loading",
  READY: "ready",
  INVALID: "invalid",
  SUBMITTED: "submitted",
  EMPTY: "empty",
  EXPIRED: "expired"
};

const DEFAULT_SCORE = 10;

export default class GxFeedbackForm extends LightningElement {
  logoUrl = LOGO;

  bookingNumber;
  secret;

  lastAttempt;
  loadState = LOAD.LOADING;
  screen = SCREEN.OVERALL;
  submitting = false;
  submitError;
  reference;

  @track ctx;
  @track answers = {
    overallExperience: DEFAULT_SCORE,
    overallExperienceComment: "",
    consultation: DEFAULT_SCORE,
    consultationComment: "",
    flight: { score: DEFAULT_SCORE, comment: "" },
    transfer: { score: DEFAULT_SCORE, comment: "" },
    rentalCar: { score: DEFAULT_SCORE, comment: "" },
    hotels: {},
    golfCourses: {},
    generalHotelComment: "",
    generalGolfComment: "",
    recommendation: DEFAULT_SCORE,
    nextDestination: "",
    improvementSuggestions: ""
  };

  connectedCallback() {
    // LWR and Aura sites deliver query parameters differently, and on an LWR
    // site CurrentPageReference can arrive empty for a guest. The address bar
    // is authoritative on both, so read it first and let the wire correct it.
    this.readParamsFromUrl();
    this.load();
  }

  @wire(CurrentPageReference)
  pageRef(ref) {
    const state = (ref && ref.state) || {};
    if (state.b && state.k) {
      this.bookingNumber = state.b;
      this.secret = state.k;
    }
    this.load();
  }

  readParamsFromUrl() {
    try {
      const params = new URLSearchParams(window.location.search);
      const b = params.get("b");
      const k = params.get("k");
      if (b && k) {
        this.bookingNumber = b;
        this.secret = k;
      }
    } catch {
      // No window.location to read - leave whatever the wire supplied.
    }
  }

  async load() {
    if (!this.bookingNumber || !this.secret) {
      this.loadState = LOAD.INVALID;
      return;
    }
    // Both connectedCallback and the wire call this; only ask Apex once.
    const attempt = `${this.bookingNumber}|${this.secret}`;
    if (this.lastAttempt === attempt) {
      return;
    }
    this.lastAttempt = attempt;

    try {
      const context = await getContext({
        bookingNumber: this.bookingNumber,
        secret: this.secret
      });
      if (context && context.ok) {
        this.ctx = context;
        this.loadState = LOAD.READY;
        return;
      }
      this.loadState = this.mapMessage(context && context.message);
    } catch {
      this.loadState = LOAD.INVALID;
    }
  }

  mapMessage(message) {
    if (message === "submitted") {
      return LOAD.SUBMITTED;
    }
    if (message === "empty") {
      return LOAD.EMPTY;
    }
    if (message === "expired") {
      return LOAD.EXPIRED;
    }
    return LOAD.INVALID;
  }

  // ------------------------------------------------------------------
  // Load states

  get isLoading() {
    return this.loadState === LOAD.LOADING;
  }
  get isReady() {
    return this.loadState === LOAD.READY;
  }
  get isInvalid() {
    return this.loadState === LOAD.INVALID;
  }
  get isAlreadySubmitted() {
    return this.loadState === LOAD.SUBMITTED;
  }
  get isEmpty() {
    return this.loadState === LOAD.EMPTY;
  }
  get isExpired() {
    return this.loadState === LOAD.EXPIRED;
  }

  // ------------------------------------------------------------------
  // Which screen

  get onOverall() {
    return this.screen === SCREEN.OVERALL;
  }
  get onMobility() {
    return this.screen === SCREEN.MOBILITY;
  }
  get onHotels() {
    return this.screen === SCREEN.HOTELS;
  }
  get onGolf() {
    return this.screen === SCREEN.GOLF;
  }
  get onConclusion() {
    return this.screen === SCREEN.CONCLUSION;
  }
  get onThanks() {
    return this.screen === SCREEN.THANKS;
  }
  get showQuestions() {
    return this.isReady && !this.onThanks;
  }

  get progress() {
    return progressFor(this.screen, this.ctx);
  }
  get stepLabel() {
    const p = this.progress;
    return `Schritt ${p.step} von ${p.total}`;
  }
  get progressStyle() {
    return `width: ${this.progress.percent}%`;
  }
  get progressPercentLabel() {
    return `${this.progress.percent}%`;
  }

  get isFinalStep() {
    return isLastQuestionScreen(this.screen, this.ctx);
  }
  get nextLabel() {
    return this.isFinalStep ? "Feedback Jetzt Absenden" : "Weiter";
  }
  get canGoBack() {
    return previousScreen(this.screen, this.ctx) !== null;
  }

  get hotelsScreenTitle() {
    const many = this.ctx && this.ctx.hotels && this.ctx.hotels.length > 1;
    return many ? "Hotels und Unterkunft" : "Hotel und Unterkunft";
  }

  get flightBadge() {
    return this.joinSuppliers(this.ctx && this.ctx.flightSuppliers);
  }
  get transferBadge() {
    return this.joinSuppliers(this.ctx && this.ctx.transferSuppliers);
  }
  get rentalBadge() {
    return this.joinSuppliers(this.ctx && this.ctx.rentalSuppliers);
  }

  joinSuppliers(list) {
    return Array.isArray(list) && list.length ? list.join(", ") : "";
  }

  /** Hotels and courses paired with whatever the guest has answered so far. */
  get hotelCards() {
    const items = (this.ctx && this.ctx.hotels) || [];
    return items.map((hotel) => ({
      key: hotel.reservationId,
      hotel,
      answer: this.answers.hotels[hotel.reservationId] || {
        score: DEFAULT_SCORE
      }
    }));
  }

  get courseCards() {
    const items = (this.ctx && this.ctx.golfCourses) || [];
    return items.map((course) => ({
      key: course.reservationId,
      course,
      answer: this.answers.golfCourses[course.reservationId] || {
        score: DEFAULT_SCORE
      }
    }));
  }

  // ------------------------------------------------------------------
  // Thank-you screen

  get showPublicReview() {
    return earnsPublicReview(this.answers.recommendation);
  }
  get trustpilotUrl() {
    return this.ctx && this.ctx.trustpilotUrl;
  }
  get googleMapsUrl() {
    return this.ctx && this.ctx.googleMapsUrl;
  }
  get hasReviewLinks() {
    return Boolean(this.trustpilotUrl || this.googleMapsUrl);
  }

  // ------------------------------------------------------------------
  // Answer handlers

  handleScore(event) {
    const field = event.currentTarget.dataset.field;
    this.answers[field] = event.detail.value;
  }

  /**
   * Screen 1's two comments hang off their own fields rather than a `*.comment`
   * sub-object, so they get named handlers instead of the data-field lookup.
   */
  handleOverallComment(event) {
    this.answers.overallExperienceComment = event.detail.comment;
  }

  handleConsultationComment(event) {
    this.answers.consultationComment = event.detail.comment;
  }

  handleServiceScore(event) {
    const field = event.currentTarget.dataset.field;
    this.answers[field] = {
      ...this.answers[field],
      score: event.detail.value
    };
  }

  handleServiceComment(event) {
    const field = event.currentTarget.dataset.field;
    this.answers[field] = {
      ...this.answers[field],
      comment: event.detail.comment
    };
  }

  handleText(event) {
    this.answers[event.currentTarget.dataset.field] = event.target.value;
  }

  handleHotelScore(event) {
    this.patchItem("hotels", event.detail.reservationId, {
      score: event.detail.score
    });
  }

  handleHotelComment(event) {
    this.patchItem("hotels", event.detail.reservationId, {
      comment: event.detail.comment
    });
  }

  handleHotelSub(event) {
    const { reservationId, category, score } = event.detail;
    const current = this.answers.hotels[reservationId] || {};
    this.patchItem("hotels", reservationId, {
      sub: { ...(current.sub || {}), [category]: score }
    });
  }

  handleCourseScore(event) {
    this.patchItem("golfCourses", event.detail.reservationId, {
      score: event.detail.score
    });
  }

  handleCourseComment(event) {
    this.patchItem("golfCourses", event.detail.reservationId, {
      comment: event.detail.comment
    });
  }

  patchItem(collection, reservationId, patch) {
    if (!reservationId) {
      return;
    }
    const existing = this.answers[collection][reservationId] || {
      score: DEFAULT_SCORE
    };
    this.answers[collection] = {
      ...this.answers[collection],
      [reservationId]: { ...existing, ...patch }
    };
  }

  // ------------------------------------------------------------------
  // Navigation

  handleBack() {
    const previous = previousScreen(this.screen, this.ctx);
    if (previous !== null) {
      this.screen = previous;
      this.scrollToTop();
    }
  }

  handleNext() {
    if (this.isFinalStep) {
      this.send();
      return;
    }
    this.screen = nextScreen(this.screen, this.ctx);
    this.scrollToTop();
  }

  async send() {
    if (this.submitting) {
      return;
    }
    this.submitting = true;
    this.submitError = undefined;

    const payload = buildPayload({
      context: this.ctx,
      bookingNumber: this.bookingNumber,
      secret: this.secret,
      answers: this.answers
    });

    try {
      const result = await submit({ payloadJson: JSON.stringify(payload) });
      if (result && result.ok) {
        this.reference = result.reference;
        this.screen = SCREEN.THANKS;
        this.scrollToTop();
      } else {
        this.submitError =
          (result && result.message) ||
          "Ihr Feedback konnte nicht gespeichert werden.";
      }
    } catch {
      this.submitError =
        "Ihr Feedback konnte nicht gesendet werden. Bitte versuchen Sie es später erneut.";
    } finally {
      this.submitting = false;
    }
  }

  scrollToTop() {
    const top = this.template.querySelector(".survey");
    if (top && top.scrollIntoView) {
      top.scrollIntoView({ behavior: "smooth", block: "start" });
    }
  }
}
