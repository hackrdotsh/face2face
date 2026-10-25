/** A region of the source image, in its natural pixels. */
export interface CropArea {
  x: number;
  y: number;
  width: number;
  height: number;
}

/** The server makes its own sizes, so a larger upload adds nothing. */
const maxOutputEdge = 2048;
const outputType = "image/jpeg";
const outputQuality = 0.92;

/** Draws the square `area` of the image at `imageURL` into a JPEG. */
export async function cropToSquare(
  imageURL: string,
  area: CropArea,
): Promise<Blob> {
  const image = new Image();
  image.src = imageURL;
  await image.decode();
  const edge = Math.min(Math.round(area.width), maxOutputEdge);
  const canvas = document.createElement("canvas");
  canvas.width = edge;
  canvas.height = edge;
  const context = canvas.getContext("2d");
  if (!context) throw new Error("This browser can't crop images.");
  context.drawImage(
    image,
    area.x,
    area.y,
    area.width,
    area.height,
    0,
    0,
    edge,
    edge,
  );
  return new Promise((resolve, reject) =>
    canvas.toBlob(
      (blob) =>
        blob
          ? resolve(blob)
          : reject(new Error("The photo could not be cropped.")),
      outputType,
      outputQuality,
    ),
  );
}
