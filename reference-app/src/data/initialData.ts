import { TripItinerary, CeoVideoConfig, FullSurveyData } from '../types';

export const initialTripItinerary: TripItinerary = {
  guestTitle: 'Dr.',
  guestName: 'Maximilian von Bern',
  bookingReference: 'GX-2026-VAL892',
  tripName: 'Andalusia Golf Trophy & Valderrama Masters Experience',
  travelDates: '18. July – 25. July 2026',
  destination: 'Costa del Sol & Marbella, Spain',
  flights: [
    {
      airline: 'Swiss International Air Lines',
      flightNumber: 'LX 2110',
      route: 'Zürich (ZRH) ➔ Málaga (AGP)',
      class: 'Business Class'
    },
    {
      airline: 'Swiss International Air Lines',
      flightNumber: 'LX 2111',
      route: 'Málaga (AGP) ➔ Zürich (ZRH)',
      class: 'Business Class'
    }
  ],
  transfer: 'Private Luxury Chauffeur Mercedes-Maybach S-Class with Golf Bag Vault',
  hotel: {
    name: 'Anantara Villa Padierna Palace Benahavís Resort',
    location: 'Marbella, Andalusia, Spain',
    roomType: 'Deluxe Suite with Golf & Sea View',
    nights: 7,
    image: 'https://images.unsplash.com/photo-1566073771259-6a8506099945?auto=format&fit=crop&w=1200&q=80'
  },
  golfCourses: [
    {
      name: 'Real Club Valderrama',
      holes: 18,
      par: 71,
      teeTime: '19. Jul 09:30 AM (VIP Starter Slot)',
      image: 'https://images.unsplash.com/photo-1587174486073-ae5e5cff23aa?auto=format&fit=crop&w=1200&q=80',
      highlight: 'Ryder Cup venue & Championship Greens'
    },
    {
      name: 'Finca Cortesín Golf Club',
      holes: 18,
      par: 72,
      teeTime: '21. Jul 10:15 AM (Private Buggy Included)',
      image: 'https://images.unsplash.com/photo-1535131749006-b7f58c99034b?auto=format&fit=crop&w=1200&q=80',
      highlight: 'Solheim Cup 2023 Host & Luxury Clubhouse'
    },
    {
      name: 'Club de Campo La Zagaleta',
      holes: 18,
      par: 72,
      teeTime: '23. Jul 08:45 AM (Exclusive Member Access)',
      image: 'https://images.unsplash.com/photo-1600585154340-be6161a56a0c?auto=format&fit=crop&w=1200&q=80',
      highlight: 'Ultra-private estate course in Marbella hills'
    }
  ],
  specialWishes: [
    'Hand-selected English & German speaking Pro Caddies for Valderrama',
    'Custom TaylorMade Qi10 Rental Set fitted with Stiff Graphite Shafts',
    'Post-Round Spa Massage reserved at Anantara Thermal Spa',
    'Private Table at Michelin Star Restaurant Skina in Marbella Old Town'
  ],
  treePlantedId: 'TREE-GX-884920',
  treeSpecies: 'Noble Oak (Quercus robur)',
  treeLocation: 'Bavarian Alps Reforestation Sanctuary, Germany',
  treeGps: '47.6749° N, 11.8542° E',
  co2OffsetKg: 250,
  trustpilotUrl: 'https://www.trustpilot.com/evaluate/emu-travel.com',
  googleMapsUrl: 'https://maps.google.com/?q=golf.extra+GmbH+Heilbronn'
};

