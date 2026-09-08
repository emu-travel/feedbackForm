import React, { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { TripItinerary, CeoVideoConfig, Language, SubmittedFeedback } from './types';
import { initialTripItinerary, initialCeoVideoConfig } from './data/initialData';
import { Navbar } from './components/Navbar';
import { EmailTemplateView } from './components/EmailTemplateView';
import { SurveyView } from './components/SurveyView';
import { EmailCustomizer } from './components/EmailCustomizer';
import { FeedbackAnalyticsModal } from './components/FeedbackAnalyticsModal';

export default function App() {
  const [currentView, setCurrentView] = useState<'email' | 'survey' | 'customizer' | 'analytics'>('email');
  const [lang, setLang] = useState<Language>('DE');
  const [itinerary, setItinerary] = useState<TripItinerary>(initialTripItinerary);
  const [ceoConfig, setCeoConfig] = useState<CeoVideoConfig>(initialCeoVideoConfig);
  const [submissions, setSubmissions] = useState<SubmittedFeedback[]>([]);
  const [showCustomizerModal, setShowCustomizerModal] = useState<boolean>(false);

  const handleSurveySubmitted = (feedback: SubmittedFeedback) => {
    setSubmissions((prev) => [feedback, ...prev]);
  };

  return (
    <div className="min-h-screen bg-[#FAFAFA] text-slate-900 font-sans selection:bg-[#1E3A2B] selection:text-white flex flex-col">
      {/* Top Navbar */}
      <Navbar
        currentView={currentView}
        onViewChange={setCurrentView}
        submissionCount={submissions.length}
      />

      {/* Main Container */}
      <main className="flex-1 max-w-7xl w-full mx-auto px-4 sm:px-6 py-8 flex flex-col items-center">
        {/* View Switcher Content with Smooth Transitions */}
        <AnimatePresence mode="wait">
          <motion.div
            key={currentView}
            initial={{ opacity: 0, y: 15 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -15 }}
            transition={{ duration: 0.25, ease: 'easeOut' }}
            className="w-full flex justify-center"
          >
            {currentView === 'email' && (
              <EmailTemplateView
                itinerary={itinerary}
                ceoConfig={ceoConfig}
                lang={lang}
                onStartSurvey={() => setCurrentView('survey')}
                onOpenCustomizer={() => setShowCustomizerModal(true)}
              />
            )}

            {currentView === 'survey' && (
              <SurveyView
                itinerary={itinerary}
                lang={lang}
                onSurveySubmitted={handleSurveySubmitted}
                onBackToEmail={() => setCurrentView('email')}
              />
            )}

            {currentView === 'analytics' && (
              <FeedbackAnalyticsModal
                submissions={submissions}
                lang={lang}
                onClose={() => setCurrentView('email')}
              />
            )}
          </motion.div>
        </AnimatePresence>

        {/* Email Customizer Modal */}
        {showCustomizerModal && (
          <EmailCustomizer
            itinerary={itinerary}
            ceoConfig={ceoConfig}
            lang={lang}
            onUpdateItinerary={setItinerary}
            onUpdateCeoConfig={setCeoConfig}
            onClose={() => setShowCustomizerModal(false)}
          />
        )}
      </main>

      {/* Footer */}
      <footer className="w-full bg-white border-t border-slate-200 py-6 text-center text-xs text-slate-500">
        <div className="max-w-7xl mx-auto px-4 flex flex-col sm:flex-row items-center justify-between gap-3">
          <div>
            © 2026 Golf Extra GmbH
          </div>
          <div>
            <a
              href="https://www.golf-extra.com/"
              target="_blank"
              rel="noreferrer"
              className="text-slate-600 hover:text-[#1E3A2B] transition-colors"
            >
              golf-extra.com
            </a>
          </div>
        </div>
      </footer>
    </div>
  );
}

