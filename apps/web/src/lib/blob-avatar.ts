/**
 * Blob avatar geometry from an avatar seed. The iOS app draws the same shape
 * from the same seed, and `docs/fixtures/blob-avatar.json` holds the
 * expected output for both. Coordinates are in a unit square.
 */

export interface Point {
  x: number;
  y: number;
}

/** One cubic Bézier segment, starting where the previous one ended. */
export interface Curve {
  control1: Point;
  control2: Point;
  end: Point;
}

/** A vertical pill. `x` and `y` are its top-left corner. */
export interface Eye {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface HSL {
  hue: number;
  saturation: number;
  lightness: number;
}

export interface BlobAvatar {
  start: Point;
  curves: Curve[];
  eyes: [Eye, Eye];
  /** The top-left and bottom-right colors of a diagonal gradient. */
  fill: [HSL, HSL];
  eyeColor: HSL;
}

const center = 0.5;
const minPointCount = 6;
const pointCountChoices = 3;
const minRadius = 0.34;
const radiusRange = 0.1;
const eyeWidth = 0.06;
const eyeHeight = 0.12;
const minEyeGap = 0.075;
const eyeGapRange = 0.03;
const minEyeTop = 0.39;
const eyeTopRange = 0.04;
const gazeRange = 0.04;
const gradientHueShift = 40;

export function blobAvatar(seed: Uint8Array): BlobAvatar {
  const byte = (index: number) => (seed[index] ?? 0) / 255;
  const pointCount = minPointCount + ((seed[0] ?? 0) % pointCountChoices);
  const hue = ((seed[1] ?? 0) * 256 + (seed[2] ?? 0)) % 360;
  const step = (2 * Math.PI) / pointCount;
  const rotation = byte(3) * step;
  const points = Array.from({ length: pointCount }, (_, index) => {
    const radius = minRadius + byte(4 + index) * radiusRange;
    const angle = rotation + index * step - Math.PI / 2;
    return {
      x: center + radius * Math.cos(angle),
      y: center + radius * Math.sin(angle),
    };
  });
  const gap = minEyeGap + byte(12) * eyeGapRange;
  const top = minEyeTop + byte(13) * eyeTopRange;
  const gaze = (byte(14) - 0.5) * gazeRange;
  const eyeAt = (middle: number): Eye => ({
    x: middle - eyeWidth / 2,
    y: top,
    width: eyeWidth,
    height: eyeHeight,
  });
  return {
    start: points[0] ?? { x: center, y: center },
    curves: smoothClosedCurves(points),
    eyes: [eyeAt(center - gap + gaze), eyeAt(center + gap + gaze)],
    fill: [
      { hue, saturation: 0.8, lightness: 0.82 },
      {
        hue: (hue + gradientHueShift) % 360,
        saturation: 0.7,
        lightness: 0.68,
      },
    ],
    eyeColor: { hue, saturation: 0.4, lightness: 0.2 },
  };
}

/** A closed Catmull-Rom spline through every point, as cubic Béziers. */
function smoothClosedCurves(points: Point[]): Curve[] {
  const at = (index: number) =>
    points[(index + points.length) % points.length] ?? { x: 0, y: 0 };
  return points.map((_, index) => {
    const previous = at(index - 1);
    const current = at(index);
    const next = at(index + 1);
    const afterNext = at(index + 2);
    return {
      control1: {
        x: current.x + (next.x - previous.x) / 6,
        y: current.y + (next.y - previous.y) / 6,
      },
      control2: {
        x: next.x - (afterNext.x - current.x) / 6,
        y: next.y - (afterNext.y - current.y) / 6,
      },
      end: next,
    };
  });
}

/** An SVG path in a box of `size`. */
export function blobPath(avatar: BlobAvatar, size: number): string {
  const scaled = (point: Point) =>
    `${round(point.x * size)} ${round(point.y * size)}`;
  const segments = avatar.curves.map(
    (curve) =>
      `C${scaled(curve.control1)} ${scaled(curve.control2)} ${scaled(curve.end)}`,
  );
  return `M${scaled(avatar.start)}${segments.join("")}Z`;
}

export function cssColor({ hue, saturation, lightness }: HSL): string {
  return `hsl(${hue} ${round(saturation * 100)}% ${round(lightness * 100)}%)`;
}

export function decodeSeed(seed: string): Uint8Array {
  const base64 = seed.replaceAll("-", "+").replaceAll("_", "/");
  return Uint8Array.from(atob(base64), (character) => character.charCodeAt(0));
}

function round(value: number): number {
  return Math.round(value * 1000) / 1000;
}
