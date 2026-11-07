import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.modernlibrary.hodor',
  appName: 'HODOR',
  webDir: 'www',
  bundledWebRuntime: false,
  backgroundColor: '#101827',
  plugins: {
    SplashScreen: {
      launchShowDuration: 1200,
      backgroundColor: '#101827',
      showSpinner: false
    }
  }
};

export default config;
