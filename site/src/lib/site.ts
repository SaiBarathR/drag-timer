import fs from 'node:fs';
import path from 'node:path';

const plist = (() => {
  try {
    return fs.readFileSync(path.resolve(process.cwd(), '..', 'Packaging', 'Info.plist'), 'utf8');
  } catch {
    return '';
  }
})();
const plistString = (key: string) => plist.match(new RegExp(`<key>${key}</key>\\s*<string>([^<]+)</string>`))?.[1];

/** The app version in ../Packaging/Info.plist at build time, used for file names and the download fallback. */
export const APP_VERSION: string = plistString('CFBundleShortVersionString') ?? '1.7.0';
/** The oldest macOS the app runs on, as a major version ("14"). */
export const MIN_MACOS: string = (plistString('LSMinimumSystemVersion') ?? '14.0').replace(/\.0$/, '');

export const SITE = {
  name: 'Drag Timer',
  url: 'https://saibarathr.github.io/drag-timer/',
  repo: 'https://github.com/SaiBarathR/drag-timer',
  releases: 'https://github.com/SaiBarathR/drag-timer/releases',
  latestRelease: 'https://github.com/SaiBarathR/drag-timer/releases/latest',
  releasesApi: 'https://api.github.com/repos/SaiBarathR/drag-timer/releases/latest',
  description:
    'Drag Timer is a native macOS menu-bar timer: pull time out of the clock icon, let go, and the timer starts. Free and open source.',
};

/** The universal zip a release carries, e.g. Drag-Timer-1.7.0-macos-universal.zip. */
export const zipName = (version = APP_VERSION) => `Drag-Timer-${version}-macos-universal.zip`;

/** Prefix a site path with the base path (/drag-timer/). */
export function url(p = ''): string {
  const base = import.meta.env.BASE_URL.replace(/\/?$/, '/');
  return base + p.replace(/^\//, '');
}
