export type Variant = 'mac' | 'iphone' | 'android' | 'windows';

const COMPOSITE: Record<Variant, { src: string; alt: string; w: number; h: number }> = {
  mac: { src: '/img/plink-mac-composite.webp', alt: 'Plink on Mac', w: 701, h: 423 },
  iphone: { src: '/img/plink-iphone-composite.webp', alt: 'Plink on iPhone', w: 478, h: 976 },
  android: { src: '/img/plink-android-composite.webp', alt: 'Plink on Android', w: 407, h: 881 },
  windows: { src: '/img/plink-windows-composite.webp', alt: 'Plink on Windows', w: 921, h: 671 },
};

export function DeviceMockup({ variant }: { variant: Variant }) {
  const img = COMPOSITE[variant];
  const isLaptop = variant === 'mac' || variant === 'windows';

  return (
    <div className={`device-stage ${isLaptop ? 'device-stage-laptop' : 'device-stage-phone'}`}>
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        src={img.src}
        alt={img.alt}
        width={img.w}
        height={img.h}
        className="device-composite"
        draggable={false}
        loading={variant === 'mac' || variant === 'iphone' ? 'eager' : 'lazy'}
      />
    </div>
  );
}