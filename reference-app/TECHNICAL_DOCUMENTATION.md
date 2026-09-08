# Technical Documentation: Golf Extra Post-Trip Concierge & Feedback Application

## 1. Executive Overview

The **Golf Extra Post-Trip Concierge & Feedback Application** is a specialized web application engineered for **Golf Extra GmbH (Luxury Golf Travel)**. It provides an end-to-end post-trip guest feedback system that translates booking itineraries into a personalized, interactive guest experience.

The platform simulates a post-travel concierge email dispatched to guests upon their return from a golf journey. From the email view, guests can launch a multi-step feedback survey tailored specifically to their booked services (Flights, Accommodations, Transfers & Chauffeur Services, Golf Courses). Upon completing the survey, guests receive a personalized thank-you message along with direct review links to Trustpilot and Google Maps to share their experience publicly.

---

## 2. Technology Stack & Dependencies

- **Frontend Framework**: React 18+ (TypeScript)
- **Build Tool / Bundler**: Vite
- **Styling**: Tailwind CSS
- **Animation Engine**: `motion` (`motion/react`) for fluid view transitions and micro-interactions
- **Iconography**: `lucide-react`
- **State Management**: React State (`useState`, `useMemo`) with `localStorage` persistence for submitted feedback records
- **Typography & Brand Identity**:
  - Primary Typography: Sans-serif (system body) paired with Serif display headers
  - Brand Palette:
    - **Golf Extra Gold**: `#E59E0F` / `#B87A08`
    - **Deep Forest Green**: `#0f3822` / `#1E3A2B`
    - **Neutral Canvas**: Warm slate and crisp whites

---

## 3. Core Architecture & Component Hierarchy

```
src/
├── main.tsx                      # App entry point
├── App.tsx                       # Root view orchestrator & navigation state
├── index.css                     # Global styles & Tailwind CSS imports
├── types.ts                      # TypeScript interfaces & data models
├── data/
│   └── initialData.ts            # Default guest itinerary & survey defaults
└── components/
    ├── Navbar.tsx                # Brand header & view switcher navigation
    ├── EmailTemplateView.tsx     # Simulated inbox header & concierge invitation email
    ├── SurveyView.tsx            # Multi-screen feedback survey & submission engine
    ├── FeedbackAnalyticsModal.tsx# Feedback log, NPS breakdown & analytics exporter
    ├── EmailCustomizer.tsx       # Live itinerary & service customizer modal
    └── GolfExtraLogo.tsx         # SVG Brand Logo component (Dark/Light variants)
```

---

## 4. Component Deep Dive

### 4.1 Root View Orchestrator (`src/App.tsx`)
- **Role**: Manages active view routing (`email`, `survey`, `analytics`), global state for trip itineraries, guest survey responses, and submission logs.
- **State Variables**:
  - `currentView`: Controls active screen (`'email' | 'survey' | 'analytics'`).
  - `itinerary`: Object holding guest name, title, booking ref, destination, and booked services list.
  - `submissions`: Array of `SubmittedFeedback` stored in `localStorage`.
  - `showCustomizerModal`: Boolean toggling the itinerary customizer modal.

### 4.2 Email Template View (`src/components/EmailTemplateView.tsx`)
- **Role**: Renders a realistic email client interface representing the post-trip invitation.
- **Key Specifications**:
  - **From Header**: `Golf Extra <anfrage@golf-extra.com>`
  - **Subject Line**: `Ihre Meinung liegt uns am Herzen – wir freuen uns auf Ihr Feedback`
  - **Personalized Salutation**: `Sehr geehrte(r) [Title] [Name],`
  - **Welcome Message**: Welcomes the guest back from their destination and expresses gratitude for choosing Golf Extra.
  - **Interactive Call to Action (CTA)**: Gold banner with dark green button (`Feedback-Umfrage jetzt starten`) navigating directly into the survey.
  - **Footer**: Clean minimalism displaying `golf.extra` and `www.golf-extra.com`.

