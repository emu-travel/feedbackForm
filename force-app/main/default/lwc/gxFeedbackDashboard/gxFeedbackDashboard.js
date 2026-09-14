import { LightningElement, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import { NavigationMixin } from "lightning/navigation";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import GxResponseModal from "c/gxResponseModal";
import getDashboard from "@salesforce/apex/GxFeedbackDashboardController.getDashboard";
import getFilterOptions from "@salesforce/apex/GxFeedbackDashboardController.getFilterOptions";
import findResponses from "@salesforce/apex/GxFeedbackDashboardController.findResponses";
import exportResponses from "@salesforce/apex/GxFeedbackDashboardController.exportResponses";
import getVenueDetail from "@salesforce/apex/GxFeedbackDashboardController.getVenueDetail";
import getVenueScores from "@salesforce/apex/GxFeedbackDashboardController.getVenueScores";
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
  venueMatches,
  venueSearchSummary,
  heatRows,
  followUpRows,
  destinationRows,
  drillRows,
  categoryLabel,
  pageOf,
  GROUP_OPTIONS,
  SORT_OPTIONS,
  responseListRows,
  responsesSummary,
  designerRows,
  exportMessage,
  nameMatches,
  pagingNote,
  plural
} from "c/gxDashboardView";

/** How long typing pauses before the search runs. */
const SEARCH_DELAY_MS = 350;

