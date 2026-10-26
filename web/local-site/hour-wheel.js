const sectors = [
  {
    id: "matins",
    label: "Matutinum",
    start: 0,
    end: 60,
  },
  {
    id: "lauds",
    label: "Laudes",
    start: 60,
    end: 90,
  },
  {
    id: "prime",
    label: "Prima",
    start: 90,
    end: 120,
  },
  {
    id: "terce",
    label: "Tertia",
    start: 120,
    end: 150,
  },
  {
    id: "sext",
    label: "Sexta",
    start: 150,
    end: 195,
  },
  {
    id: "none",
    label: "Nona",
    start: 195,
    end: 240,
  },
  {
    id: "vespers",
    label: "Vesperae",
    start: 240,
    end: 300,
  },
  {
    id: "compline",
    label: "Completorium",
    start: 300,
    end: 360,
  },
];

const ancientTimeMarkers = [
  ["VII", 7.5],
  ["VIII", 22.5],
  ["IX", 37.5],
  ["X", 52.5],
  ["XI", 67.5],
  ["XII", 82.5],
  ["I", 97.5],
  ["II", 112.5],
  ["III", 127.5],
  ["IV", 142.5],
  ["V", 157.5],
  ["VI", 172.5],
  ["VII", 187.5],
  ["VIII", 202.5],
  ["IX", 217.5],
  ["X", 232.5],
  ["XI", 247.5],
  ["XII", 262.5],
  ["I", 277.5],
  ["II", 292.5],
  ["III", 307.5],
  ["IV", 322.5],
  ["V", 337.5],
  ["VI", 352.5],
];

const geometry = {
  artworkExtent: 0.555,
  wheelRadius: 0.5,
  timeRingInnerRadius: 0.458,
  texturedSectorOuterRadius: 0.458,
  numeralRadius: 0.476,
  labelRadius: 0.535,
  selectedLabelRadius: 0.535,
  centerOpeningRadius: 0.084,
};

const palette = {
  light: {
    foreground: "#0f0f0f",
    timeRingFill: "#0f0f0f",
    timeRingNumeral: "#ebebeb",
    selectedLabel: "#ad1f17",
  },
  dark: {
    foreground: "#ebebeb",
    timeRingFill: "#0a0a0a",
    timeRingNumeral: "#ebebeb",
    selectedLabel: "#ad1f17",
  },
};

function radians(degrees) {
  return (degrees * Math.PI) / 180;
}

function centerAngle(sector) {
  return (sector.start + sector.end) / 2;
}

function normalizedRotation(degrees) {
  return ((degrees % 360) + 360) % 360;
}

function pointAt(angle, radius) {
  const value = radians(angle);
  return {
    x: radius * Math.sin(value),
    y: -radius * Math.cos(value),
  };
}

function sectorFor(id) {
  return sectors.find((sector) => sector.id === id) ?? sectors[0];
}

function loadImage(source) {
  return new Promise((resolve) => {
    const image = new Image();
    image.addEventListener("load", () => resolve(image), { once: true });
    image.addEventListener("error", () => resolve(null), { once: true });
    image.src = source;
  });
}

function mixChannel(from, to, progress) {
  return Math.round(from + (to - from) * progress);
}

function mixHex(from, to, progress) {
  const channels = [1, 3, 5].map((offset) =>
    mixChannel(
      Number.parseInt(from.slice(offset, offset + 2), 16),
      Number.parseInt(to.slice(offset, offset + 2), 16),
      progress,
    ),
  );
  return `rgb(${channels.join(", ")})`;
}

export class HourWheel {
  constructor(
    canvas,
    {
      artworkExtent = geometry.artworkExtent,
      labelRadius = geometry.labelRadius,
      labelScale = 1,
      selectedLabelRadius = geometry.selectedLabelRadius,
      selectedLabelScale = labelScale,
      tapestrySource = "./hour-wheel/tapestry-20260907.webp",
      wheelScale = 1,
    } = {},
  ) {
    this.canvas = canvas;
    this.context = canvas.getContext("2d");
    this.tapestrySource = tapestrySource;
    this.artworkExtent = artworkExtent;
    this.labelRadius = labelRadius;
    this.labelScale = labelScale;
    this.selectedLabelRadius = selectedLabelRadius;
    this.selectedLabelScale = selectedLabelScale;
    this.wheelScale = wheelScale;
    this.rotation = 0;
    this.selectedID = "matins";
    this.appearanceBlend = 0;
    this.tapestryImage = null;
    this.ready = this.prepare();
  }

