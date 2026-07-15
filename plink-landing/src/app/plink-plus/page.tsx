import { Header } from '@/components/landing/Header';
import { Footer } from '@/components/landing/Footer';
import { PlusSection } from '@/components/landing/HomeSections';

export default function PlinkPlusPage() {
  return (
    <>
      <Header />
      <main className="pt-24">
        <PlusSection />
      </main>
      <Footer />
    </>
  );
}