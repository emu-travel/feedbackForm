import { LightningElement, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getDashboard from "@salesforce/apex/GxFeedbackDashboardController.getDashboard";
import getFilterOptions from "@salesforce/apex/GxFeedbackDashboardController.getFilterOptions";
import getVenueDetail from "@salesforce/apex/GxFeedbackDashboardController.getVenueDetail";
import updateFollowUp from "@salesforce/apex/GxFeedbackDashboardController.updateFollowUp";
import {
  CATEGORY_OPTIONS,
  FOLLOW_UP_OPTIONS,
  defaultFilters,
  filtersPayload,
  withAll,
  kpiTiles,
  trendBars,
  venueList,
  heatRows,
  followUpRows,
  destinationRows,
  commentRows,
  drillRows,
  categoryLabel
} from "c/gxDashboardView";

/**
 * gxFeedbackDashboard
 *
 * The team's view of post-trip feedback. Everything is computed by
 * GxFeedbackDashboardController in one call per filter change; this component
 * only holds the filters, the follow-up drafts and the open drill-down.
 */
export default class GxFeedbackDashboard extends LightningElement {
  filters = defaultFilters();
  filtersJson = filtersPayload(this.filters);

  data;
  error;
  loading = true;

  options = { regions: [], countries: [], travelTypes: [] };
  categoryOptions = CATEGORY_OPTIONS;
  followUpOptions = FOLLOW_UP_OPTIONS;

  showHandled = false;
  lowOnly = false;
  drafts = {};
  savingId;

  drill;

  wiredDashboard;

  @wire(getDashboard, { filtersJson: "$filtersJson" })
  wiredData(result) {
    this.wiredDashboard = result;
    if (result.data) {
      this.data = result.data;
      this.error = undefined;
      this.loading = false;
    } else if (result.error) {
      this.error = messageOf(result.error);
      this.data = undefined;
      this.loading = false;
    }
  }

  @wire(getFilterOptions)
  wiredOptions({ data }) {
    if (data) {
      this.options = data;
    }
  }

  // ------------------------------------------------------------------
  // What the template reads

  get regionOptions() {
    return withAll(this.options.regions, "All regions");
  }

  get countryOptions() {
    return withAll(this.options.countries, "All countries");
  }

  get travelTypeOptions() {
    return withAll(this.options.travelTypes, "All travel types");
  }

  get kpis() {
    return kpiTiles(this.data && this.data.kpis).map((k) => ({
      ...k,
      cls: k.alert ? "kpi kpi_alert" : "kpi"
    }));
  }

  get isEmpty() {
    return Boolean(this.data) && this.data.kpis.responses === 0;
  }

  get trend() {
    return trendBars(this.data && this.data.trend);
  }

  get hasTrend() {
    return this.trend.length > 0;
  }

  get minRatings() {
    return (this.data && this.data.minRatings) || 3;
  }

  get hotelBoard() {
    return venueList(this.data && this.data.hotels);
  }

  get golfBoard() {
    return venueList(this.data && this.data.golf);
  }

  get supplierBoard() {
    return venueList(this.data && this.data.suppliers);
  }

  get rankingHint() {
    return `Ranked once a venue has ${this.minRatings} ratings. Overall scores only — sub-ratings are shown separately below. Select a venue to see every rating.`;
  }

  get hotelDetail() {
    return heatRows(this.data && this.data.hotelDetail);
  }

  get hasHotelDetail() {
    return this.hotelDetail.length > 0;
  }

  get followUps() {
    return followUpRows(this.data && this.data.followUps, this.showHandled).map(
      (r) => {
        const draft = this.drafts[r.key] || {};
        return {
          ...r,
          draftStatus: draft.status !== undefined ? draft.status : r.status,
          draftNote:
            draft.note !== undefined ? draft.note : r.followUpNote || "",
          saving: this.savingId === r.key
        };
      }
    );
  }

  get hasFollowUps() {
    return this.followUps.length > 0;
  }

  get followUpEmptyText() {
    return this.showHandled
      ? "No unhappy guests in this selection."
      : "No open cases. Every detractor in this selection has been contacted.";
  }

  get handledToggleLabel() {
    return this.showHandled ? "Hide handled" : "Show handled";
  }

  get destinations() {
    return destinationRows(this.data && this.data.nextDestinations);
  }

  get hasDestinations() {
    return this.destinations.length > 0;
  }

  get comments() {
    const rows = commentRows(this.data && this.data.comments);
    return this.lowOnly ? rows.filter((c) => c.low) : rows;
  }

  get lowOnlyLabel() {
    return this.lowOnly ? "Show all comments" : "Only low scores";
  }

  get commentsEmptyText() {
    return this.lowOnly
      ? "No low-scoring comments in this selection."
      : "No comments in this selection.";
  }

  toggleLowOnly() {
    this.lowOnly = !this.lowOnly;
  }

  handleKpiClick(event) {
    this.scrollToSection(event.currentTarget.dataset.target);
  }

  scrollToSection(name) {
    const section = this.template.querySelector(`[data-section="${name}"]`);
    if (section && section.scrollIntoView) {
      section.scrollIntoView({ behavior: "smooth", block: "start" });
    }
  }

  get hasComments() {
    return this.comments.length > 0;
  }

  get drillTitle() {
    return this.drill
      ? `${this.drill.name} · ${categoryLabel(this.drill.category)}`
      : "";
  }

  get drillCount() {
    if (!this.drill || this.drill.loading) {
      return "";
    }
    const n = this.drill.rows.length;
    return n === 1 ? "1 guest" : `${n} guests`;
  }

  // ------------------------------------------------------------------
  // Filters

  handleFilter(event) {
    const field = event.currentTarget.dataset.field;
    this.applyFilters({ ...this.filters, [field]: event.detail.value || "" });
  }

  handleAllTime() {
    this.applyFilters({ ...this.filters, fromDate: "", toDate: "" });
  }

  handleReset() {
    this.applyFilters(defaultFilters());
  }

  applyFilters(next) {
    this.filters = next;
    const json = filtersPayload(next);
    if (json !== this.filtersJson) {
      this.loading = true;
      this.drill = undefined;
      this.filtersJson = json;
    }
  }

  async handleRefresh() {
    this.loading = true;
    try {
      await refreshApex(this.wiredDashboard);
    } finally {
      this.loading = false;
    }
  }

  // ------------------------------------------------------------------
  // Drill-down

  handleVenueSelect(event) {
    const { name, category } = event.detail;
    this.openDrill(name, category);
  }

  /** The hotel names in the detail grid open the same drill-down. */
  handleHeatSelect(event) {
    const { name, category } = event.currentTarget.dataset;
    this.openDrill(name, category);
  }

  async openDrill(name, category) {
    this.drill = { name, category, rows: [], loading: true };
    // Opened from further down the page, the panel would appear off screen.
    Promise.resolve().then(() => this.scrollToSection("drill"));
    try {
      const rows = await getVenueDetail({
        filtersJson: this.filtersJson,
        category,
        itemName: name
      });
      this.drill = { name, category, rows: drillRows(rows), loading: false };
    } catch (e) {
      this.drill = undefined;
      this.toast("Couldn't load that venue", messageOf(e), "error");
    }
  }

  closeDrill() {
    this.drill = undefined;
  }

  // ------------------------------------------------------------------
  // Follow-up

  toggleHandled() {
    this.showHandled = !this.showHandled;
  }

  handleStatusChange(event) {
    this.setDraft(event.currentTarget.dataset.id, {
      status: event.detail.value
    });
  }

  handleNoteChange(event) {
    this.setDraft(event.currentTarget.dataset.id, {
      note: event.detail.value
    });
  }

  setDraft(id, patch) {
    this.drafts = { ...this.drafts, [id]: { ...this.drafts[id], ...patch } };
  }

  async handleSaveFollowUp(event) {
    const id = event.currentTarget.dataset.id;
    const row = this.followUps.find((r) => r.key === id);
    if (!row) {
      return;
    }
    // Saving what is already saved would stamp a new name and date on the
    // case and make it look worked on when nothing happened.
    const unchanged =
      row.draftStatus === row.status &&
      (row.draftNote || "") === (row.followUpNote || "");
    if (unchanged) {
      this.toast(
        "Nothing to save",
        "Change the status or add a note first.",
        "info"
      );
      return;
    }
    this.savingId = id;
    try {
      await updateFollowUp({
        responseId: id,
        status: row.draftStatus,
        note: row.draftNote
      });
      const rest = { ...this.drafts };
      delete rest[id];
      this.drafts = rest;
      await refreshApex(this.wiredDashboard);
      this.toast(
        "Follow-up saved",
        `${row.bookingNumber} is now ${row.draftStatus}.`,
        "success"
      );
    } catch (e) {
      this.toast("Couldn't save the follow-up", messageOf(e), "error");
    } finally {
      this.savingId = undefined;
    }
  }

  toast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}

function messageOf(error) {
  if (!error) {
    return "Something went wrong.";
  }
  if (error.body && error.body.message) {
    return error.body.message;
  }
  return error.message || "Something went wrong.";
}
