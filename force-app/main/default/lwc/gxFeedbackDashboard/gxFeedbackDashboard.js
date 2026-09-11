import { LightningElement, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import { NavigationMixin } from "lightning/navigation";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import GxResponseModal from "c/gxResponseModal";
import getDashboard from "@salesforce/apex/GxFeedbackDashboardController.getDashboard";
import getFilterOptions from "@salesforce/apex/GxFeedbackDashboardController.getFilterOptions";
import findResponses from "@salesforce/apex/GxFeedbackDashboardController.findResponses";
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
  categoryLabel,
  pageOf,
  GROUP_OPTIONS,
  SORT_OPTIONS,
  responseListRows,
  responsesSummary,
  designerRows
} from "c/gxDashboardView";

/** How long typing pauses before the search runs. */
const SEARCH_DELAY_MS = 350;

/**
 * gxFeedbackDashboard
 *
 * The team's view of post-trip feedback. The numbers are computed by
 * GxFeedbackDashboardController in one call per filter change; the response
 * list is its own call, so searching and paging it never reloads the rest.
 * This component holds the filters, the search, the follow-up drafts, the
 * open drill-down and which page each list is on. Every response it shows
 * opens in full in gxResponseModal.
 */
export default class GxFeedbackDashboard extends NavigationMixin(
  LightningElement
) {
  filters = defaultFilters();
  filtersJson = filtersPayload(this.filters);

  data;
  error;
  loading = true;

  options = { regions: [], countries: [], travelTypes: [], designers: [] };
  categoryOptions = CATEGORY_OPTIONS;
  followUpOptions = FOLLOW_UP_OPTIONS;
  sortOptions = SORT_OPTIONS;

  // The response list: what is typed, what was searched, and how it is cut.
  searchInput = "";
  searchTerm = "";
  searchTimer;
  responseGroup = "all";
  responseSort = "newest";
  responsePage = 1;
  responses;
  responsesLoading = true;
  wiredResponsesResult;

  showHandled = false;
  lowOnly = false;
  drafts = {};
  savingId;

  drill;

  /** Which page each list is on, by list name. Missing means page 1. */
  pages = {};

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

  @wire(findResponses, {
    filtersJson: "$filtersJson",
    search: "$searchTerm",
    groupName: "$responseGroup",
    sortBy: "$responseSort",
    pageNumber: "$responsePage"
  })
  wiredResponses(result) {
    this.wiredResponsesResult = result;
    if (result.data) {
      this.responses = result.data;
      this.responsesLoading = false;
    } else if (result.error) {
      this.responses = undefined;
      this.responsesLoading = false;
      this.toast(
        "Couldn't load the responses",
        messageOf(result.error),
        "error"
      );
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

  get designerOptions() {
    return withAll(this.options.designers, "All travel designers");
  }

  // ------------------------------------------------------------------
  // The response list

  get responseRows() {
    return responseListRows(this.responses && this.responses.rows);
  }

  get hasResponseRows() {
    return this.responseRows.length > 0;
  }

  get responsesTotal() {
    return (this.responses && this.responses.total) || 0;
  }

  get responsesPageNo() {
    return (this.responses && this.responses.page) || 1;
  }

  get responsesPageSize() {
    return (this.responses && this.responses.pageSize) || 10;
  }

  get responsesSummary() {
    return responsesSummary(this.responses, this.searchTerm);
  }

  get responsesCapNote() {
    return this.responses && this.responses.capped
      ? "Paging stops here. Search, or narrow the dates, to reach older responses."
      : null;
  }

  get groupChips() {
    return GROUP_OPTIONS.map((g) => ({
      ...g,
      pressed: g.value === this.responseGroup ? "true" : "false",
      cls: g.value === this.responseGroup ? "chip chip_on" : "chip"
    }));
  }

  handleSearch(event) {
    this.searchInput = event.detail.value || "";
    clearTimeout(this.searchTimer);
    // Wait for a pause in typing rather than searching on every keystroke.
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.searchTimer = setTimeout(() => {
      const term = this.searchInput.trim();
      if (term !== this.searchTerm) {
        this.searchTerm = term;
        this.responsePage = 1;
      }
    }, SEARCH_DELAY_MS);
  }

  handleGroup(event) {
    this.responseGroup = event.currentTarget.dataset.value;
    this.responsePage = 1;
  }

  handleSort(event) {
    this.responseSort = event.detail.value;
    this.responsePage = 1;
  }

  handleResponsePage(event) {
    this.responsePage = event.detail.page;
    this.scrollToSection("responses");
  }

  // ------------------------------------------------------------------
  // Travel designers

  get designers() {
    return designerRows(
      this.data && this.data.designers,
      this.filters.designer
    );
  }

  get hasDesigners() {
    return this.designers.length > 0;
  }

  get designerPage() {
    return pageOf(this.designers, this.pages.designers);
  }

  get designerFiltered() {
    return Boolean(this.filters.designer);
  }

  handleDesignerSelect(event) {
    const id = event.currentTarget.dataset.id;
    this.applyFilters({
      ...this.filters,
      designer: this.filters.designer === id ? "" : id
    });
  }

  clearDesigner() {
    this.applyFilters({ ...this.filters, designer: "" });
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

  get heatPage() {
    return pageOf(this.hotelDetail, this.pages.heat);
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

  get followUpPage() {
    return pageOf(this.followUps, this.pages.followups);
  }

  /** Said only when the server sent fewer cases than the selection holds. */
  get followUpCapNote() {
    const total = (this.data && this.data.followUpsTotal) || 0;
    const sent = ((this.data && this.data.followUps) || []).length;
    return total > sent
      ? `Showing ${sent} of ${total} unhappy guests, open cases first. Narrow the dates to reach the rest.`
      : null;
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

  get destinationPage() {
    return pageOf(this.destinations, this.pages.destinations);
  }

  get destinationsCapNote() {
    return this.data && this.data.destinationsCapped
      ? "From the most recent responses. Narrow the dates to see older wishes."
      : null;
  }

  get comments() {
    const rows = commentRows(this.data && this.data.comments);
    return this.lowOnly ? rows.filter((c) => c.low) : rows;
  }

  get lowOnlyLabel() {
    return this.lowOnly ? "Show all comments" : "Only low scores";
  }

  get commentPage() {
    return pageOf(this.comments, this.pages.comments);
  }

  get commentsCapNote() {
    return this.data && this.data.commentsCapped
      ? "The most recent comments. Narrow the dates to see older ones."
      : null;
  }

  get commentsEmptyText() {
    return this.lowOnly
      ? "No low-scoring comments in this selection."
      : "No comments in this selection.";
  }

  toggleLowOnly() {
    this.lowOnly = !this.lowOnly;
    this.setPage("comments", 1);
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

  get drillPage() {
    return pageOf(this.drill ? this.drill.rows : [], this.pages.drill);
  }

  // ------------------------------------------------------------------
  // Paging and full responses

  handlePage(event) {
    const list = event.currentTarget.dataset.list;
    this.setPage(list, event.detail.page);
    // Paging from the foot of a long list would leave the reader looking at
    // the end of the new page; bring its top back into view.
    const section = this.template.querySelector(`[data-section="${list}"]`);
    if (
      section &&
      section.scrollIntoView &&
      section.getBoundingClientRect().top < 0
    ) {
      section.scrollIntoView({ behavior: "smooth", block: "start" });
    }
  }

  setPage(list, page) {
    this.pages = { ...this.pages, [list]: page };
  }

  async handleOpenResponse(event) {
    const responseId = event.currentTarget.dataset.responseId;
    if (!responseId) {
      return;
    }
    const result = await GxResponseModal.open({
      size: "medium",
      label: "Feedback response",
      description: "The guest's whole answer, screen by screen",
      responseId
    });
    if (result && result.navigate) {
      this[NavigationMixin.Navigate]({
        type: "standard__recordPage",
        attributes: { recordId: result.navigate, actionName: "view" }
      });
    }
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
      this.pages = {};
      this.responsePage = 1;
      this.filtersJson = json;
    }
  }

  async handleRefresh() {
    this.loading = true;
    try {
      await Promise.all([
        refreshApex(this.wiredDashboard),
        refreshApex(this.wiredResponsesResult)
      ]);
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
    this.setPage("drill", 1);
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
    this.setPage("followups", 1);
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
      await Promise.all([
        refreshApex(this.wiredDashboard),
        refreshApex(this.wiredResponsesResult)
      ]);
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

  disconnectedCallback() {
    clearTimeout(this.searchTimer);
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
