import React, { useState } from 'react';
import { TripItinerary, CeoVideoConfig, Language } from '../types';
import { Settings, Save, User, Building2, Star } from 'lucide-react';

interface EmailCustomizerProps {
  itinerary: TripItinerary;
  ceoConfig: CeoVideoConfig;
  lang: Language;
  onUpdateItinerary: (updated: TripItinerary) => void;
  onUpdateCeoConfig: (updated: CeoVideoConfig) => void;
  onClose: () => void;
}

export const EmailCustomizer: React.FC<EmailCustomizerProps> = ({
  itinerary,
  ceoConfig,
  lang,
  onUpdateItinerary,
  onUpdateCeoConfig,
  onClose
}) => {
  const [formItinerary, setFormItinerary] = useState<TripItinerary>(itinerary);
  const [formCeo, setFormCeo] = useState<CeoVideoConfig>(ceoConfig);

  const handleSave = () => {
    onUpdateItinerary(formItinerary);
    onUpdateCeoConfig(formCeo);
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 bg-slate-900/60 backdrop-blur-xs flex items-center justify-center p-4 overflow-y-auto">
      <div className="bg-white border border-slate-200 rounded-3xl p-6 sm:p-8 max-w-2xl w-full text-slate-800 shadow-2xl my-8 relative space-y-6 font-sans">
        <div className="flex items-center justify-between border-b border-slate-200 pb-4">
          <div className="flex items-center space-x-2">
            <Settings className="w-5 h-5 text-[#E59E0F]" />
            <h2 className="text-lg font-bold text-slate-900">
              E-Mail & Reise-Daten anpassen
            </h2>
          </div>
          <button onClick={onClose} className="text-slate-400 hover:text-slate-700 p-1 cursor-pointer">✕</button>
        </div>

        <div className="space-y-5 text-xs">
          {/* Guest Info */}
          <div className="space-y-2">
            <div className="flex items-center space-x-1.5 text-[#B87A08] font-bold uppercase tracking-wider text-[11px]">
              <User className="w-3.5 h-3.5" />
              <span>Kundeninformationen</span>
            </div>
            <div className="grid grid-cols-3 gap-2">
              <div>
                <label className="text-slate-600 block mb-1">Anrede / Titel</label>
                <input
                  type="text"
                  value={formItinerary.guestTitle}
                  onChange={(e) => setFormItinerary({ ...formItinerary, guestTitle: e.target.value })}
                  className="w-full bg-slate-50 border border-slate-200 rounded-xl p-2.5 text-slate-900 focus:border-[#E59E0F] focus:outline-none"
                />
              </div>
              <div className="col-span-2">
                <label className="text-slate-600 block mb-1">Vollständiger Name</label>
                <input
                  type="text"
                  value={formItinerary.guestName}
                  onChange={(e) => setFormItinerary({ ...formItinerary, guestName: e.target.value })}
                  className="w-full bg-slate-50 border border-slate-200 rounded-xl p-2.5 text-slate-900 font-medium"
                />
              </div>
            </div>
            <div className="grid grid-cols-2 gap-2">
              <div>
                <label className="text-slate-600 block mb-1">Buchungsreferenz</label>
                <input
                  type="text"
                  value={formItinerary.bookingReference}
                  onChange={(e) => setFormItinerary({ ...formItinerary, bookingReference: e.target.value })}
                  className="w-full bg-slate-50 border border-slate-200 rounded-xl p-2.5 text-[#B87A08] font-mono font-semibold"
                />
              </div>
              <div>
                <label className="text-slate-600 block mb-1">Reisezeitraum</label>
                <input
                  type="text"
                  value={formItinerary.travelDates}
                  onChange={(e) => setFormItinerary({ ...formItinerary, travelDates: e.target.value })}
                  className="w-full bg-slate-50 border border-slate-200 rounded-xl p-2.5 text-slate-900"
                />
              </div>
            </div>
          </div>

          {/* Destination & Hotel */}
          <div className="space-y-2 border-t border-slate-200 pt-4">
            <div className="flex items-center space-x-1.5 text-[#B87A08] font-bold uppercase tracking-wider text-[11px]">
              <Building2 className="w-3.5 h-3.5" />
              <span>Zielort & Hotel</span>
            </div>
            <div>
              <label className="text-slate-600 block mb-1">Reiseziel (Land / Ort)</label>
              <input
                type="text"
                value={formItinerary.destination}
                onChange={(e) => setFormItinerary({ ...formItinerary, destination: e.target.value })}
                className="w-full bg-slate-50 border border-slate-200 rounded-xl p-2.5 text-slate-900"
              />
            </div>
            <div className="grid grid-cols-2 gap-2">
              <div>
                <label className="text-slate-600 block mb-1">Hotelname</label>
                <input
                  type="text"
                  value={formItinerary.hotel.name}
                  onChange={(e) => setFormItinerary({ ...formItinerary, hotel: { ...formItinerary.hotel, name: e.target.value } })}
                  className="w-full bg-slate-50 border border-slate-200 rounded-xl p-2.5 text-slate-900"
                />
              </div>
              <div>
                <label className="text-slate-600 block mb-1">Zimmerkategorie</label>
                <input
                  type="text"
                  value={formItinerary.hotel.roomType}
                  onChange={(e) => setFormItinerary({ ...formItinerary, hotel: { ...formItinerary.hotel, roomType: e.target.value } })}
                  className="w-full bg-slate-50 border border-slate-200 rounded-xl p-2.5 text-slate-900"
                />
              </div>
            </div>
          </div>

          {/* Public Review Links (Trustpilot & Google Maps) */}
          <div className="space-y-2 border-t border-slate-200 pt-4">
            <div className="flex items-center space-x-1.5 text-[#B87A08] font-bold uppercase tracking-wider text-[11px]">
              <Star className="w-3.5 h-3.5" />
              <span>Bewertungs-Plattform Links</span>
            </div>
            <div className="grid grid-cols-2 gap-2">
              <div>
                <label className="text-slate-600 block mb-1">Trustpilot Bewertungslink</label>
                <input
                  type="text"
                  value={formItinerary.trustpilotUrl || 'https://www.trustpilot.com/evaluate/emu-travel.com'}
                  onChange={(e) => setFormItinerary({ ...formItinerary, trustpilotUrl: e.target.value })}
                  className="w-full bg-slate-50 border border-slate-200 rounded-xl p-2.5 text-amber-800 font-mono text-xs font-medium"
                />
              </div>
              <div>
                <label className="text-slate-600 block mb-1">Google Maps Bewertungslink</label>
                <input
                  type="text"
                  value={formItinerary.googleMapsUrl || 'https://maps.google.com/?q=golf.extra+GmbH+Heilbronn'}
                  onChange={(e) => setFormItinerary({ ...formItinerary, googleMapsUrl: e.target.value })}
                  className="w-full bg-slate-50 border border-slate-200 rounded-xl p-2.5 text-blue-800 font-mono text-xs font-medium"
                />
              </div>
            </div>
          </div>
        </div>

        <div className="flex items-center justify-end space-x-3 border-t border-slate-200 pt-4">
          <button
            onClick={onClose}
            className="bg-slate-100 hover:bg-slate-200 text-slate-700 px-4 py-2 rounded-xl text-xs font-semibold cursor-pointer"
          >
            Abbrechen
          </button>
          <button
            onClick={handleSave}
            className="flex items-center space-x-1.5 bg-[#E59E0F] hover:bg-[#D99313] text-[#0f3822] font-bold px-5 py-2 rounded-xl text-xs transition-all shadow-md cursor-pointer"
          >
            <Save className="w-4 h-4" />
            <span>Änderungen übernehmen</span>
          </button>
        </div>
      </div>
    </div>
  );
};
