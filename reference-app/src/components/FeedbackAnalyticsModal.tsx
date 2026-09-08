import React from 'react';
import { SubmittedFeedback, Language } from '../types';
import { User, Calendar, Award, Star } from 'lucide-react';

interface FeedbackAnalyticsModalProps {
  submissions: SubmittedFeedback[];
  lang: Language;
  onClose: () => void;
}

export const FeedbackAnalyticsModal: React.FC<FeedbackAnalyticsModalProps> = ({
  submissions,
  lang,
  onClose
}) => {
  const avgSatisfaction =
    submissions.length > 0
      ? (submissions.reduce((acc, curr) => acc + (curr.surveyData?.overallExperience || 10), 0) / submissions.length).toFixed(1)
      : '10.0';

  const recommendationCount =
    submissions.length > 0
      ? submissions.filter((s) => {
          const rec = s.surveyData?.recommendation;
          if (typeof rec === 'number') return rec >= 9;
          return rec === 'Ja' || (s.surveyData as any)?.recommendationChoice === 'JA';
        }).length
      : 0;

  return (
    <div className="w-full max-w-4xl mx-auto bg-white border border-slate-200 rounded-3xl p-6 sm:p-8 shadow-xl space-y-6 text-slate-800 font-sans">
      <div className="flex items-center justify-between border-b border-slate-200 pb-4">
        <div>
          <span className="text-[#B87A08] text-[10px] uppercase font-sans tracking-widest font-bold">Golf Extra Management</span>
          <h2 className="text-xl font-bold text-slate-900">
            {lang === 'DE' ? 'Eingegangene Kunden-Feedbacks' : 'Customer Feedback Log'}
          </h2>
        </div>
        <button
          onClick={onClose}
          className="text-slate-600 hover:text-slate-900 text-xs bg-slate-100 hover:bg-slate-200 px-3.5 py-1.5 rounded-xl border border-slate-200 cursor-pointer font-semibold"
        >
          {lang === 'DE' ? 'Schließen' : 'Close'}
        </button>
      </div>

      {/* High level KPI cards */}
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <div className="bg-slate-50 p-4 rounded-2xl border border-slate-200 text-center">
          <div className="text-slate-600 text-xs font-medium">{lang === 'DE' ? 'Ø Gesamterfahrung' : 'Avg Trip Experience'}</div>
          <div className="text-[#B87A08] font-bold text-2xl mt-1">{avgSatisfaction} / 10</div>
          <div className="text-[10px] text-slate-500 mt-0.5">NPS Post-Trip Rating</div>
        </div>

        <div className="bg-slate-50 p-4 rounded-2xl border border-slate-200 text-center">
          <div className="text-slate-600 text-xs font-medium">{lang === 'DE' ? 'Weiterempfehlungen' : 'Positive Recommendations'}</div>
          <div className="text-[#B87A08] font-bold text-2xl mt-1">{recommendationCount} / {submissions.length || 1}</div>
          <div className="text-[10px] text-slate-500 mt-0.5">Ja / Yes</div>
        </div>
      </div>

      {/* Submissions Table */}
      <div className="space-y-3">
        <h3 className="text-slate-900 font-bold text-sm">
          {lang === 'DE' ? 'Letzte Rückmeldungen' : 'Recent Submissions'}
        </h3>

        {submissions.length === 0 ? (
          <div className="bg-slate-50 p-6 rounded-2xl text-center text-slate-500 text-xs border border-slate-200">
            {lang === 'DE' ? 'Noch keine Feedbacks eingegangen. Testen Sie die Umfrage!' : 'No live submissions yet. Complete the survey to log live feedback!'}
          </div>
        ) : (
          <div className="space-y-3">
            {submissions.map((sub) => (
              <div key={sub.id} className="bg-slate-50 p-4 rounded-2xl border border-slate-200 space-y-2 text-xs">
                <div className="flex justify-between items-center text-slate-700">
                  <div className="flex items-center space-x-2">
                    <User className="w-4 h-4 text-[#E59E0F]" />
                    <span className="font-bold text-slate-900">{sub.guestName}</span>
                    <span className="text-slate-500 font-mono">({sub.bookingRef})</span>
                  </div>
                  <span className="text-slate-500 text-[11px]">{sub.timestamp}</span>
                </div>

                <div className="grid grid-cols-3 gap-2 bg-white p-2.5 rounded-xl border border-slate-200 text-[11px]">
                  <div>
                    <span className="text-slate-500">Overall:</span>{' '}
                    <strong className="text-slate-900">{sub.surveyData?.overallExperience || 10}/10</strong>
                  </div>
                  <div>
                    <span className="text-slate-500">Consultation:</span>{' '}
                    <strong className="text-[#B87A08]">{sub.surveyData?.consultationProductSelection || 10}/10</strong>
                  </div>
                  <div>
                    <span className="text-slate-500">Recommendation:</span>{' '}
                    <strong className="text-[#B87A08]">
                      {typeof sub.surveyData?.recommendation === 'number'
                        ? `${sub.surveyData.recommendation}/10`
                        : (sub.surveyData?.recommendationChoice || sub.surveyData?.recommendation || '10/10')}
                    </strong>
                  </div>
                </div>

                {(sub.surveyData?.nextBucketListDestination || sub.surveyData?.positiveMoment) && (
                  <div className="text-slate-700 text-xs bg-white p-2 rounded-lg border border-slate-200">
                    <span className="font-semibold text-slate-500 text-[10px] block uppercase tracking-wider">Bucket List Destination</span>
                    <span className="italic">"{sub.surveyData.nextBucketListDestination || sub.surveyData.positiveMoment}"</span>
                  </div>
                )}
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
};
