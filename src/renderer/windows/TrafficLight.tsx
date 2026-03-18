import React, { useEffect, useState } from 'react';
import appIcon from '../assets/AppIcon1024.png';

type Color = 'green' | 'yellow' | 'red';

const COLOR_MAP: Record<Color, string> = {
  green: '#22c55e',
  yellow: '#eab308',
  red: '#ef4444',
};

export default function TrafficLight() {
  const [color, setColor] = useState<Color>('green');
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    const offUpdate = window.ghostedit.onTrafficLightUpdate?.((data: { color: string; visible: boolean }) => {
      setColor(data.color as Color);
      setVisible(data.visible);
    });
    const offHide = window.ghostedit.onTrafficLightHide?.(() => {
      setVisible(false);
    });
    return () => {
      offUpdate?.();
      offHide?.();
    };
  }, []);

  const handleClick = () => {
    window.ghostedit.trafficLightClicked?.();
  };

  return (
    <div
      className="w-[24px] h-[24px] flex items-center justify-center cursor-pointer"
      onClick={handleClick}
      style={{
        WebkitAppRegion: 'no-drag',
        transition: 'all 0.3s ease',
        opacity: visible ? 1 : 0,
        transform: visible ? 'scale(1)' : 'scale(0.8)',
      } as any}
    >
      {/* Round app icon with traffic light badge */}
      <div style={{ position: 'relative', width: 19, height: 19 }}>
        {/* App icon clipped to circle */}
        <img
          src={appIcon}
          alt=""
          style={{
            width: 19,
            height: 19,
            borderRadius: '50%',
            objectFit: 'cover',
            boxShadow: '0 2px 8px rgba(0,0,0,0.25)',
          }}
          draggable={false}
        />

        {/* Traffic light dot — bottom-right, on the circle edge */}
        <div
          style={{
            position: 'absolute',
            bottom: 0,
            right: 0,
            width: 8,
            height: 8,
            borderRadius: '50%',
            backgroundColor: COLOR_MAP[color],
            border: '1.5px solid #1e1e1e',
            transition: 'background-color 0.3s ease',
          }}
        />
      </div>
    </div>
  );
}