  async prepare() {
    this.tapestryImage = await loadImage(this.tapestrySource);
    await document.fonts?.ready;
    this.resize();
  }

  resize() {
    const bounds =
      this.canvas.parentElement?.getBoundingClientRect() ??
      this.canvas.getBoundingClientRect();
    const pixelRatio = Math.min(window.devicePixelRatio || 1, 3);
    const width = Math.max(1, Math.round(bounds.width));
    const height = Math.max(1, Math.round(bounds.height));
    this.canvas.width = Math.round(width * pixelRatio);
    this.canvas.height = Math.round(height * pixelRatio);
    this.canvas.style.width = `${width}px`;
    this.canvas.style.height = `${height}px`;
    this.canvas.style.transform = `rotate(${this.rotation}deg)`;
    this.context.setTransform(pixelRatio, 0, 0, pixelRatio, 0, 0);
    this.context.imageSmoothingEnabled = true;
    this.context.imageSmoothingQuality = "high";
    this.draw();
  }

  targetRotation(id, reference = this.rotation) {
    const canonical = -centerAngle(sectorFor(id));
    const revolutions = Math.round((reference - canonical) / 360);
    return canonical + revolutions * 360;
  }

  hourAtPoint(clientX, clientY) {
    const bounds =
      this.canvas.parentElement?.getBoundingClientRect() ??
      this.canvas.getBoundingClientRect();
    const scale =
      Math.min(bounds.width, bounds.height) /
      (2 * geometry.artworkExtent);
    const x = (clientX - bounds.left - bounds.width / 2) / scale;
    const y = (clientY - bounds.top - bounds.height / 2) / scale;
    const radius = Math.hypot(x, y);
    if (
      radius < geometry.centerOpeningRadius ||
      radius > geometry.wheelRadius
    ) {
      return null;
    }

    const visualAngle = normalizedRotation(
      (Math.atan2(x, -y) * 180) / Math.PI,
    );
    const dialAngle = normalizedRotation(visualAngle - this.rotation);
    return sectorAtDialAngle(dialAngle).id;
  }

  setState({ rotation, selectedID, appearanceBlend }) {
    let needsRedraw = false;
    if (Number.isFinite(rotation) && rotation !== this.rotation) {
      this.rotation = rotation;
      this.canvas.style.transform = `rotate(${rotation}deg)`;
    }
    if (selectedID && selectedID !== this.selectedID) {
      this.selectedID = selectedID;
      needsRedraw = true;
    }
    if (Number.isFinite(appearanceBlend)) {
      const nextBlend = Math.min(1, Math.max(0, appearanceBlend));
      if (Math.abs(nextBlend - this.appearanceBlend) > 0.0005) {
        this.appearanceBlend = nextBlend;
        needsRedraw = true;
      }
    }
    if (needsRedraw) this.draw();
  }

  draw() {
    const { context } = this;
    const bounds =
      this.canvas.parentElement?.getBoundingClientRect() ??
      this.canvas.getBoundingClientRect();
    const width = bounds.width;
    const height = bounds.height;
    if (!width || !height) return;

    context.clearRect(0, 0, width, height);
    context.save();
    context.translate(width / 2, height / 2);
    const scale =
      Math.min(width, height) / (2 * this.artworkExtent);
    context.scale(scale, scale);
    this.drawArtwork(context);
    context.restore();
  }

  drawArtwork(context) {
    const colors = {
      foreground: mixHex(
        palette.light.foreground,
        palette.dark.foreground,
        this.appearanceBlend,
      ),
      timeRingFill: mixHex(
        palette.light.timeRingFill,
        palette.dark.timeRingFill,
        this.appearanceBlend,
      ),
      timeRingNumeral: palette.light.timeRingNumeral,
      selectedLabel: palette.light.selectedLabel,
    };

    context.save();
    context.scale(this.wheelScale, this.wheelScale);

    context.save();
    context.fillStyle = colors.timeRingFill;
    context.beginPath();
    context.arc(0, 0, geometry.wheelRadius, 0, Math.PI * 2);
    context.arc(
      0,
      0,
      geometry.timeRingInnerRadius,
      0,
      Math.PI * 2,
      true,
    );
    context.fill("evenodd");
    context.restore();

    this.drawTapestry(context);

    this.drawNumerals(context, colors.timeRingNumeral);
    context.restore();

    this.drawLabels(context, colors);
  }

