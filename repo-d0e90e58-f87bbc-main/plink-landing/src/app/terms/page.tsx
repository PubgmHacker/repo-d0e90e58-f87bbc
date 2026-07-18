import { Header } from '@/components/landing/Header';
import { Footer } from '@/components/landing/Footer';

export default function TermsPage() {
  return (
    <>
      <Header />
      <main className="subpage-main prose prose-invert mx-auto max-w-3xl px-4 py-24">
        <h1>Terms of Service</h1>
        <p>By using Plink you agree to our community guidelines. Do not share copyrighted content without rights. Plink+ subscriptions renew automatically unless cancelled.</p>
      </main>
      <Footer />
    </>
  );
}