import { ImageIcon, TrashIcon } from "@phosphor-icons/react";
import { useEffect, useRef, useState } from "react";
import Cropper from "react-easy-crop";
import type { Avatar as AvatarValue } from "@/api/types";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { useProfilePhoto } from "@/flows/use-profile-photo";
import type { CropArea } from "@/lib/crop-image";
import { acceptedImageTypes } from "@/lib/image-types";
import { Avatar } from "./avatar";
import { ErrorAlert } from "./parts";

const maxZoom = 4;

/** Shows the current photo or blob, and lets the person pick and crop a new one. */
export function ProfilePhotoEditor({
  avatar,
  label,
}: {
  avatar: AvatarValue;
  label: string;
}) {
  const photo = useProfilePhoto();
  const fileInput = useRef<HTMLInputElement>(null);
  const [pickedURL, setPickedURL] = useState<string | null>(null);
  const { busy } = photo.activity;

  useEffect(() => {
    if (!pickedURL) return;
    return () => URL.revokeObjectURL(pickedURL);
  }, [pickedURL]);

  const save = async (imageURL: string, area: CropArea) => {
    if (await photo.upload(imageURL, area)) setPickedURL(null);
  };

  return (
    <section className="flex flex-col gap-3">
      <h3 className="font-medium text-sm">{label}</h3>
      <ErrorAlert message={photo.activity.error} />
      {pickedURL ? (
        <CircleCropper
          imageURL={pickedURL}
          busy={busy}
          onCancel={() => setPickedURL(null)}
          onSave={save}
        />
      ) : (
        <div className="flex items-center gap-4">
          <Avatar avatar={avatar} large className="size-20" />
          <div className="flex flex-wrap gap-2">
            <input
              ref={fileInput}
              type="file"
              accept={acceptedImageTypes}
              className="hidden"
              onChange={(event) => {
                const file = event.target.files?.[0];
                event.target.value = "";
                if (file) setPickedURL(URL.createObjectURL(file));
              }}
            />
            <Button
              type="button"
              variant="outline"
              disabled={busy}
              onClick={() => fileInput.current?.click()}
            >
              <ImageIcon />
              {avatar.photo ? "Change photo" : "Choose a photo"}
            </Button>
            {avatar.photo && (
              <Button
                type="button"
                variant="ghost"
                loading={busy}
                onClick={photo.remove}
              >
                <TrashIcon />
                Remove
              </Button>
            )}
          </div>
        </div>
      )}
    </section>
  );
}

function CircleCropper({
  imageURL,
  busy,
  onCancel,
  onSave,
}: {
  imageURL: string;
  busy: boolean;
  onCancel: () => void;
  onSave: (imageURL: string, area: CropArea) => void;
}) {
  const [crop, setCrop] = useState({ x: 0, y: 0 });
  const [zoom, setZoom] = useState(1);
  const [area, setArea] = useState<CropArea | null>(null);
  return (
    <div className="flex flex-col gap-3">
      <div className="relative h-72 overflow-hidden rounded-lg bg-muted">
        <Cropper
          image={imageURL}
          crop={crop}
          zoom={zoom}
          maxZoom={maxZoom}
          aspect={1}
          cropShape="round"
          showGrid={false}
          onCropChange={setCrop}
          onZoomChange={setZoom}
          onCropComplete={(_, pixels) => setArea(pixels)}
        />
      </div>
      <Label className="flex items-center gap-3 text-sm">
        Zoom
        <input
          type="range"
          className="flex-1 accent-primary"
          min={1}
          max={maxZoom}
          step={0.01}
          value={zoom}
          onChange={(event) => setZoom(Number(event.target.value))}
        />
      </Label>
      <div className="flex justify-end gap-2">
        <Button
          type="button"
          variant="ghost"
          disabled={busy}
          onClick={onCancel}
        >
          Cancel
        </Button>
        <Button
          type="button"
          loading={busy}
          disabled={!area}
          onClick={() => area && onSave(imageURL, area)}
        >
          Use photo
        </Button>
      </div>
    </div>
  );
}
