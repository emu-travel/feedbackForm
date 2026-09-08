import React, { useState, useEffect } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { TripItinerary, FullSurveyData, Language, SubmittedFeedback, HotelDetail } from '../types';
import { defaultFullSurveyData } from '../data/initialData';
import { GolfExtraLogo } from './GolfExtraLogo';
import {
  Plane,
  Building2,
  Car,
  Flag,
  ArrowRight,
  ArrowLeft,
  Send,
  CheckCircle2,
  Star,
  ExternalLink,
  MapPin
} from 'lucide-react';

interface SurveyViewProps {
  itinerary: TripItinerary;
  lang: Language;
  onSurveySubmitted: (feedback: SubmittedFeedback) => void;
  onBackToEmail: () => void;
}

const slideVariants = {
  enter: (direction: number) => ({
    x: direction > 0 ? 35 : -35,
    opacity: 0,
    scale: 0.98
  }),
  center: {
    x: 0,
    opacity: 1,
    scale: 1,
    transition: { duration: 0.28, ease: 'easeOut' }
  },
  exit: (direction: number) => ({
    x: direction < 0 ? 35 : -35,
    opacity: 0,
    scale: 0.98,
    transition: { duration: 0.22, ease: 'easeIn' }
  })
};

export const SurveyView: React.FC<SurveyViewProps> = ({
  itinerary,
  lang,
  onSurveySubmitted,
  onBackToEmail
}) => {
  // Screen sequence:
  // 1: Ihr erstes Feedback (Gesamterfahrung, Beratung + Flüge, Transfers, Mietwagen)
  // 2: Hotels & Unterkunft (1 overall rating per hotel; expands sub-questions if rating < 9)
  // 3: Golfplätze & Platzqualität
  // 4: Empfehlung & Abschluss
  // 5: Dankeseite (Thank You & Trustpilot/Google Maps review)
  const [screen, setScreen] = useState<number>(1);
  const [direction, setDirection] = useState<number>(1);
  const [surveyData, setSurveyData] = useState<FullSurveyData>(defaultFullSurveyData);
  const [, setIsCompleted] = useState<boolean>(false);

  // Derive hotel list cleanly (supporting multiple hotels or single hotel fallback)
  const hotelList: HotelDetail[] =
    itinerary.hotels && itinerary.hotels.length > 0
      ? itinerary.hotels
      : itinerary.hotel
      ? [itinerary.hotel]
      : [];

  // Synchronize initial services and ratings from itinerary
  useEffect(() => {
    setSurveyData((prev) => {
      const syncedServices = {
        flight: itinerary.flights.length > 0,
        hotels: hotelList.length > 0,
        transfers: !!itinerary.transfer && itinerary.transfer.length > 0,
        golfCourses: itinerary.golfCourses.length > 0,
        rentalCar: prev.services.rentalCar || false
      };

      const initialGolfRatings: Record<string, number> = { ...prev.golfCourseRatings };
      itinerary.golfCourses.forEach((c) => {
        if (initialGolfRatings[c.name] === undefined) {
          initialGolfRatings[c.name] = 10;
        }
      });

      const initialHotelRatings: Record<string, number> = { ...(prev.hotelRatings || {}) };
      hotelList.forEach((h) => {
        if (initialHotelRatings[h.name] === undefined) {
          initialHotelRatings[h.name] = 10;
        }
      });

      return {
        ...prev,
        services: syncedServices,
        golfCourseRatings: initialGolfRatings,
        hotelRatings: initialHotelRatings
      };
    });
  }, [itinerary]);

  const updateField = <K extends keyof FullSurveyData>(key: K, value: FullSurveyData[K]) => {
    setSurveyData((prev) => ({ ...prev, [key]: value }));
  };

  const updateGolfRating = (courseName: string, val: number) => {
    setSurveyData((prev) => ({
      ...prev,
      golfCourseRatings: { ...prev.golfCourseRatings, [courseName]: val }
    }));
  };

  const updateGolfCourseComment = (courseName: string, comment: string) => {
    setSurveyData((prev) => ({
      ...prev,
      golfCourseComments: {
        ...(prev.golfCourseComments || {}),
        [courseName]: comment
      }
    }));
  };

  const updateHotelRating = (hotelName: string, val: number) => {
    setSurveyData((prev) => ({
      ...prev,
      hotelRatings: { ...(prev.hotelRatings || {}), [hotelName]: val }
    }));
  };

  const updateHotelSubRating = (
    hotelName: string,
    category: 'room' | 'service' | 'catering' | 'cleanliness',
    val: number
  ) => {
    setSurveyData((prev) => ({
      ...prev,
      hotelSubRatings: {
        ...(prev.hotelSubRatings || {}),
        [hotelName]: {
          ...(prev.hotelSubRatings?.[hotelName] || {
            room: 8,
            service: 8,
            catering: 8,
            cleanliness: 8
          }),
          [category]: val
        }
      }
    }));
  };

  const updateHotelComment = (hotelName: string, comment: string) => {
    setSurveyData((prev) => ({
      ...prev,
      hotelComments: {
        ...(prev.hotelComments || {}),
        [hotelName]: comment
      }
    }));
  };

  // Dynamic screen navigation helper
  const hasMobilityServices =
    surveyData.services.flight ||
    surveyData.services.transfers ||
    surveyData.services.rentalCar;

  const getNextScreen = (current: number): number => {
    if (current === 1) {
      if (hasMobilityServices) return 2;
      if (hotelList.length > 0) return 3;
      if (itinerary.golfCourses.length > 0) return 4;
      return 5;
    }
    if (current === 2) {
      if (hotelList.length > 0) return 3;
      if (itinerary.golfCourses.length > 0) return 4;
      return 5;
    }
    if (current === 3) {
      if (itinerary.golfCourses.length > 0) return 4;
      return 5;
    }
    if (current === 4) return 5;
    if (current === 5) return 6;
    return 6;
  };

  const getPrevScreen = (current: number): number => {
    if (current === 6) return 5;
    if (current === 5) {
      if (itinerary.golfCourses.length > 0) return 4;
      if (hotelList.length > 0) return 3;
      if (hasMobilityServices) return 2;
      return 1;
    }
    if (current === 4) {
      if (hotelList.length > 0) return 3;
      if (hasMobilityServices) return 2;
      return 1;
    }
    if (current === 3) {
      if (hasMobilityServices) return 2;
      return 1;
    }
    if (current === 2) return 1;
    return 1;
  };

  const handleNext = () => {
    const next = getNextScreen(screen);
    setDirection(1);
    if (next === 6) {
      const newFeedback: SubmittedFeedback = {
        id: `FB-${Date.now().toString().slice(-6)}`,
        timestamp: new Date().toLocaleDateString('de-DE'),
        guestName: `${itinerary.guestTitle} ${itinerary.guestName}`,
        bookingRef: itinerary.bookingReference,
        surveyData,
        treePlantedConfirmed: false
      };
      setIsCompleted(true);
      onSurveySubmitted(newFeedback);
    }
    setScreen(next);
  };

  const handlePrev = () => {
    if (screen === 1) {
      onBackToEmail();
      return;
    }
    setDirection(-1);
    setScreen(getPrevScreen(screen));
  };

  // Sub-category rating scale renderer
  const renderSubRatingScale = (
    value: number,
    onChange: (val: number) => void
  ) => {
    const currentVal = value >= 1 && value <= 10 ? value : 8;
    const trackPercent = ((currentVal - 1) / 9) * 100;

    return (
      <div className="space-y-1.5 font-sans">
        <div className="flex items-center justify-between text-[11px] text-slate-500 font-medium px-0.5">
          <span>Unzureichend</span>
          <span className="text-[#B87A08] font-bold bg-amber-50 px-2.5 py-0.5 rounded-full border border-amber-200 text-[11px]">
            {currentVal} / 10
          </span>
          <span>Ausgezeichnet</span>
        </div>
        <input
          type="range"
          min={1}
          max={10}
          step={1}
          value={currentVal}
          onChange={(e) => onChange(parseInt(e.target.value, 10))}
          className="w-full h-2 bg-slate-200 rounded-lg appearance-none cursor-pointer accent-[#E59E0F] focus:outline-none"
          style={{
            background: `linear-gradient(to right, #E59E0F 0%, #E59E0F ${trackPercent}%, #e2e8f0 ${trackPercent}%, #e2e8f0 100%)`
          }}
        />
        <div className="grid grid-cols-10 gap-1 pt-0.5">
          {[1, 2, 3, 4, 5, 6, 7, 8, 9, 10].map((num) => (
            <button
              key={num}
              type="button"
              onClick={() => onChange(num)}
              className={`py-1 rounded-lg text-center font-bold text-[10px] transition-all cursor-pointer ${
                currentVal === num
                  ? 'bg-[#E59E0F] text-[#0f3822] shadow-2xs scale-105 font-extrabold ring-1 ring-amber-400'
                  : 'bg-white text-slate-600 border border-slate-200 hover:bg-slate-100'
              }`}
            >
              {num}
            </button>
          ))}
        </div>
      </div>
    );
  };

  // High precision 1–10 NPS rating scale rendering
  const renderConnectedRatingScale = (
    value: number,
    onChange: (val: number) => void,
    minLabel: string = 'Unzureichend',
    maxLabel: string = 'Ausgezeichnet',
    commentValue?: string,
    onCommentChange?: (comment: string) => void,
    commentPlaceholder: string = 'Bitte beschreiben Sie kurz, was wir in diesem Bereich verbessern können...',
    commentPrompt: string = 'Was können wir in diesem Bereich verbessern? (optional)'
  ) => {
    const currentVal = value >= 1 && value <= 10 ? value : 10;
    const trackPercent = ((currentVal - 1) / 9) * 100;

    return (
      <div className="py-2 space-y-2.5 font-sans">
        <div className="flex items-center justify-between text-[11px] font-sans px-1 text-slate-600 font-medium">
          <span className="flex items-center space-x-1.5 text-slate-600 font-semibold">
            <span className="w-1.5 h-1.5 rounded-full bg-slate-400 inline-block" />
            <span>{minLabel}</span>
          </span>

          <span className="text-[#B87A08] font-bold text-xs bg-amber-50 px-3 py-1 rounded-full border border-amber-200 shadow-2xs">
            {currentVal} / 10
          </span>

          <span className="flex items-center space-x-1.5 text-slate-800 font-semibold">
            <span>{maxLabel}</span>
            <span className="w-1.5 h-1.5 rounded-full bg-[#E59E0F] inline-block" />
          </span>
        </div>

        <div className="space-y-2 bg-slate-50/90 p-3.5 rounded-2xl border border-slate-200 shadow-2xs">
          <div className="relative flex items-center w-full px-1 py-1">
            <input
              type="range"
              min={1}
              max={10}
              step={1}
              value={currentVal}
              onChange={(e) => onChange(parseInt(e.target.value, 10))}
              className="w-full h-2.5 bg-slate-200 rounded-lg appearance-none cursor-pointer accent-[#E59E0F] focus:outline-none z-10"
              style={{
                background: `linear-gradient(to right, #E59E0F 0%, #E59E0F ${trackPercent}%, #e2e8f0 ${trackPercent}%, #e2e8f0 100%)`
              }}
            />
          </div>

          <div className="grid grid-cols-10 gap-1 sm:gap-1.5 pt-1">
            {[1, 2, 3, 4, 5, 6, 7, 8, 9, 10].map((num) => {
              const isSelected = currentVal === num;
              return (
                <button
                  key={num}
                  type="button"
                  onClick={() => onChange(num)}
                  className={`py-1.5 rounded-lg text-center font-bold text-[11px] sm:text-xs transition-all duration-150 cursor-pointer ${
                    isSelected
                      ? 'bg-[#E59E0F] text-[#0f3822] shadow-xs scale-105 font-extrabold ring-2 ring-amber-400/50'
                      : 'bg-white text-slate-600 border border-slate-200 hover:bg-slate-100 hover:text-slate-900'
                  }`}
                >
                  {num}
                </button>
              );
            })}
          </div>
        </div>

        {/* Dynamic comment box for standalone questions when rating <= 8 */}
        <AnimatePresence>
          {currentVal <= 8 && onCommentChange && (
            <motion.div
              initial={{ height: 0, opacity: 0, marginTop: 0 }}
              animate={{ height: 'auto', opacity: 1, marginTop: 10 }}
              exit={{ height: 0, opacity: 0, marginTop: 0 }}
              transition={{ duration: 0.22, ease: 'easeOut' }}
              className="overflow-hidden"
            >
              <div className="bg-amber-50/80 border border-amber-200 rounded-2xl p-3.5 space-y-1.5 text-xs shadow-2xs">
                <div className="flex items-center space-x-1.5 text-[#B87A08] font-semibold">
                  <span className="w-1.5 h-1.5 rounded-full bg-[#E59E0F]" />
                  <span>{commentPrompt}</span>
                </div>
                <textarea
                  value={commentValue || ''}
                  onChange={(e) => onCommentChange(e.target.value)}
                  placeholder={commentPlaceholder}
                  rows={2}
                  className="w-full bg-white border border-slate-200 rounded-xl p-2.5 text-slate-900 text-xs focus:border-[#E59E0F] focus:outline-none transition-all placeholder:text-slate-400"
                />
              </div>
            </motion.div>
          )}
        </AnimatePresence>
      </div>
    );
  };

  return (
    <div className="w-full max-w-3xl mx-auto bg-white border border-slate-200 rounded-3xl p-6 sm:p-10 shadow-lg relative overflow-hidden font-sans text-slate-800">
      {/* Top Header */}
      <div className="flex items-center justify-between border-b border-slate-200 pb-4 mb-6">
        <div className="flex items-center space-x-3">
          <GolfExtraLogo variant="light-bg" className="scale-90" />
        </div>
        {screen <= 5 && (
          <div className="text-xs font-semibold text-slate-500 bg-slate-100 px-3 py-1 rounded-full border border-slate-200">
            Schritt {screen} von 5
          </div>
        )}
      </div>

      {/* Progress Bar (Screens 1 through 5) */}
      {screen >= 1 && screen <= 5 && (
        <div className="mb-6 space-y-1.5 font-sans">
          <div className="flex justify-between items-center text-[10px] uppercase tracking-widest text-slate-500 font-semibold">
            <span className="flex items-center space-x-1.5">
              <span className="w-1.5 h-1.5 rounded-full bg-[#E59E0F]" />
              <span>Fortschritt</span>
            </span>
            <span>{Math.round((screen / 5) * 100)}%</span>
          </div>
          <div className="w-full bg-slate-100 h-2 rounded-full overflow-hidden p-0.5 border border-slate-200">
            <motion.div
              className="bg-[#E59E0F] h-full rounded-full shadow-xs"
              initial={{ width: `${((screen - 1) / 5) * 100}%` }}
              animate={{ width: `${(screen / 5) * 100}%` }}
              transition={{ duration: 0.35, ease: 'easeInOut' }}
            />
          </div>
        </div>
      )}

      {/* Screen Container with Framer Motion AnimatePresence */}
      <AnimatePresence mode="wait" custom={direction}>
        <motion.div
          key={screen}
          custom={direction}
          variants={slideVariants}
          initial="enter"
          animate="center"
          exit="exit"
          className="w-full"
        >
          {/* SCREEN 1: OVERALL IMPRESSION */}
          {screen === 1 && (
            <div className="space-y-8 py-2">
              <div className="text-center space-y-1">
                <h2 className="text-2xl text-slate-900 font-bold">
                  Gesamteindruck Ihrer Golfreise
                </h2>
              </div>

              <div className="space-y-6">
                {/* Question 1: Overall Experience */}
                <div className="bg-slate-50 p-5 rounded-2xl border border-slate-200 space-y-3 shadow-xs">
                  <label className="text-slate-900 text-sm sm:text-base block font-semibold">
                    1. Wie bewerten Sie Ihre Golfreise insgesamt?
                  </label>
                  {renderConnectedRatingScale(
                    surveyData.overallExperience,
                    (val) => updateField('overallExperience', val),
                    'Unzureichend',
                    'Ausgezeichnet',
                    surveyData.overallExperienceComment,
                    (val) => updateField('overallExperienceComment', val),
                    'Was können wir tun, um Ihr Reiseerlebnis künftig noch weiter zu verbessern?',
                    'Was können wir tun, um Ihr Reiseerlebnis künftig noch weiter zu verbessern? (optional)'
                  )}
                </div>

                {/* Question 2: Consultation & Product Selection */}
                <div className="bg-slate-50 p-5 rounded-2xl border border-slate-200 space-y-3 shadow-xs">
                  <label className="text-slate-900 text-sm sm:text-base block font-semibold">
                    2. Wie zufrieden waren Sie mit unserer Beratung und Produktauswahl?
                  </label>
                  {renderConnectedRatingScale(
                    surveyData.consultationProductSelection,
                    (val) => updateField('consultationProductSelection', val),
                    'Sehr unzufrieden',
                    'Sehr zufrieden',
                    surveyData.consultationComment,
                    (val) => updateField('consultationComment', val),
                    'Was können wir tun, um unsere Beratung und Produktauswahl künftig noch weiter zu verbessern?',
                    'Was können wir tun, um unsere Beratung und Produktauswahl künftig noch weiter zu verbessern? (optional)'
                  )}
                </div>
              </div>
            </div>
          )}

          {/* SCREEN 2: TRANSFER AND MOBILITY SERVICES */}
          {screen === 2 && (
            <div className="space-y-8 py-2">
              <div className="text-center space-y-1">
                <h2 className="text-2xl text-slate-900 font-bold">
                  Transfer- und Mobilitätsleistungen
                </h2>
              </div>

              <div className="space-y-6">
                {/* Transportation - Flight (if booked) */}
                {surveyData.services.flight && (
                  <div className="bg-slate-50 p-5 rounded-2xl border border-slate-200 space-y-3 shadow-xs">
                    <div className="flex items-center space-x-2 text-slate-900 font-semibold text-sm sm:text-base border-b border-slate-200/80 pb-2.5">
                      <Plane className="w-4 h-4 text-[#B87A08]" />
                      <span>Wie zufrieden waren Sie mit den gebuchten Flugleistungen?</span>
                      {itinerary.flights.length > 0 && (
                        <span className="text-xs text-slate-500 font-mono ml-auto">
                          {itinerary.flights[0].airline}
                        </span>
                      )}
                    </div>
                    {renderConnectedRatingScale(
                      surveyData.flightRating,
                      (val) => updateField('flightRating', val),
                      'Sehr unzufrieden',
                      'Sehr zufrieden',
                      surveyData.flightComment,
                      (val) => updateField('flightComment', val),
                      'Was können wir tun, um die für Sie gebuchten Flugleistungen künftig noch besser auf Ihre Wünsche abzustimmen?',
                      'Was können wir tun, um die für Sie gebuchten Flugleistungen künftig noch besser auf Ihre Wünsche abzustimmen? (optional)'
                    )}
                  </div>
                )}

                {/* Transportation - Transfers (if booked) */}
                {surveyData.services.transfers && (
                  <div className="bg-slate-50 p-5 rounded-2xl border border-slate-200 space-y-3 shadow-xs">
                    <div className="flex items-center space-x-2 text-slate-900 font-semibold text-sm sm:text-base border-b border-slate-200/80 pb-2.5">
                      <Car className="w-4 h-4 text-[#B87A08]" />
                      <span>Wie zufrieden waren Sie mit dem Transfer-/ Chauffeurservice?</span>
                    </div>
                    {renderConnectedRatingScale(
                      surveyData.transfersRating,
                      (val) => updateField('transfersRating', val),
                      'Sehr unzufrieden',
                      'Sehr zufrieden',
                      surveyData.transfersComment,
                      (val) => updateField('transfersComment', val),
                      'Was können wir tun, um Ihre Transfer-/ Chauffeurleistungen künftig noch weiter zu verbessern?',
                      'Was können wir tun, um Ihre Transfer-/ Chauffeurleistungen künftig noch weiter zu verbessern? (optional)'
                    )}
                  </div>
                )}

                {/* Transportation - Rental Car (if booked) */}
                {surveyData.services.rentalCar && (
                  <div className="bg-slate-50 p-5 rounded-2xl border border-slate-200 space-y-3 shadow-xs">
                    <div className="flex items-center space-x-2 text-slate-900 font-semibold text-sm sm:text-base border-b border-slate-200/80 pb-2.5">
                      <Car className="w-4 h-4 text-[#B87A08]" />
                      <span>Mietwagen</span>
                    </div>
                    {renderConnectedRatingScale(
                      surveyData.rentalCarRating,
                      (val) => updateField('rentalCarRating', val),
                      'Sehr unzufrieden',
                      'Sehr zufrieden',
                      surveyData.rentalCarComment,
                      (val) => updateField('rentalCarComment', val),
                      'Bitte beschreiben Sie kurz Ihre Erfahrungen bezüglich Fahrzeugkategorie oder Abwicklung...',
                      'Was können wir beim Mietwagen verbessern? (optional)'
                    )}
                  </div>
                )}
              </div>
            </div>
          )}

          {/* SCREEN 3: HOTELS */}
          {screen === 3 && (
            <div className="space-y-6 py-2">
              <div className="text-center space-y-1">
                <h2 className="text-2xl text-slate-900 font-bold">
                  {hotelList.length > 1 ? 'Hotels und Unterkunft' : 'Hotel und Unterkunft'}
                </h2>
              </div>

              <div className="space-y-5">
                {hotelList.map((hotel, idx) => {
                  const currentVal = surveyData.hotelRatings?.[hotel.name] ?? 10;
                  const isBelowNine = currentVal < 9;

                  return (
                    <div key={idx} className="bg-slate-50 p-5 rounded-2xl border border-slate-200 space-y-3 shadow-xs">
                      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-1 border-b border-slate-200/80 pb-3">
                        <div className="flex items-center space-x-2">
                          <Building2 className="w-4 h-4 text-[#B87A08]" />
                          <h3 className="text-sm sm:text-base font-bold text-slate-900">{hotel.name}</h3>
                        </div>
                        <div className="text-[11px] text-slate-500 font-mono flex items-center space-x-2">
                          <span>{hotel.location}</span>
                          <span>•</span>
                          <span>{hotel.nights} Nächte</span>
                        </div>
                      </div>

                      {/* Overall Hotel Rating */}
                      {renderConnectedRatingScale(
                        currentVal,
                        (val) => updateHotelRating(hotel.name, val),
                        'Unzureichend',
                        'Ausgezeichnet'
                      )}

                      {/* Conditional Expansion when Overall Rating is below 9 (< 9) */}
                      <AnimatePresence>
                        {isBelowNine && (
                          <motion.div
                            initial={{ height: 0, opacity: 0, marginTop: 0 }}
                            animate={{ height: 'auto', opacity: 1, marginTop: 16 }}
                            exit={{ height: 0, opacity: 0, marginTop: 0 }}
                            transition={{ duration: 0.25, ease: 'easeOut' }}
                            className="overflow-hidden"
                          >
                            <div className="bg-amber-50/80 border border-amber-200 rounded-2xl p-4 space-y-4 shadow-2xs">
                              <div className="text-xs font-bold text-[#B87A08] flex items-center space-x-1.5 pb-2 border-b border-amber-200/70">
                                <span className="w-2 h-2 rounded-full bg-[#E59E0F]" />
                                <span>Detailbewertung für {hotel.name} (optional):</span>
                              </div>

                              <div className="space-y-3.5">
                                {/* Room */}
                                <div className="bg-white p-3.5 rounded-xl border border-slate-200/80 space-y-2">
                                  <label className="text-slate-800 text-xs font-bold block">
                                    Zimmer und Ausstattung
                                  </label>
                                  {renderSubRatingScale(
                                    surveyData.hotelSubRatings?.[hotel.name]?.room ?? 8,
                                    (v) => updateHotelSubRating(hotel.name, 'room', v)
                                  )}
                                </div>

                                {/* Service */}
                                <div className="bg-white p-3.5 rounded-xl border border-slate-200/80 space-y-2">
                                  <label className="text-slate-800 text-xs font-bold block">
                                    Hotelservice und Betreuung vor Ort
                                  </label>
                                  {renderSubRatingScale(
                                    surveyData.hotelSubRatings?.[hotel.name]?.service ?? 8,
                                    (v) => updateHotelSubRating(hotel.name, 'service', v)
                                  )}
                                </div>

                                {/* Catering */}
                                <div className="bg-white p-3.5 rounded-xl border border-slate-200/80 space-y-2">
                                  <label className="text-slate-800 text-xs font-bold block">
                                    Gastronomie
                                  </label>
                                  {renderSubRatingScale(
                                    surveyData.hotelSubRatings?.[hotel.name]?.catering ?? 8,
                                    (v) => updateHotelSubRating(hotel.name, 'catering', v)
                                  )}
                                </div>

                                {/* Cleanliness */}
                                <div className="bg-white p-3.5 rounded-xl border border-slate-200/80 space-y-2">
                                  <label className="text-slate-800 text-xs font-bold block">
                                    Sauberkeit
                                  </label>
                                  {renderSubRatingScale(
                                    surveyData.hotelSubRatings?.[hotel.name]?.cleanliness ?? 8,
                                    (v) => updateHotelSubRating(hotel.name, 'cleanliness', v)
                                  )}
                                </div>
                              </div>

                              {/* Hotel comment box */}
                              <div className="space-y-1.5 pt-1">
                                <label className="text-slate-900 text-xs font-bold block">
                                  Welche Aspekte Ihres Aufenthalts im {hotel.name} könnten aus Ihrer Sicht verbessert werden? (optional)
                                </label>
                                <textarea
                                  value={surveyData.hotelComments?.[hotel.name] || ''}
                                  onChange={(e) => updateHotelComment(hotel.name, e.target.value)}
                                  placeholder="z.B. Zimmerausstattung, Service, Verpflegung, Sauberkeit, Spa, …"
                                  rows={2}
                                  className="w-full bg-white border border-slate-200 rounded-xl p-2.5 text-slate-900 text-xs focus:border-[#E59E0F] focus:outline-none placeholder:text-slate-400"
                                />
                              </div>
                            </div>
                          </motion.div>
                        )}
                      </AnimatePresence>
                    </div>
                  );
                })}

                <div className="bg-slate-50 p-4 rounded-2xl border border-slate-200 pt-3">
                  <label className="text-slate-700 text-xs font-semibold block mb-1">
                    {hotelList.length > 1
                      ? 'Weitere Anmerkungen oder Hinweise zu Ihren Hotels (optional):'
                      : 'Weitere Anmerkungen oder Hinweise zu Ihrem Hotel (optional):'}
                  </label>
                  <textarea
                    value={surveyData.hotelComment}
                    onChange={(e) => updateField('hotelComment', e.target.value)}
                    placeholder=""
                    rows={2}
                    className="w-full bg-white border border-slate-200 rounded-xl p-3 text-xs text-slate-900 focus:border-[#E59E0F] focus:outline-none placeholder:text-slate-400"
                  />
                </div>
              </div>
            </div>
          )}

          {/* SCREEN 4: GOLF COURSES */}
          {screen === 4 && (
            <div className="space-y-6 py-2">
              <div className="text-center space-y-1">
                <h2 className="text-2xl text-slate-900 font-bold">
                  Golfplätze
                </h2>
              </div>

              <div className="space-y-4">
                {itinerary.golfCourses.map((course, idx) => {
                  const currentVal = surveyData.golfCourseRatings[course.name] || 10;
                  return (
                    <div key={idx} className="bg-slate-50 p-5 rounded-2xl border border-slate-200 space-y-3 shadow-xs">
                      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-1 border-b border-slate-200/80 pb-3">
                        <div className="flex items-center space-x-2">
                          <Flag className="w-4 h-4 text-[#B87A08]" />
                          <h3 className="text-sm sm:text-base font-bold text-slate-900">{course.name}</h3>
                        </div>
                        <div className="text-[11px] text-slate-500 font-mono flex items-center space-x-2">
                          <span>{course.holes} Löcher</span>
                          {course.highlight && (
                            <>
                              <span>•</span>
                              <span>{course.highlight}</span>
                            </>
                          )}
                        </div>
                      </div>

                      {renderConnectedRatingScale(
                        currentVal,
                        (val) => updateGolfRating(course.name, val),
                        'Unzureichend',
                        'Ausgezeichnet',
                        surveyData.golfCourseComments?.[course.name] || '',
                        (val) => updateGolfCourseComment(course.name, val),
                        'z.B. Platzzustand, Service, Clubhaus, …',
                        `Welche Aspekte des ${course.name} könnten aus Ihrer Sicht verbessert werden? (optional)`
                      )}
                    </div>
                  );
                })}

                <div className="bg-slate-50 p-4 rounded-2xl border border-slate-200 pt-3">
                  <label className="text-slate-700 text-xs font-semibold block mb-1">
                    {itinerary.golfCourses.length > 1
                      ? 'Weitere Anmerkungen oder Hinweise zu Ihren Golfplätzen (optional):'
                      : 'Weitere Anmerkungen oder Hinweise zu Ihrem Golfplatz (optional):'}
                  </label>
                  <textarea
                    value={surveyData.golfCourseComment}
                    onChange={(e) => updateField('golfCourseComment', e.target.value)}
                    placeholder=""
                    rows={2}
                    className="w-full bg-white border border-slate-200 rounded-xl p-3 text-xs text-slate-900 focus:border-[#E59E0F] focus:outline-none placeholder:text-slate-400"
                  />
                </div>
              </div>
            </div>
          )}

          {/* SCREEN 5: RECOMMENDATION & FINAL REMARKS */}
          {screen === 5 && (
            <div className="space-y-6 py-2">
              <div className="text-center space-y-1">
                <h2 className="text-2xl text-slate-900 font-bold">
                  Fazit
                </h2>
              </div>

              <div className="space-y-5 font-sans text-xs">
                {/* 1. Recommendation Question (1-10 NPS) */}
                <div className="bg-slate-50 p-5 rounded-2xl border border-slate-200 space-y-3 shadow-xs font-sans">
                  <label className="text-slate-900 text-sm block font-semibold">
                    Wie wahrscheinlich ist es, dass Sie golf.extra Ihren Freunden, Bekannten oder anderen Golfbegeisterten weiterempfehlen würden?
                  </label>
                  {renderConnectedRatingScale(
                    typeof surveyData.recommendation === 'number' ? surveyData.recommendation : 10,
                    (val) => updateField('recommendation', val),
                    'Sehr unwahrscheinlich',
                    'Sehr wahrscheinlich'
                  )}
                </div>

                {/* 1. Destination / Golfplatz / Reiseerlebnis Wunschliste */}
                <div className="bg-slate-50 p-4 rounded-2xl border border-slate-200 space-y-1.5 shadow-xs">
                  <label className="text-slate-900 font-semibold block text-xs">
                    Welche Destination, welcher Golfplatz oder welches besondere Reiseerlebnis steht als Nächstes auf Ihrer Wunschliste? (optional)
                  </label>
                  <textarea
                    value={surveyData.nextBucketListDestination || ''}
                    onChange={(e) => updateField('nextBucketListDestination', e.target.value)}
                    placeholder="z.B. Pebble Beach, St. Andrews, Mauritius, Augusta..."
                    rows={2}
                    className="w-full bg-white border border-slate-200 rounded-xl p-3 text-slate-900 text-xs focus:border-[#E59E0F] focus:outline-none placeholder:text-slate-400"
                  />
                </div>

                {/* 2. Anregungen & Verbesserungsvorschläge */}
                <div className="bg-slate-50 p-4 rounded-2xl border border-slate-200 space-y-1.5 shadow-xs">
                  <label className="text-slate-900 font-semibold block text-xs">
                    Gibt es abschließend noch Anregungen, Verbesserungsvorschläge oder persönliche Hinweise, die Sie uns mitgeben möchten? (optional)
                  </label>
                  <textarea
                    value={surveyData.improvementSuggestions}
                    onChange={(e) => updateField('improvementSuggestions', e.target.value)}
                    placeholder="z. B. persönliche Worte an Ihre Reiseberaterin oder Ihren Reiseberater, Wünsche für zukünftige Reiseangebote oder Hinweise dazu, was wir künftig verbessern können"
                    rows={2.5}
                    className="w-full bg-white border border-slate-200 rounded-xl p-3 text-slate-900 text-xs focus:border-[#E59E0F] focus:outline-none placeholder:text-slate-400"
                  />
                </div>
              </div>
            </div>
          )}

          {/* SCREEN 6: THANK YOU & PUBLIC REVIEWS */}
          {screen === 6 && (
            <div className="text-center space-y-6 py-6">
              <motion.div
                initial={{ scale: 0.5, opacity: 0 }}
                animate={{ scale: 1, opacity: 1 }}
                transition={{ type: 'spring', stiffness: 200, damping: 15 }}
                className="w-16 h-16 rounded-full bg-[#E59E0F] text-[#0f3822] flex items-center justify-center mx-auto shadow-md"
              >
                <CheckCircle2 className="w-10 h-10" />
              </motion.div>

              <div className="space-y-4">
                <h1 className="text-3xl sm:text-4xl text-slate-900 font-bold">
                  Vielen Dank!
                </h1>
                <div className="text-slate-600 text-sm sm:text-base max-w-xl mx-auto font-sans leading-relaxed space-y-3">
                  <p className="font-medium text-slate-800">
                    Vielen Dank, dass Sie sich die Zeit genommen haben, uns Ihr Feedback mitzuteilen.
                  </p>
                  {(typeof surveyData.recommendation === 'number' ? surveyData.recommendation >= 9 : surveyData.recommendation === 'Ja') ? (
                    <p>
                      Wenn Sie mit Ihrer Reise und unserem Service rundum zufrieden waren, würden wir uns sehr freuen, wenn Sie Ihre Erfahrungen auch auf Trustpilot und Google teilen und uns mit fünf Sternen bewerten. Ihre positive Bewertung bedeutet uns sehr viel und unterstützt zugleich andere Golferinnen und Golfer bei ihrer Reiseentscheidung.
                    </p>
                  ) : (
                    <p>
                      Wir haben Ihre Rückmeldung dankend erhalten und nutzen diese, um unsere Beratung und unseren Service fortlaufend weiterzuentwickeln.
                    </p>
                  )}
                  <p className="font-semibold text-slate-900 pt-1">
                    Vielen Dank und hoffentlich bis ganz bald auf einer unserer nächsten Reisen.
                  </p>
                </div>
              </div>

              {/* Trustpilot & Google Maps Public Review Request Box (Only shown if recommendation score is 9 or 10) */}
              {(typeof surveyData.recommendation === 'number' ? surveyData.recommendation >= 9 : surveyData.recommendation === 'Ja') && (
                <div className="bg-slate-50 border border-slate-200 rounded-3xl p-5 sm:p-6 text-left space-y-4 max-w-lg mx-auto shadow-sm relative overflow-hidden">
                  <div className="flex items-center justify-between border-b border-slate-200 pb-3">
                    <div className="text-slate-900 font-bold text-base sm:text-lg">
                      <span>Erfahrung öffentlich teilen</span>
                    </div>
                    <span className="text-[10px] font-sans font-bold bg-amber-100 text-amber-900 px-2.5 py-0.5 rounded-full border border-amber-200">
                      5.0 ★★★★★
                    </span>
                  </div>

                  {/* Review Platform Cards */}
                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 pt-1">
                    {/* Trustpilot Card */}
                    <a
                      href={itinerary.trustpilotUrl || 'https://www.trustpilot.com/evaluate/emu-travel.com'}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="group bg-white hover:bg-amber-50/50 border border-amber-200 hover:border-amber-400 p-4 rounded-2xl transition-all duration-200 flex flex-col justify-between space-y-3 cursor-pointer shadow-xs"
                    >
                      <div className="flex items-center justify-between">
                        <div className="flex items-center space-x-2">
                          <div className="w-7 h-7 rounded-lg bg-[#00b67a] text-white font-bold text-xs flex items-center justify-center shadow-xs">
                            ★
                          </div>
                          <div>
                            <div className="text-slate-900 font-bold font-sans text-xs group-hover:text-amber-900 transition-colors">Trustpilot</div>
                            <div className="text-[10px] text-slate-500 font-mono">
                              {itinerary.trustpilotUrl ? itinerary.trustpilotUrl.replace('https://www.trustpilot.com/evaluate/', '') : 'emu-travel.com'}
                            </div>
                          </div>
                        </div>
                        <ExternalLink className="w-4 h-4 text-slate-400 group-hover:translate-x-0.5 group-hover:-translate-y-0.5 transition-transform" />
                      </div>

                      <div className="flex items-center space-x-1">
                        {[1, 2, 3, 4, 5].map((i) => (
                          <div key={i} className="w-4 h-4 bg-[#00b67a] rounded-xs flex items-center justify-center text-white text-[10px] font-bold">
                            ★
                          </div>
                        ))}
                        <span className="text-[10px] text-slate-700 font-sans font-medium ml-1">4.9 / 5</span>
                      </div>

                      <div className="bg-[#00b67a] text-white group-hover:bg-[#00a26d] font-sans font-bold text-xs py-2 px-3 rounded-xl text-center transition-colors">
                        Auf Trustpilot bewerten
                      </div>
                    </a>

                    {/* Google Maps Card */}
                    <a
                      href={itinerary.googleMapsUrl || 'https://maps.google.com/?q=golf.extra+GmbH+Heilbronn'}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="group bg-white hover:bg-blue-50/50 border border-blue-200 hover:border-blue-400 p-4 rounded-2xl transition-all duration-200 flex flex-col justify-between space-y-3 cursor-pointer shadow-xs"
                    >
                      <div className="flex items-center justify-between">
                        <div className="flex items-center space-x-2">
                          <div className="w-7 h-7 rounded-lg bg-blue-600 text-white font-bold text-xs flex items-center justify-center shadow-xs">
                            <MapPin className="w-4 h-4 text-white" />
                          </div>
                          <div>
                            <div className="text-slate-900 font-bold font-sans text-xs group-hover:text-blue-800 transition-colors">Google</div>
                            <div className="text-[10px] text-blue-700 font-mono">Google Reviews</div>
                          </div>
                        </div>
                        <ExternalLink className="w-4 h-4 text-blue-600 group-hover:translate-x-0.5 group-hover:-translate-y-0.5 transition-transform" />
                      </div>

                      <div className="flex items-center space-x-1">
                        {[1, 2, 3, 4, 5].map((i) => (
                          <Star key={i} className="w-3.5 h-3.5 fill-amber-400 text-amber-400" />
                        ))}
                        <span className="text-[10px] text-blue-800 font-sans font-medium ml-1">4.9 Stars</span>
                      </div>

                      <div className="bg-blue-600 text-white group-hover:bg-blue-700 font-sans font-bold text-xs py-2 px-3 rounded-xl text-center transition-colors">
                        Auf Google bewerten
                      </div>
                    </a>
                  </div>
                </div>
              )}

              {/* Simple Navigation Button */}
              <div className="pt-2">
                <button
                  onClick={onBackToEmail}
                  className="bg-[#E59E0F] hover:bg-[#D99313] text-[#0f3822] text-xs px-6 py-2.5 rounded-xl font-sans font-bold cursor-pointer transition-colors shadow-sm"
                >
                  Zurück zur E-Mail
                </button>
              </div>
            </div>
          )}
        </motion.div>
      </AnimatePresence>

      {/* BOTTOM NAVIGATION (For screens 1 through 5) */}
      {screen >= 1 && screen <= 5 && (
        <div className="flex items-center justify-between border-t border-slate-200 pt-5 mt-6 font-sans">
          <motion.button
            whileHover={{ scale: 1.02 }}
            whileTap={{ scale: 0.98 }}
            type="button"
            onClick={handlePrev}
            className="flex items-center space-x-1.5 text-slate-600 hover:text-slate-900 text-xs font-semibold px-4 py-2 rounded-xl transition-colors cursor-pointer"
          >
            <ArrowLeft className="w-4 h-4" />
            <span>{screen === 1 ? 'Zurück zur E-Mail' : 'Zurück'}</span>
          </motion.button>

          <motion.button
            whileHover={{ scale: 1.02 }}
            whileTap={{ scale: 0.98 }}
            type="button"
            onClick={handleNext}
            className="flex items-center space-x-2 bg-[#E59E0F] hover:bg-[#D99313] text-[#0f3822] font-bold text-xs px-6 py-2.5 rounded-xl transition-all shadow-md cursor-pointer"
          >
            <span>
              {screen === 5 ? 'Feedback Jetzt Absenden' : 'Weiter'}
            </span>
            {screen === 5 ? <Send className="w-4 h-4" /> : <ArrowRight className="w-4 h-4" />}
          </motion.button>
        </div>
      )}
    </div>
  );
};