/**
 * gxFeedbackDashboard
 *
 * The team's view of post-trip feedback, from GxFeedbackDashboardController:
 * headline numbers and lists in one call, venue scores in another - each has
 * its own row limit, so a selection too big for one still shows the other -
 * and the response list in a call of its own, so searching and paging it
 * never reloads the rest.
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
  exporting = false;

  showHandled = false;
  drafts = {};
  savingId;

  drill;

  /** Which page each list is on, by list name. Missing means page 1. */
  pages = {};

  wiredDashboard;

  // Venue and partner scores: a call of their own.
  venues;
  venuesError;
  venuesLoading = true;
  wiredVenuesResult;

  /** Derived lists, each rebuilt only when what it is built from changes. */
  _memo = {};

  memo(name, deps, build) {
    const hit = this._memo[name];
    if (
      hit &&
      hit.deps.length === deps.length &&
      hit.deps.every((d, i) => d === deps[i])
    ) {
      return hit.value;
    }
    const value = build();
    this._memo[name] = { deps, value };
    return value;
  }

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

  @wire(getVenueScores, { filtersJson: "$filtersJson" })
  wiredVenues(result) {
    this.wiredVenuesResult = result;
    if (result.data) {
      this.venues = result.data;
      this.venuesError = undefined;
      this.venuesLoading = false;
    } else if (result.error) {
      this.venues = undefined;
      this.venuesError = messageOf(result.error);
      this.venuesLoading = false;
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
    return this.memo("responseRows", [this.responses], () =>
      responseListRows(this.responses && this.responses.rows)
    );
  }

  /** The pager counts what paging can reach, so "next" never dead-ends. */
  get responsesPagerTotal() {
    return this.responses && this.responses.capped
      ? this.responses.reachable
      : this.responsesTotal;
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
    return pagingNote(
      this.responses,
      "responses",
      "Search, pick a group, or narrow the dates to reach the rest."
    );
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

  get exportDisabled() {
    return this.exporting || this.responsesTotal === 0;
  }

  get exportLabel() {
    return this.exporting ? "Exporting…" : "Export to Excel";
  }

  /**
   * Everything the list is showing - all pages of it - as a spreadsheet.
   * The byte order mark tells Excel the file is UTF-8, so umlauts survive.
   */
  async handleExport() {
    this.exporting = true;
    try {
      const result = await exportResponses({
        filtersJson: this.filtersJson,
        search: this.searchTerm,
        groupName: this.responseGroup,
        sortBy: this.responseSort
      });
      if (result && result.rows) {
        this.download(result.fileName, result.csv);
      }
      this.toast(
        result && result.capped ? "Export cut short" : "Exported",
        exportMessage(result),
        result && result.capped ? "warning" : "success"
      );
    } catch (e) {
      this.toast("Couldn't export", messageOf(e), "error");
    } finally {
      this.exporting = false;
    }
  }

  download(fileName, csv) {
    const blob = new Blob(["\ufeff" + csv], {
      type: "text/csv;charset=utf-8"
    });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = fileName;
    link.style.display = "none";
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    // Revoked a moment later: some browsers still need it as the save begins.
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    setTimeout(() => URL.revokeObjectURL(url), 10000);
  }

  // ------------------------------------------------------------------
  // Travel designers

  get designers() {
    return this.memo("designers", [this.data, this.filters.designer], () =>
      designerRows(this.data && this.data.designers, this.filters.designer)
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
    return this.memo("kpis", [this.data], () =>
      kpiTiles(this.data && this.data.kpis).map((k) => ({
        ...k,
        cls: k.alert ? "kpi kpi_alert" : "kpi"
      }))
    );
  }

  get isEmpty() {
    return Boolean(this.data) && this.data.kpis.responses === 0;
  }

  get trend() {
    return this.memo("trend", [this.data], () =>
      trendBars(this.data && this.data.trend)
    );
  }

  get hasTrend() {
    return this.trend.length > 0;
  }

  get minRatings() {
    return (this.venues && this.venues.minRatings) || 3;
  }

  /**
   * Built once per set of venue scores. A fresh object would reach the board
   * as a new board and send it back to page one on every re-render - opening
   * a venue, or typing a follow-up note, would lose the reader's place.
   */
  get hotelBoard() {
    return this.memo("hotelBoard", [this.venues], () =>
      venueList(this.venues && this.venues.hotels)
    );
  }

  get golfBoard() {
    return this.memo("golfBoard", [this.venues], () =>
      venueList(this.venues && this.venues.golf)
    );
  }

  get supplierBoard() {
    return this.memo("supplierBoard", [this.venues], () =>
      venueList(this.venues && this.venues.suppliers)
    );
  }

  get venuesPending() {
    return this.venuesLoading && !this.venues;
  }

  get venuesCapNote() {
    return this.venues && this.venues.venuesCapped
      ? "Only the most-rated venues are listed: there are more than one list holds. Narrow the dates or pick a category to see the rest."
      : null;
  }

  get rankingHint() {
    return `Ranked once a venue has ${this.minRatings} ratings. Overall scores only - sub-ratings are shown separately below. Select a venue to see every rating.`;
  }

  // ------------------------------------------------------------------
  // Finding a venue

  /**
   * What is typed in the venue search. It survives a filter change, so
   * "Search all dates" looks for the same venue further back. The venues are
   * already loaded, so it filters as the user types, with no server call.
   */
  venueInput = "";

  get venueTerm() {
    return this.venueInput.trim();
  }

  get venueSearching() {
    return this.venueTerm.length > 0;
  }

  get venueResults() {
    return this.memo("venueResults", [this.venues, this.venueTerm], () =>
      venueMatches(this.venues, this.venueTerm)
    );
  }

  get hasVenueResults() {
    return this.venueResults.length > 0;
  }

  get venueResultPage() {
    return pageOf(this.venueResults, this.pages.venues);
  }

  get venueSearchSummary() {
    return venueSearchSummary(this.venueResults.length, this.venueTerm);
  }

  /** Offered only while dates narrow the selection. */
  get venueCanWiden() {
    const f = this.filters || {};
    return Boolean(f.fromDate || f.toDate);
  }

  handleVenueSearch(event) {
    this.venueInput = event.detail.value || "";
    this.pages = { ...this.pages, venues: 1, heat: 1 };
  }

  handleVenuePick(event) {
    const { name, category } = event.currentTarget.dataset;
    this.openDrill(name, category);
  }

  get hotelDetail() {
    return this.memo("hotelDetail", [this.venues], () =>
      heatRows(this.venues && this.venues.hotelDetail)
    );
  }

  get hasHotelDetail() {
    return this.hotelDetail.length > 0;
  }

  /** The grid follows the venue search, so one hotel's reasons are a search away. */
  get heatRowsShown() {
    return this.memo(
      "heatRowsShown",
      [this.hotelDetail, this.venueTerm],
      () => {
        const term = this.venueTerm;
        return term
          ? this.hotelDetail.filter((row) => nameMatches(row.hotel, term))
          : this.hotelDetail;
      }
    );
  }

  get hasHeatRowsShown() {
    return this.heatRowsShown.length > 0;
  }

  get heatPage() {
    return pageOf(this.heatRowsShown, this.pages.heat);
  }

  get heatSearchNote() {
    if (!this.venueSearching) {
      return null;
    }
    const n = this.heatRowsShown.length;
    return n
      ? `${plural(n, "hotel", "hotels")} matching "${this.venueTerm}"`
      : `No hotel detail matching "${this.venueTerm}" in this selection.`;
  }

  get heatCapNote() {
    return this.venues && this.venues.hotelDetailCapped
      ? "More hotels have detail ratings than the grid holds, so those late in the alphabet are left out. Search for one, or narrow the dates."
      : null;
  }

  get followUps() {
    return this.memo("followUpRows", [this.data, this.showHandled], () =>
      followUpRows(this.data && this.data.followUps, this.showHandled)
    ).map((r) => {
      const draft = this.drafts[r.key] || {};
      return {
        ...r,
        draftStatus: draft.status !== undefined ? draft.status : r.status,
        draftNote: draft.note !== undefined ? draft.note : r.followUpNote || "",
        saving: this.savingId === r.key
      };
    });
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
    return this.memo("destinations", [this.data], () =>
      destinationRows(this.data && this.data.nextDestinations)
    );
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

  handleKpiClick(event) {
    this.scrollToSection(event.currentTarget.dataset.target);
  }

  scrollToSection(name) {
    const section = this.template.querySelector(`[data-section="${name}"]`);
    if (section && section.scrollIntoView) {
      section.scrollIntoView({ behavior: "smooth", block: "start" });
    }
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
    return plural(
      Math.max(this.drill.total || 0, this.drill.rows.length),
      "guest",
      "guests"
    );
  }

  /** Said when a busy venue has more guests than one drill-down shows. */
  get drillCapNote() {
    if (
      !this.drill ||
      this.drill.loading ||
      this.drill.total <= this.drill.rows.length
    ) {
      return null;
    }
    return `Showing the latest ${this.drill.rows.length} of ${this.drill.total}. Narrow the dates to see earlier guests.`;
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
      this.venuesLoading = true;
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
        refreshApex(this.wiredVenuesResult),
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
    this.drill = { name, category, rows: [], total: 0, loading: true };
    this.setPage("drill", 1);
    // Opened from further down the page, the panel would appear off screen.
    Promise.resolve().then(() => this.scrollToSection("drill"));
    try {
      const detail = await getVenueDetail({
        filtersJson: this.filtersJson,
        category,
        itemName: name
      });
      const rows = drillRows(detail && detail.rows);
      this.drill = {
        name,
        category,
        rows,
        total: (detail && detail.total) || rows.length,
        loading: false
      };
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
