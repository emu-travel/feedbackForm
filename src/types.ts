export type Language = 'DE' | 'EN';

export interface FlightDetail {
  airline: string;
  flightNumber: string;
  route: string;
  class: string;
}

export interface HotelDetail {
  name: string;
  location: string;
  roomType: string;
  nights: number;
  image: string;
}

export interface GolfCourseDetail {
  name: string;
  holes: number;
  par: number;
  teeTime: string;
  image: string;
  highlight: string;
}

export interface TripItinerary {
  guestTitle: string;
  guestName: string;
  bookingReference: string;
  tripName: string;
  travelDates: string;
  destination: string;
  flights: FlightDetail[];
  transfer: string;
  hotel: HotelDetail;
  hotels?: HotelDetail[];
  golfCourses: GolfCourseDetail[];
  specialWishes: string[];
  treePlantedId: string;
  treeSpecies: string;
  treeLocation: string;
  treeGps: string;
  co2OffsetKg: number;
  trustpilotUrl?: string;
  googleMapsUrl?: string;
}

export interface CeoVideoConfig {
  ceoName: string;
  ceoTitle: string;
  videoPoster: string;
  videoUrl?: string;
  durationSeconds: number;
  transcripts: {
    DE: string;
    EN: string;
  };
}

export interface BookedServices {
  flight: boolean;
  hotels: boolean;
  transfers: boolean;
  golfCourses: boolean;
  rentalCar: boolean;
}

export interface FullSurveyData {
  // Screen 1: Initial Feedback (1-10 NPS Scale)
  overallExperience: number; // 1-10
  overallExperienceComment?: string;
  consultationProductSelection: number; // 1-10
  consultationComment?: string;

  // Booked Services Status
  services: BookedServices;

  // Transportation (Screen 1)
  flightRating: number; // 1-10
  flightComment: string;
  transfersRating: number; // 1-10
  transfersComment: string;
  rentalCarRating: number; // 1-10
  rentalCarComment: string;

  // Screen 2: Hotels (Overall rating per booked hotel; sub-categories expand if rating < 9)
  hotelRatings?: Record<string, number>; // hotel name -> 1-10
  hotelSubRatings?: Record<string, {
    room?: number;
    service?: number;
    catering?: number;
    cleanliness?: number;
  }>;
  hotelComments?: Record<string, string>; // hotel name -> comment
  hotelComment: string; // general hotel comment

  // Screen 3: Golf Courses
  golfCourseRatings: Record<string, number>; // name -> 1-10
  golfCourseComments?: Record<string, string>; // name -> comment
  golfCourseComment: string; // general golf courses comment

  // Screen 4: Recommendation & Final Remarks (1-10 NPS Scale)
  recommendation: number; // 1-10 NPS rating score
  nextBucketListDestination?: string;
  positiveMoment?: string;
  improvementSuggestions: string;
  generalFeedback: string;

  // Sustainability
  sustainabilityImportance: number; // 1-10
}

export interface SubmittedFeedback {
  id: string;
  timestamp: string;
  guestName: string;
  bookingRef: string;
  surveyData: FullSurveyData;
  treePlantedConfirmed: boolean;
}