  drawTapestry(context) {
    if (!this.tapestryImage) return;

    const radius = geometry.texturedSectorOuterRadius;
    // Match the native wheel: remove the source margin with 3.5% radial bleed,
    // and register the authored noon (180°) with Sexta / VI (172.5°).
    const imageRadius = radius * 1.035;
    context.save();
    context.beginPath();
    context.arc(0, 0, radius, 0, Math.PI * 2);
    context.clip();
    context.rotate(radians(centerAngle(sectorFor("sext")) - 180));
    context.drawImage(
      this.tapestryImage,
      -imageRadius,
      -imageRadius,
      imageRadius * 2,
      imageRadius * 2,
    );
    context.restore();
  }

  drawNumerals(context, fill) {
    context.save();
    context.fillStyle = fill;
    context.font = '0.027px "EB Garamond", Georgia, serif';
    context.textAlign = "center";
    context.textBaseline = "middle";
    for (const [numeral, angle] of ancientTimeMarkers) {
      const position = pointAt(angle, geometry.numeralRadius);
      context.save();
      context.translate(position.x, position.y);
      context.rotate(radians(angle));
      context.fillText(numeral, 0, 0);
      context.restore();
    }
    context.restore();
  }

  drawLabels(context, colors) {
    for (const sector of sectors) {
      const isSelected = sector.id === this.selectedID;
      const radius = isSelected
        ? this.selectedLabelRadius
        : this.labelRadius;
      const scale = isSelected
        ? this.selectedLabelScale
        : this.labelScale;
      const availableArc =
        radius *
        radians(Math.min(
          centerAngle(sector) - sector.start,
          sector.end - centerAngle(sector),
        ) * 2) *
        0.79;
      this.drawCurvedLabel(
        context,
        sector.label,
        centerAngle(sector),
        availableArc,
        isSelected
          ? colors.selectedLabel
          : colors.foreground,
        radius,
        scale,
      );
    }
  }

  drawCurvedLabel(
    context,
    text,
    center,
    availableArc,
    fill,
    radius = this.labelRadius,
    scale = this.labelScale,
  ) {
    const baseSize = 0.041 * scale;
    context.save();
    context.font = `${baseSize}px "EB Garamond", Georgia, serif`;
    const baseWidth = context.measureText(text).width;
    const fontSize = baseSize * Math.min(1, availableArc / baseWidth);
    context.font = `${fontSize}px "EB Garamond", Georgia, serif`;
    const widths = [...text].map(
      (character) => context.measureText(character).width,
    );
    const lineWidth = widths.reduce((sum, width) => sum + width, 0);
    const baselineRadius = radius - fontSize * 0.33;
    let advance = -lineWidth / 2;

    context.fillStyle = fill;
    context.textAlign = "center";
    context.textBaseline = "middle";
    for (let index = 0; index < text.length; index += 1) {
      const character = text[index];
      const glyphCenter = advance + widths[index] / 2;
      const angle = center + (glyphCenter / baselineRadius) * (180 / Math.PI);
      const position = pointAt(angle, baselineRadius);
      context.save();
      context.translate(position.x, position.y);
      context.rotate(radians(angle));
      context.fillText(character, 0, 0);
      context.restore();
      advance += widths[index];
    }
    context.restore();
  }
}

export function isWheelNightOffice(id) {
  return id === "matins" || id === "compline";
}

export function shortestWheelTarget(id, reference) {
  const sector = sectorFor(id);
  const canonical = -centerAngle(sector);
  const revolutions = Math.round((reference - canonical) / 360);
  return canonical + revolutions * 360;
}

export function wheelAngleFor(id) {
  return normalizedRotation(centerAngle(sectorFor(id)));
}

function sectorAtDialAngle(angle) {
  const normalized = normalizedRotation(angle);
  return (
    sectors.find(
      (sector) => normalized >= sector.start && normalized < sector.end,
    ) ?? sectors[0]
  );
}

export function wheelHourForRotation(rotation) {
  return sectorAtDialAngle(normalizedRotation(-rotation)).id;
}
