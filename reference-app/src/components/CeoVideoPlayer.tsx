import React, { useState, useEffect } from 'react';
import { Play, Pause, Volume2, VolumeX, Award, ShieldCheck, CheckCircle2, ChevronDown, ChevronUp, Radio } from 'lucide-react';
import { CeoVideoConfig, Language } from '../types';

interface CeoVideoPlayerProps {
  config: CeoVideoConfig;
  lang: Language;
}

export const CeoVideoPlayer: React.FC<CeoVideoPlayerProps> = ({ config, lang }) => {
  const [isPlaying, setIsPlaying] = useState<boolean>(false);
  const [isMuted, setIsMuted] = useState<boolean>(false);
  const [progress, setProgress] = useState<number>(0);
  const [currentTime, setCurrentTime] = useState<number>(0);
  const [showTranscript, setShowTranscript] = useState<boolean>(false);
  const [speechActive, setSpeechActive] = useState<boolean>(false);

  const transcript = config.transcripts[lang];

  // Speech Synthesis fallback
  const speakTranscript = () => {
    if ('speechSynthesis' in window) {
      window.speechSynthesis.cancel();
      if (!isPlaying) {
        const utterance = new SpeechSynthesisUtterance(transcript);
        utterance.lang = lang === 'DE' ? 'de-DE' : 'en-US';
        utterance.rate = 0.92;
        utterance.pitch = 0.95;
        
        utterance.onend = () => {
          setIsPlaying(false);
          setSpeechActive(false);
          setProgress(100);
        };

        utterance.onboundary = (event) => {
          const totalLength = transcript.length;
          const currentChar = event.charIndex;
          const pct = Math.min(100, Math.round((currentChar / totalLength) * 100));
          setProgress(pct);
          setCurrentTime(Math.round((pct / 100) * config.durationSeconds));
        };

        window.speechSynthesis.speak(utterance);
        setSpeechActive(true);
      } else {
        window.speechSynthesis.cancel();
        setSpeechActive(false);
      }
    }
  };

  const handlePlayToggle = () => {
    if (isPlaying) {
      setIsPlaying(false);
      if (speechActive && 'speechSynthesis' in window) {
        window.speechSynthesis.cancel();
        setSpeechActive(false);
      }
    } else {
      setIsPlaying(true);
      speakTranscript();
    }
  };

  useEffect(() => {
    let interval: NodeJS.Timeout;
    if (isPlaying && !speechActive) {
      interval = setInterval(() => {
        setCurrentTime((prev) => {
          if (prev >= config.durationSeconds) {
            setIsPlaying(false);
            setProgress(100);
            return config.durationSeconds;
          }
          const next = prev + 1;
          setProgress(Math.round((next / config.durationSeconds) * 100));
          return next;
        });
      }, 1000);
    }
    return () => clearInterval(interval);
  }, [isPlaying, speechActive, config.durationSeconds]);

  useEffect(() => {
    return () => {
      if ('speechSynthesis' in window) {
        window.speechSynthesis.cancel();
      }
    };
  }, []);

  const formatTime = (secs: number) => {
    const m = Math.floor(secs / 60);
    const s = Math.floor(secs % 60);
    return `${m}:${s < 10 ? '0' : ''}${s}`;
  };

  return (
    <div className="w-full bg-slate-50 rounded-2xl overflow-hidden shadow-sm border border-slate-200 relative group">
      {/* Top PGA Badge bar */}
      <div className="bg-slate-100 px-4 py-2 flex items-center justify-between text-xs text-slate-700 border-b border-slate-200">
        <div className="flex items-center space-x-2 font-medium tracking-wide">
          <Award className="w-4 h-4 text-[#E59E0F]" />
          <span className="uppercase tracking-widest text-[10px] text-[#B87A08] font-bold">PGA Professional Message</span>
        </div>
        <div className="flex items-center space-x-2 text-slate-600">
          <ShieldCheck className="w-3.5 h-3.5 text-[#E59E0F]" />
          <span className="text-[11px] font-medium">Golf Extra CEO Video Message</span>
        </div>
      </div>

      {/* Main Video Viewport / Canvas */}
      <div className="relative aspect-video w-full bg-slate-900 flex items-center justify-center overflow-hidden">
        {/* Background Image / Poster */}
        <img
          src={config.videoPoster}
          alt={config.ceoName}
          referrerPolicy="no-referrer"
          className={`absolute inset-0 w-full h-full object-cover transition-transform duration-700 ${isPlaying ? 'scale-105 filter brightness-90' : 'filter brightness-80 hover:scale-102'}`}
        />

        {/* Ambient Dark Gradient overlay */}
        <div className="absolute inset-0 bg-gradient-to-t from-[#0a2818]/90 via-[#0a2818]/40 to-transparent" />

        {/* CEO Personal Avatar Card overlay */}
        <div className="absolute top-4 left-4 flex items-center space-x-3 bg-white/90 backdrop-blur-md px-3.5 py-2 rounded-xl border border-slate-200 shadow-md">
          <div className="relative">
            <div className="w-9 h-9 rounded-full bg-[#E59E0F] p-0.5 shadow-sm flex items-center justify-center">
              <div className="w-full h-full rounded-full bg-[#0f3822] flex items-center justify-center text-[#E59E0F] font-serif font-bold text-xs">
                EE
              </div>
            </div>
            <div className="absolute -bottom-1 -right-1 bg-[#E59E0F] text-[#0f3822] text-[9px] font-bold px-1 rounded shadow-xs">
              PGA
            </div>
          </div>
          <div>
            <div className="text-slate-900 font-semibold text-xs leading-tight flex items-center gap-1.5">
              <span>{config.ceoName}</span>
              <CheckCircle2 className="w-3.5 h-3.5 text-[#E59E0F] fill-amber-100" />
            </div>
            <div className="text-slate-500 text-[11px] font-medium">{config.ceoTitle}</div>
          </div>
        </div>

        {/* Live Audio Spectrum Wave Animation during playback */}
        {isPlaying && (
          <div className="absolute top-4 right-4 flex items-center space-x-1.5 bg-slate-900/90 backdrop-blur-md px-3 py-1.5 rounded-full border border-amber-500/40">
            <Radio className="w-3.5 h-3.5 text-[#E59E0F]" />
            <span className="text-[11px] font-medium text-amber-200 uppercase tracking-wider mr-1">Playing Audio</span>
            <div className="flex items-end space-x-0.5 h-3">
              <div className="w-1 bg-[#E59E0F] rounded-full animate-[bounce_1s_infinite_100ms]" style={{ height: '60%' }} />
              <div className="w-1 bg-amber-200 rounded-full animate-[bounce_1s_infinite_300ms]" style={{ height: '100%' }} />
              <div className="w-1 bg-[#E59E0F] rounded-full animate-[bounce_1s_infinite_200ms]" style={{ height: '40%' }} />
              <div className="w-1 bg-amber-200 rounded-full animate-[bounce_1s_infinite_400ms]" style={{ height: '80%' }} />
            </div>
          </div>
        )}

        {/* Center Play Button Overlay if Paused */}
        {!isPlaying && (
          <button
            onClick={handlePlayToggle}
            className="group/play relative z-10 flex flex-col items-center justify-center text-center transition-all transform hover:scale-105 active:scale-95 cursor-pointer"
            aria-label="Play CEO Video Message"
          >
            <div className="w-16 h-16 sm:w-20 sm:h-20 rounded-full bg-[#E59E0F] text-[#0f3822] flex items-center justify-center shadow-xl border-2 border-white group-hover/play:bg-[#D99313] transition-colors">
              <Play className="w-8 h-8 fill-[#0f3822] ml-1" />
            </div>
            <span className="mt-3 bg-white text-slate-900 text-xs font-sans font-semibold px-4 py-1.5 rounded-full border border-slate-200 shadow-md flex items-center gap-1.5">
              {lang === 'DE' ? 'CEO Videobotschaft abspielen' : 'Play CEO Video Message'}
            </span>
          </button>
        )}

        {/* Live Subtitle Overlay during Playback */}
        {isPlaying && (
          <div className="absolute bottom-16 left-6 right-6 text-center z-10">
            <div className="inline-block bg-slate-900/90 backdrop-blur-md text-slate-100 text-xs sm:text-sm px-4 py-2 rounded-xl border border-slate-700 shadow-xl max-w-xl mx-auto leading-relaxed">
              <span className="text-[#D8B467] font-semibold mr-1.5">Mr. Erguel:</span>
              "{lang === 'DE' ? 'Vielen Dank, dass Sie Golf Extra für Ihre Traumreise vertraut haben.' : 'Thank you for trusting Golf Extra for your luxury getaway.'}"
            </div>
          </div>
        )}

        {/* Video Control Bar */}
        <div className="absolute bottom-0 inset-x-0 bg-slate-900/95 backdrop-blur-md px-4 py-2.5 border-t border-slate-800 flex flex-col gap-1 z-20">
          {/* Progress Slider */}
          <div className="w-full bg-slate-800 h-1.5 rounded-full overflow-hidden cursor-pointer relative">
            <div
              className="bg-[#C5A059] h-full transition-all duration-300"
              style={{ width: `${progress}%` }}
            />
          </div>

          <div className="flex items-center justify-between text-xs text-slate-200 pt-1 font-sans">
            <div className="flex items-center space-x-3">
              <button
                onClick={handlePlayToggle}
                className="hover:text-[#C5A059] transition-colors p-1 rounded focus:outline-none cursor-pointer"
              >
                {isPlaying ? <Pause className="w-4 h-4" /> : <Play className="w-4 h-4 fill-slate-200" />}
              </button>

              <button
                onClick={() => setIsMuted(!isMuted)}
                className="hover:text-[#C5A059] transition-colors p-1 rounded focus:outline-none cursor-pointer"
              >
                {isMuted ? <VolumeX className="w-4 h-4 text-rose-400" /> : <Volume2 className="w-4 h-4" />}
              </button>

              <span className="text-[11px] font-mono text-slate-400">
                {formatTime(currentTime)} / {formatTime(config.durationSeconds)}
              </span>
            </div>

            <div className="flex items-center space-x-2">
              <button
                onClick={() => setShowTranscript(!showTranscript)}
                className="text-[11px] text-[#D8B467] hover:text-white flex items-center space-x-1 bg-slate-800 px-2.5 py-1 rounded-lg border border-slate-700 cursor-pointer font-medium"
              >
                <span>{lang === 'DE' ? 'Transkript' : 'Transcript'}</span>
                {showTranscript ? <ChevronUp className="w-3 h-3" /> : <ChevronDown className="w-3 h-3" />}
              </button>
            </div>
          </div>
        </div>
      </div>

      {/* Accordion Transcript Drawer */}
      {showTranscript && (
        <div className="p-4 bg-white border-t border-slate-200 text-slate-700 text-xs leading-relaxed font-sans whitespace-pre-line animate-fadeIn">
          <div className="flex items-center justify-between mb-2 text-[#1E3A2B] font-semibold text-xs border-b border-slate-200 pb-1">
            <span>{lang === 'DE' ? 'Persönliche Botschaft von CEO Erguel Erguel' : 'Personal Message from CEO Erguel Erguel'}</span>
            <span className="text-slate-400 text-[10px] uppercase tracking-wider">Golf Extra</span>
          </div>
          {transcript}
        </div>
      )}
    </div>
  );
};