export const initialCeoVideoConfig: CeoVideoConfig = {
  ceoName: 'Erguel Erguel',
  ceoTitle: 'CEO & Founder, Golf Extra | PGA Professional',
  videoPoster: 'https://images.unsplash.com/photo-1535131749006-b7f58c99034b?auto=format&fit=crop&w=1200&q=80',
  durationSeconds: 94,
  transcripts: {
    DE: `Sehr geehrter Dr. von Bern,

hier ist Erguel Erguel, CEO von Golf Extra und Ihr PGA Professional.

Im Namen unseres gesamten Teams möchte ich mich ganz herzlich bei Ihnen bedanken, dass Sie uns Ihre wertvollste Zeit anvertraut haben. Für uns bei Golf Extra ist jede Reise nicht nur eine Buchung – sie ist eine persönliche Passion für erstklassigen Golfsport und unvergleichlichen Luxus.

Wir hoffen, dass Ihr Aufenthalt im Anantara Villa Padierna Palace und Ihre Runden auf Valderrama sowie Finca Cortesín unvergesslich waren. Um unseren Standard kontinuierlich auf dem höchsten Niveau zu halten, bitten wir Sie um ein kurzes Feedback.

Als Zeichen unserer Dankbarkeit haben wir mit Ihrem Urlaub bereits einen Baum in Ihrem Namen in den Bayerischen Alpen gepflanzt.

Vielen Dank für Ihr Vertrauen. Ich wünsche Ihnen weiterhin schönes Spiel!`,
    EN: `Dear Dr. von Bern,

This is Erguel Erguel, CEO of Golf Extra and your PGA Professional.

On behalf of our entire team, I would like to express my sincere gratitude to you for trusting us with your precious golf travel. At Golf Extra, every journey is not just a reservation — it is a personal passion for world-class golf and uncompromising luxury.

We hope your stay at Anantara Villa Padierna Palace and your rounds at Valderrama and Finca Cortesín were truly unforgettable. To ensure we maintain the highest standards, we kindly invite you to share your feedback.

As a token of our appreciation and our commitment to our planet, a tree has been planted in your name in the Bavarian Alps for this booking.

Thank you once again for traveling with us. Wishing you fairways and greens!`
  }
};

export const defaultFullSurveyData: FullSurveyData = {
  overallExperience: 10,
  overallExperienceComment: '',
  consultationProductSelection: 10,
  consultationComment: '',

  services: {
    flight: true,
    hotels: true,
    transfers: true,
    golfCourses: true,
    rentalCar: false
  },

  flightRating: 10,
  flightComment: '',

  transfersRating: 10,
  transfersComment: '',

  rentalCarRating: 10,
  rentalCarComment: '',

  hotelRatings: {
    'Anantara Villa Padierna Palace Benahavís Resort': 10
  },
  hotelComments: {},
  hotelComment: '',

  golfCourseRatings: {
    'Real Club Valderrama': 10,
    'Finca Cortesín Golf Club': 10,
    'Club de Campo La Zagaleta': 10
  },
  golfCourseComments: {},
  golfCourseComment: '',

  recommendation: 10,

  nextBucketListDestination: '',
  positiveMoment: '',
  improvementSuggestions: '',
  generalFeedback: '',

  sustainabilityImportance: 10
};

export const sampleDemoSurveyData: FullSurveyData = {
  overallExperience: 10,
  overallExperienceComment: '',
  consultationProductSelection: 10,
  consultationComment: '',

  services: {
    flight: true,
    hotels: true,
    transfers: true,
    golfCourses: true,
    rentalCar: false
  },

  flightRating: 10,
  flightComment: 'Swiss Business Class flight was smooth and golf equipment arrived in perfect condition.',

  transfersRating: 10,
  transfersComment: 'Driver was punctual, professional, and Maybach vault accommodated golf bags easily.',

  rentalCarRating: 10,
  rentalCarComment: '',

  hotelRatings: {
    'Anantara Villa Padierna Palace Benahavís Resort': 10
  },
  hotelComments: {},
  hotelComment: 'Anantara Villa Padierna surpassed expectations in room quality and thermal spa treatments.',

  golfCourseRatings: {
    'Real Club Valderrama': 10,
    'Finca Cortesín Golf Club': 10,
    'Club de Campo La Zagaleta': 10
  },
  golfCourseComments: {},
  golfCourseComment: 'Caddies at Valderrama were exceptional. Greens were PGA championship caliber.',

  recommendation: 10,

  nextBucketListDestination: 'Pebble Beach Golf Links & St. Andrews Old Course',
  positiveMoment: 'Teeing off on the 17th hole at Real Club Valderrama with our PGA Pro caddie!',
  improvementSuggestions: 'Seamless experience. Everything was coordinated perfectly down to the tee times.',
  generalFeedback: 'Herzlichen Dank an Mr. Erguel und das gesamte Golf Extra Team.',

  sustainabilityImportance: 10
};

