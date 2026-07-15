import { Header } from '@/components/landing/Header';
import { Footer } from '@/components/landing/Footer';
import {
  HeroSection,
  DownloadSection,
  FeaturesSection,
  HowItWorksSection,
  ComparisonSection,
  PlusSection,
  TestimonialsSection,
} from '@/components/landing/HomeSections';

export default function HomePage() {
  return (
    <>
      <Header />
      <main>
        <HeroSection />
        <DownloadSection />
        <FeaturesSection />
        <HowItWorksSection />
        <ComparisonSection />
        <PlusSection />
        <TestimonialsSection />
      </main>
      <Footer />
    </>
  );
}