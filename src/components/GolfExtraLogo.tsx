import React from 'react';

interface GolfExtraLogoProps {
  size?: 'sm' | 'md' | 'lg' | 'xl';
  variant?: 'gold-bg' | 'dark-bg' | 'light-bg' | 'transparent';
  className?: string;
}

export const GolfExtraLogo: React.FC<GolfExtraLogoProps> = ({
  size = 'md',
  className = ''
}) => {
  const sizeClasses = {
    sm: 'w-10 h-10',
    md: 'w-12 h-12',
    lg: 'w-16 h-16',
    xl: 'w-24 h-24',
  }[size];

  return (
    <div className={`inline-flex items-center justify-center flex-shrink-0 select-none ${sizeClasses} ${className}`}>
      <svg
        viewBox="0 0 400 400"
        className="w-full h-full rounded-2xl shadow-xs overflow-hidden"
      >
        {/* Solid Gold Square Background matching standard logo color */}
        <rect width="400" height="400" fill="#E59E0F" />
        
        {/* Bold White 'golf.' text in lower right area with generous gold padding */}
        <text
          x="105"
          y="310"
          fill="#FFFFFF"
          fontFamily="ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif"
          fontWeight="900"
          fontSize="135"
          letterSpacing="-2px"
        >
          golf.
        </text>

        {/* Light White 'extra' text indented under 'golf.' */}
        <text
          x="200"
          y="370"
          fill="#FFFFFF"
          fontFamily="ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif"
          fontWeight="300"
          fontSize="72"
          letterSpacing="-0.5px"
        >
          extra
        </text>
      </svg>
    </div>
  );
};