### 4.3 Multi-Step Feedback Survey (`src/components/SurveyView.tsx`)
- **Role**: Guides guests through a personalized feedback questionnaire based on their booked itinerary.
- **Survey Steps**:
  1. **Overall Experience & Mobility Services**:
     - 1–10 rating scores for Overall Experience and Consultation/Product Selection.
     - Transportation rating blocks (Flights, Transfers / Chauffeur Service, Rental Cars).
     - Conditional feedback text fields triggered when any service score is rated **below 9** (e.g., *"Was können wir tun, um Ihre Transfer-/ Chauffeurleistungen künftig noch weiter zu verbessern?"*).
  2. **Accommodations & Hotel Ratings**:
     - Individual 1–10 ratings for each booked hotel (e.g., Anantara Villa Padierna Palace).
     - Conditional sub-category expansion (Room, Service, Catering, Cleanliness) if score < 9.
  3. **Golf Courses & Playing Experiences**:
     - Course-by-course 1–10 rating cards with tee times, hole counts, and highlight badges (e.g., Real Club Valderrama, Finca Cortesín, La Zagaleta).
     - Conditional comment field for ratings under 9.
  4. **Recommendation, Future Travel & Final Remarks**:
     - 1–10 NPS Recommendation Rating prompt (*"Wie wahrscheinlich ist es, dass Sie golf.extra Ihren Freunden, Bekannten oder anderen Golfbegeisterten weiterempfehlen würden?"*).
     - Next bucket-list golf destination input field.
     - Highlight moments input field.
     - General improvement suggestions box with exact placeholder text:
       `"z. B. persönliche Worte an Ihre Reiseberaterin oder Ihren Reiseberater, Wünsche für zukünftige Reiseangebote oder Hinweise dazu, was wir künftig verbessern können"`.
  5. **Completion Screen & Public Reviews**:
     - Submission confirmation message ("Vielen Dank!").
     - Personal message of thanks acknowledging the feedback.
     - **Conditional Public Review Invitation**: If recommendation score is **9 or 10**, displays the public review box featuring direct action cards for **Trustpilot** (5.0 ★★★★★ rating) and **Google Maps** (4.9 Stars). If the score is **8 or lower**, displays a discrete thank-you without public review prompts.
     - Navigation button ("Zurück zur E-Mail") to return to the invitation view.

### 4.4 Feedback Analytics Modal (`src/components/FeedbackAnalyticsModal.tsx`)
- **Role**: Provides internal administrators with a log of submitted guest feedback.
- **Features**: Calculates average NPS scores, category ratings, displays individual guest feedback cards, and allows exporting submission data to JSON or CSV format.

### 4.5 Itinerary Customizer (`src/components/EmailCustomizer.tsx`)
- **Role**: Admin editing drawer allowing real-time modification of trip parameters (guest names, title, reference, destination, dates, flight details, booked hotels, golf courses, and service toggles).

---

## 5. Data Models (`src/types.ts`)

### Key Interfaces
- `TripItinerary`: Contains guest metadata, travel dates, booking ref, flights, hotels, golf courses, and review URLs.
- `BookedServices`: Boolean flags indicating whether `flight`, `hotels`, `transfers`, `golfCourses`, or `rentalCar` were included in the guest's booking.
- `FullSurveyData`: Stores numeric 1–10 ratings, sub-category breakdowns, textual feedback, and recommendation preferences.
- `SubmittedFeedback`: Timestamped submission object bundling guest information and survey response payload.

---

## 6. Build and Deployment Instructions

### Development Environment
```bash
npm run dev
```
Starts the Vite dev server on `http://localhost:3000`.

### Type Verification & Linting
```bash
npm run lint
```
Runs the TypeScript compiler (`tsc --noEmit`) to verify strict type safety across all components.

### Production Build
```bash
npm run build
```
Generates production-ready static web assets inside the `dist/` directory.

---

## 7. Summary of Applied Brand Messaging Rules

1. **Email Sender**: `Golf Extra <anfrage@golf-extra.com>`
2. **Email Subject**: `Ihre Meinung liegt uns am Herzen – wir freuen uns auf Ihr Feedback`
3. **Primary Survey CTA**: `Feedback-Umfrage jetzt starten`
4. **Transfer Feedback Prompt**: `"Was können wir tun, um Ihre Transfer-/ Chauffeurleistungen künftig noch weiter zu verbessern?"`
5. **Final Remark Placeholder**: `"z. B. persönliche Worte an Ihre Reiseberaterin oder Ihren Reiseberater, Wünsche für zukünftige Reiseangebote oder Hinweise dazu, was wir künftig verbessern können"`
6. **Footer Branding**: Clean `golf.extra` title and `www.golf-extra.com` link.

