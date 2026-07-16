import Link from 'next/link';

export default function AndroidPage() {
  return (
    <div className="rave-page" style={{ alignItems: 'center', justifyContent: 'center', padding: 40, textAlign: 'center' }}>
      <Link href="/" className="rave-logo" style={{ marginBottom: 32, display: 'block' }}>← Plink</Link>
      <h1 style={{ fontSize: '2rem', marginBottom: 12 }}>Android</h1>
      <p style={{ color: 'var(--rave-muted)', maxWidth: 400, marginBottom: 24 }}>
        APK скоро. Пока используйте iOS, Mac или Windows.
      </p>
      <Link href="/" style={{ color: 'var(--rave-accent-hover)' }}>Вернуться к установке</Link>
    </div>
  );
}