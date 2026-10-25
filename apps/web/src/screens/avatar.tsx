import { UserIcon } from "@phosphor-icons/react";
import { type CSSProperties, useEffect, useId, useMemo, useRef } from "react";
import { mediaURL } from "@/api/chats";
import type { Avatar as AvatarValue, Person } from "@/api/types";
import {
  blobAvatar,
  blobBreath,
  blobIdlePhase,
  blobOutline,
  blobPath,
  cssColor,
  decodeSeed,
} from "@/lib/blob-avatar";
import { cn } from "@/lib/utils";
import { useSession } from "@/session/session";

const viewBoxSize = 100;

/** Decorative: place it next to the person's name. `large` loads the bigger photo. */
export function Avatar({
  avatar,
  large = false,
  className,
}: {
  avatar: AvatarValue;
  large?: boolean;
  className?: string;
}) {
  const { serverURL } = useSession();
  const base = cn("inline-block size-7 shrink-0 rounded-full", className);
  if (avatar.photo) {
    const path = large ? avatar.photo.large : avatar.photo.thumb;
    return (
      <img
        className={cn(base, "bg-muted object-cover")}
        src={mediaURL(serverURL, path)}
        alt=""
      />
    );
  }
  return <BlobAvatar seed={avatar.seed} className={base} />;
}

function BlobAvatar({ seed, className }: { seed: string; className: string }) {
  const gradientId = useId();
  const outline = useRef<SVGPathElement>(null);
  const { bytes, blob, phase } = useMemo(() => {
    const bytes = decodeSeed(seed);
    return { bytes, blob: blobAvatar(bytes), phase: blobIdlePhase(bytes) };
  }, [seed]);
  useEffect(() => {
    if (matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    let frame = requestAnimationFrame(function breathe(now) {
      const shape = blobOutline(bytes, blobBreath(now / 1000, phase));
      outline.current?.setAttribute(
        "d",
        blobPath({ ...blob, ...shape }, viewBoxSize),
      );
      frame = requestAnimationFrame(breathe);
    });
    return () => cancelAnimationFrame(frame);
  }, [bytes, blob, phase]);
  return (
    <svg
      className={className}
      viewBox={`0 0 ${viewBoxSize} ${viewBoxSize}`}
      style={{ "--blob-phase": phase } as CSSProperties}
      aria-hidden="true"
    >
      <defs>
        <linearGradient id={gradientId} x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor={cssColor(blob.fill[0])} />
          <stop offset="1" stopColor={cssColor(blob.fill[1])} />
        </linearGradient>
      </defs>
      <path
        ref={outline}
        d={blobPath(blob, viewBoxSize)}
        fill={`url(#${gradientId})`}
      />
      <g className="blob-look">
        {blob.eyes.map((eye) => (
          <rect
            key={eye.x}
            className="blob-blink"
            x={eye.x * viewBoxSize}
            y={eye.y * viewBoxSize}
            width={eye.width * viewBoxSize}
            height={eye.height * viewBoxSize}
            rx={(eye.width * viewBoxSize) / 2}
            fill={cssColor(blob.eyeColor)}
          />
        ))}
      </g>
    </svg>
  );
}

/** The person's avatar once they are public, and a plain silhouette before. */
export function ConnectionAvatar({
  them,
  className,
}: {
  them: Person | null;
  className?: string;
}) {
  if (them) return <Avatar avatar={them.avatar} className={className} />;
  return (
    <span
      className={cn(
        "inline-flex size-7 shrink-0 items-center justify-center rounded-full bg-muted text-muted-foreground",
        className,
      )}
      aria-hidden="true"
    >
      <UserIcon />
    </span>
  );
}
