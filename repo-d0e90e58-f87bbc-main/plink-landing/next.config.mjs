/** @type {import('next').NextConfig} */
const nextConfig = {
  async redirects() {
    return [
      { source: '/mac', destination: '/downloads/Plink.dmg', permanent: false },
      { source: '/windows', destination: '/downloads/Plink-1.0.0-x64-setup.exe', permanent: false },
      { source: '/ios', destination: 'https://apps.apple.com/app/plink-watch-together/id6750000001', permanent: false, basePath: false },

    ];
  },
};

export default nextConfig;