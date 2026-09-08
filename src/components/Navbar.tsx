import React from 'react';
import { GolfExtraLogo } from './GolfExtraLogo';

interface NavbarProps {
  currentView?: 'email' | 'survey' | 'customizer' | 'analytics';
  onViewChange?: (view: 'email' | 'survey' | 'customizer' | 'analytics') => void;
  submissionCount?: number;
}

export const Navbar: React.FC<NavbarProps> = ({
  onViewChange
}) => {
  return (
    <header className="w-full bg-white/95 backdrop-blur-md border-b border-slate-200 sticky top-0 z-40 shadow-sm">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 py-3.5 flex items-center justify-between gap-4">
        {/* Brand Logo */}
        <div 
          className="flex items-center space-x-3.5 cursor-pointer" 
          onClick={() => onViewChange && onViewChange('email')}
        >
          <GolfExtraLogo variant="light-bg" />
        </div>
      </div>
    </header>
  );
};



