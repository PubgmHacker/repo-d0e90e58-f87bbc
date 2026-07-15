import { Header } from '@/components/landing/Header';
import { Footer } from '@/components/landing/Footer';

export default function PrivacyPage() {
  return (
    <>
      <Header />
      <main className="prose prose-invert mx-auto max-w-3xl px-4 py-24">
        <h1>Privacy Policy</h1>
        <p>Plink collects account email, usage analytics, and watch-room metadata to provide sync and chat services. Data is stored on Railway (EU/US). Contact: support@plink.app.</p>
      </main>
      <Footer />
    </>
  );
}