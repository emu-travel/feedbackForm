import React from 'react';
import { motion } from 'motion/react';
import { TripItinerary, CeoVideoConfig, Language } from '../types';
import { GolfExtraLogo } from './GolfExtraLogo';
import { ArrowRight } from 'lucide-react';

interface EmailTemplateViewProps {
  itinerary: TripItinerary;
  ceoConfig: CeoVideoConfig;
  lang: Language;
  onStartSurvey: () => void;
  onOpenCustomizer?: () => void;
}

export const EmailTemplateView: React.FC<EmailTemplateViewProps> = ({
  itinerary,
  onStartSurvey,
}) => {
  return (
    <div className="w-full flex flex-col items-center">
      {/* Main Email Frame Container */}
      <div className="max-w-3xl w-full bg-white border border-slate-200 rounded-3xl shadow-xl overflow-hidden">
        {/* Email Client Top Bar Header */}
        <div className="bg-slate-50 px-5 py-3 border-b border-slate-200 text-xs font-sans text-slate-600 space-y-1.5">
          <div className="flex items-center justify-between">
            <div className="flex items-center space-x-2">
              <div className="w-2.5 h-2.5 rounded-full bg-rose-400" />
              <div className="w-2.5 h-2.5 rounded-full bg-amber-400" />
              <div className="w-2.5 h-2.5 rounded-full bg-[#E59E0F]" />
              <span className="text-[11px] font-mono text-slate-500 ml-2">Inbox • Post-Trip Concierge</span>
            </div>
            <span className="text-[10px] text-slate-400 font-mono">Today, 09:15 AM</span>
          </div>

          <div className="pt-2 space-y-1 text-[11px] border-t border-slate-200">
            <div className="flex items-center justify-between">
              <span className="text-slate-600 font-sans"><strong>Von:</strong> Golf Extra &lt;anfrage@golf-extra.com&gt;</span>
              <span className="bg-[#E59E0F]/15 text-[#B87A08] text-[10px] px-2 py-0.5 rounded-full border border-[#E59E0F]/30 font-bold uppercase">PGA Certified</span>
            </div>
            <div>
              <span className="text-slate-600 font-sans"><strong>An:</strong> {itinerary.guestTitle} {itinerary.guestName} &lt;{itinerary.guestName.toLowerCase().replace(/\s+/g, '.')}@private-guest.com&gt;</span>
            </div>
            <div className="text-slate-900 font-medium text-xs pt-0.5 flex items-center justify-between">
              <span><strong>Betreff:</strong> Ihre Meinung liegt uns am Herzen – wir freuen uns auf Ihr Feedback</span>
              <span className="text-[10px] font-mono text-slate-500">Ref: {itinerary.bookingReference}</span>
            </div>
          </div>
        </div>

        {/* Email Content Body */}
        <div className="p-6 sm:p-8 space-y-7 bg-white text-slate-800 font-sans">
          {/* Header Banner */}
          <div className="text-center space-y-3 pb-4 border-b border-slate-100">
            <div className="inline-flex items-center space-x-2 bg-slate-50 px-4 py-2 rounded-2xl border border-slate-200 shadow-xs">
              <GolfExtraLogo variant="light-bg" className="scale-90" />
            </div>

            <h1 className="text-2xl sm:text-3xl font-serif text-slate-900 font-bold tracking-tight">
              Willkommen zurück, {itinerary.guestTitle ? `${itinerary.guestTitle} ` : ''}{itinerary.guestName}
            </h1>

            <p className="text-slate-600 text-xs sm:text-sm font-normal">
              {itinerary.tripName} • {itinerary.travelDates}
            </p>
          </div>

          {/* Greeting Letter with Exact German Starting Message Requested */}
          <div className="bg-slate-50 p-6 rounded-2xl border border-slate-200 leading-relaxed text-xs sm:text-sm text-slate-700 space-y-4 font-normal">
            <p className="font-semibold text-slate-900 text-sm sm:text-base">
              Sehr geehrte(r) {itinerary.guestTitle ? `${itinerary.guestTitle} ` : ''}{itinerary.guestName},
            </p>
            <p>
              herzlich willkommen zurück aus {itinerary.destination}. Wir hoffen sehr, dass Sie eine rundum schöne Reise verbringen konnten und mit vielen besonderen Eindrücken nach Hause zurückgekehrt sind.
            </p>
            <p>
              Es war uns eine große Freude, Ihre Reise begleiten und für Sie gestalten zu dürfen. Für das Vertrauen, das Sie unserem Team entgegengebracht haben, möchten wir uns nochmals ganz herzlich bedanken.
            </p>
            <p>
              Ihre persönliche Rückmeldung ist für uns von besonderer Bedeutung. Sie hilft uns dabei, die Qualität unserer Beratung, unserer Partner und der von uns zusammengestellten Reisen kontinuierlich weiterzuentwickeln. Wir würden uns daher sehr freuen, wenn Sie sich einen kurzen Moment Zeit für unser Feedbackformular nehmen:
            </p>
          </div>

          {/* Interactive CTA Banner for Survey (Gold Block with Dark Green Button) */}
          <div className="bg-[#E59E0F] border border-[#E59E0F] p-6 sm:p-8 rounded-3xl text-center shadow-lg relative overflow-hidden group">
            <div className="relative z-10 space-y-3.5">
              <h2 className="text-xl sm:text-2xl font-serif font-bold text-[#0f3822] leading-tight">
                Ihr Feedback ist uns wichtig
              </h2>

              <p className="text-[#0f3822]/90 text-xs sm:text-sm max-w-lg mx-auto leading-relaxed font-medium">
                Ihr persönliches Feedback ist für uns von besonderem Wert, um die Qualität und Individualität unserer Golfreisen fortlaufend weiterzuentwickeln.
              </p>

              <div className="pt-2">
                <motion.button
                  whileHover={{ scale: 1.02 }}
                  whileTap={{ scale: 0.98 }}
                  onClick={onStartSurvey}
                  className="inline-flex items-center space-x-2.5 bg-[#0f3822] hover:bg-[#0a2818] text-white font-bold text-sm px-8 py-3.5 rounded-xl shadow-lg transition-all cursor-pointer"
                >
                  <span>Feedback-Umfrage jetzt starten</span>
                  <ArrowRight className="w-4 h-4 text-[#E59E0F]" />
                </motion.button>
              </div>
            </div>
          </div>

          {/* Email Footer */}
          <div className="border-t border-slate-200 pt-6 text-center text-[11px] text-slate-500 space-y-1.5">
            <div className="font-serif text-[#B87A08] font-bold text-sm">golf.extra</div>
            <p className="text-slate-500">
              <a href="https://www.golf-extra.com/" target="_blank" rel="noreferrer" className="underline hover:text-[#B87A08]">
                www.golf-extra.com
              </a>
            </p>
          </div>
        </div>
      </div>
    </div>
  );
};
