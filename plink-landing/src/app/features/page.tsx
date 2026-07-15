import { Header } from '@/components/landing/Header';
import { Footer } from '@/components/landing/Footer';
import { FeaturesSection } from '@/components/landing/HomeSections';

export default function FeaturesPage() {
  return (
    <>
      <Header />
      <main className="pt-24">
        <FeaturesSection />
      </main>
      <Footer />
    </>
  );
}