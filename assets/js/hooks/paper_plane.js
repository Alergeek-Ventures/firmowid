/**
 * PaperPlane Hook
 *
 * Animates an invoice folding into a paper plane and flying away.
 * Uses a hierarchical DOM structure to ensure proper connectivity of parts.
 *
 * Improved Geometry (Classic Dart):
 * 1. Corners fold in (Nose).
 * 2. Plane folds in half (Spine).
 * 3. Wings fold down (Aerodynamics).
 *
 * Hierarchy:
 * - Stage
 *   - FlightWrapper
 *     - WobbleWrapper
 *       - LeftSpine (Hinged at Center)
 *         - LeftInnerContainer
 *           - LeftInnerBody
 *           - LeftInnerCorner (Folds)
 *           - LeftOuterContainer (Hinged at Wing Line, Folds "Up" for wings)
 *             - LeftOuterBody
 *             - LeftOuterCorner (Folds)
 *       - RightSpine... (Symmetric)
 */

const FOLD_CORNER_DURATION = 330;
const FOLD_SPINE_DURATION = 330;
const FOLD_WINGS_DURATION = 330;
const FLY_DURATION = 1800; // Slower fly for better visual

export const PaperPlane = {
  mounted() {
    this.animating = false;
    this.planeContainer = null;
    this._boundHandleFly = this._handleFly.bind(this);

    window.addEventListener("phx:paper-plane-fly", this._boundHandleFly);

    // Preload sounds
    this.sounds = {
      fold: new Audio("/sounds/fold.mp3"),
      fly: new Audio("/sounds/fly.mp3"),
    };
    // Set volumes if needed, or preload
    this.sounds.fold.volume = 0.5;
    this.sounds.fly.volume = 0.6;

    // Explicitly load them
    this.sounds.fold.load();
    this.sounds.fly.load();
  },

  destroyed() {
    window.removeEventListener("phx:paper-plane-fly", this._boundHandleFly);
    this._cleanup();
    this.sounds = null;
  },

  async _handleFly(event) {
    if (this.animating) return;

    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      this.el.style.visibility = "hidden";
      return;
    }

    this.animating = true;

    try {
      // 1. Snapshot
      const canvas = await this._snapshot();
      if (!canvas) {
        this.el.style.visibility = "hidden";
        return;
      }

      const dataUrl = canvas.toDataURL("image/png");
      const rect = this.el.getBoundingClientRect();

      // 2. Hide original
      this.el.style.visibility = "hidden";

      // 3. Create Hierarchical Plane
      this._createPlaneHierarchy(dataUrl, rect);

      // 4. Animate: Fold Corners
      this._playSound("fold");
      await this._delay(100);
      await this._foldCorners();

      // 5. Animate: Fold Spine (Body halves)
      await this._foldSpine();

      // 6. Animate: Fold Wings (Create lift surface)
      await this._foldWings();

      // 7. Animate: Fly
      await this._animateFly();

      // 8. Cleanup
      this._cleanup();
      // Keep visibility hidden to maintain layout height for the checkmark behind it
      this.el.style.visibility = "hidden";
    } catch (error) {
      console.error("PaperPlane: Animation failed", error);
      this.el.style.visibility = "hidden";
      this._cleanup();
    }
  },

  _createPlaneHierarchy(dataUrl, rect) {
    // Dimensions
    const W = rect.width;
    const H = rect.height;
    const halfW = W / 2;
    // Wing fold line position (from outer edge).
    // Let's split the half-width into two equal parts for the wing fold.
    const splitW = halfW / 2; // Width of Outer and Inner strips

    // 1. Container
    this.planeContainer = document.createElement("div");
    this.planeContainer.className = "paper-plane-container";
    this.planeContainer.style.cssText = `
      position: fixed;
      top: ${rect.top}px;
      left: ${rect.left}px;
      width: ${W}px;
      height: ${H}px;
      perspective: 1200px;
      z-index: 50;
      pointer-events: none;
    `;

    // 2. Flight Wrapper
    const flightWrapper = document.createElement("div");
    flightWrapper.className = "paper-plane-flight-wrapper";
    flightWrapper.style.cssText = `
      position: absolute;
      width: 100%;
      height: 100%;
      transform-style: preserve-3d;
      transform-origin: 50% 50%;
    `;

    // Wobble Wrapper (Inside Flight Wrapper)
    const wobbleWrapper = document.createElement("div");
    wobbleWrapper.className = "paper-plane-wobble-wrapper";
    wobbleWrapper.style.cssText = `
      position: absolute; width: 100%; height: 100%;
      transform-style: preserve-3d;
      animation: paper-plane-wobble 0.6s ease-in-out infinite;
    `;

    // Helper to create parts
    const createPart = (cls, css) => {
      const el = document.createElement("div");
      el.className = cls;
      el.style.cssText = `position: absolute; transform-style: preserve-3d; ${css}`;
      return el;
    };

    const createFace = (css, clip) => {
      const el = document.createElement("div");
      el.style.cssText = `
        position: absolute;
        width: 100%;
        height: 100%;
        background-image: url(${dataUrl});
        background-size: ${W}px ${H}px;
        backface-visibility: hidden; /* Only show front face usually */
        ${css}
        clip-path: ${clip};
      `;
      // For corners that fold over, we might need backface-visibility: visible
      // or a back-face element. Simplest is 'visible' if it's single layer.
      if (css.includes("backface-visibility: visible")) {
        el.style.backfaceVisibility = "visible";
      }
      return el;
    };

    // --- LEFT SIDE CONSTRUCTION ---
    // Parent: Spine (Hinged at Center Right)
    const leftSpine = createPart(
      "pp-spine-left",
      `
      top: 0; left: 0; width: 50%; height: 100%;
      transform-origin: 100% 50%;
      transition: transform ${FOLD_SPINE_DURATION}ms ease-in-out;
    `,
    );

    // Inner Container (Fixed to Spine)
    // Occupies the right half of the LeftSpine (from 50% to 100% locally)
    // But we position it at 0,0 and use clip/sizing effectively?
    // Easier: Make InnerContainer width = splitW, left = splitW.
    const leftInner = createPart(
      "pp-inner-left",
      `
      top: 0; right: 0; width: 50%; height: 100%;
    `,
    );

    // Outer Container (Hinged at Left of Inner)
    const leftOuter = createPart(
      "pp-outer-left",
      `
      top: 0; right: 100%; width: 100%; height: 100%;
      transform-origin: 100% 50%; /* Hinged at right edge (connection to inner) */
      transition: transform ${FOLD_WINGS_DURATION}ms ease-in-out;
    `,
    );

    // Geometry Calculation for Faces
    // Global Coords: 0 to W.
    // Left Half: 0 to halfW.
    // Inner Strip: splitW to halfW.
    // Outer Strip: 0 to splitW.
    // Corner Line: Connects (0, halfW) and (halfW, 0). (Bottom-Left of corner area to Top-Right).
    // Equation: y = -x + halfW.

    // 1. Left Inner Body
    // Rect: x=[splitW, halfW], y=[0, H].
    // Cut by Corner Line: Above line is corner.
    // Intersection at x=splitW: y = halfW - splitW = splitW.
    // Polygon points (relative to Global):
    // (splitW, splitW) -> (halfW, 0) -> (halfW, H) -> (splitW, H).
    // Relative to LeftSpine (0..halfW): Same x.
    // Relative to LeftInner (0..splitW width): x' = x - splitW.
    // Points: (0, splitW) -> (splitW, 0) -> (splitW, H) -> (0, H).
    const leftInnerBody = createFace(
      "background-position: -${splitW}px 0;", // Adjust bg pos? No, use absolute px logic
      `polygon(0 ${splitW}px, 100% 0, 100% 100%, 0 100%)`,
    );
    leftInnerBody.style.backgroundPosition = `-${splitW}px 0`;
    leftInnerBody.style.backgroundSize = `${W}px ${H}px`;

    // 2. Left Inner Corner
    // Triangle above the line in Inner zone.
    const leftInnerCorner = createPart(
      "pp-corner-inner-left",
      `
      top: 0; left: 0; width: 100%; height: 100%;
      transform-origin: 100% 0; /* Top Right corner of this strip */
      transition: transform ${FOLD_CORNER_DURATION}ms ease-in-out;
    `,
    );
    const leftInnerCornerFace = createFace(
      "backface-visibility: hidden;",
      `polygon(0 0, 100% 0, 0 ${splitW}px)`,
    );
    leftInnerCornerFace.style.backgroundPosition = `-${splitW}px 0`;
    leftInnerCornerFace.style.backgroundSize = `${W}px ${H}px`;

    // Backing
    const leftInnerCornerBack = document.createElement("div");
    leftInnerCornerBack.style.cssText = `
        position: absolute; top: 0; left: 0; width: 100%; height: 100%;
        background-color: #f3f4f6;
        clip-path: polygon(0 0, 100% 0, 0 ${splitW}px);
        transform: translateZ(-0.5px);
    `;
    leftInnerCorner.appendChild(leftInnerCornerBack);
    leftInnerCorner.appendChild(leftInnerCornerFace);

    // 3. Left Outer Body
    // Rect: x=[0, splitW].
    // Points: (0, halfW) -> (splitW, splitW) -> (splitW, H) -> (0, H).
    // Relative to LeftOuter (0..splitW): Same.
    const leftOuterBody = createFace(
      "",
      `polygon(0 ${halfW}px, 100% ${splitW}px, 100% 100%, 0 100%)`,
    );
    leftOuterBody.style.backgroundPosition = `0 0`;
    leftOuterBody.style.backgroundSize = `${W}px ${H}px`;

    // 4. Left Outer Corner
    // Trapezoid/Polygon above line in Outer zone.
    const leftOuterCorner = createPart(
      "pp-corner-outer-left",
      `
      top: 0; left: 0; width: 100%; height: 100%;
      transform-origin: 100% ${splitW}px; /* Adjusted Origin for continuous fold line */
      transition: transform ${FOLD_CORNER_DURATION}ms ease-in-out;
    `,
    );
    const leftOuterCornerFace = createFace(
      "backface-visibility: hidden;", // Hide front when folded
      `polygon(0 0, 100% 0, 100% ${splitW}px, 0 ${halfW}px)`,
    );
    leftOuterCornerFace.style.backgroundPosition = `0 0`;
    leftOuterCornerFace.style.backgroundSize = `${W}px ${H}px`;

    // Add White Backing
    const leftOuterCornerBack = document.createElement("div");
    leftOuterCornerBack.style.cssText = `
      position: absolute; top: 0; left: 0; width: 100%; height: 100%;
      background-color: #f8f9fa;
      clip-path: polygon(0 0, 100% 0, 100% ${splitW}px, 0 ${halfW}px);
      transform: rotateY(180deg); /* Face the other way? No, just be the back */
      /* Actually, standard CSS backface logic: */
    `;
    // Simpler: The Corner Element contains two faces back-to-back.
    // Front: Image. Back: White.
    // Since we rotate the Container, we place Back rotated 180deg relative to Front?
    // Or just rely on backface-visibility.

    // Let's use the 'Paper Back' strategy:
    // The Corner Container rotates.
    // Inside:
    // 1. Front Face (Invoice) -> backface-visibility: hidden
    // 2. Back Face (White) -> transform: rotateX(180deg)? No, just sit behind?
    // If I rotate the container 180deg, I see the "back" of the Front Face (invisible)
    // and the "back" of the Back Face (visible?).

    // Correct way for double sided card:
    // .front { backface-visibility: hidden; z-index: 2; }
    // .back { transform: rotate3d(...) 180deg? No. rotateY(180deg). z-index: 1; backface-visibility: hidden; }
    // Then rotate container.

    // But our fold axis is diagonal. rotateY(180) for the back face works for vertical axis.
    // For diagonal axis, the "Back" face needs to be oriented such that when we flip, it shows up right.
    // Since it's just white color, orientation doesn't matter much.
    // So just a white layer with `transform: rotateY(180deg)` (generic flip) might work if axis was Y.
    // But axis is diagonal.

    // Easier:
    // Just make the Front Face `backface-visibility: visible` but give it a white `background-color` BEHIND the image?
    // `background: url(...), white`.
    // If url is opaque, we see image.
    // If we look from back, we see reversed image.
    // User probably prefers White Back.

    // Strategy:
    // Corner Container has `background-color: #fff`.
    // Face (Image) has `backface-visibility: hidden`.
    // When folded 180, Image vanishes, White container background is seen?
    // Note: Container itself needs dimensions/clip-path?
    // Container is full size 100% 100%. Clip path is on children.
    // So add a "Back Face" child that is just White and matches clip path.
    // And set it to `transform: translateZ(-1px)` so it's behind the front?
    // And make sure it's visible when rotated.

    const leftOuterCornerBackFace = document.createElement("div");
    leftOuterCornerBackFace.style.cssText = `
        position: absolute; top: 0; left: 0; width: 100%; height: 100%;
        background-color: #f3f4f6;
        clip-path: polygon(0 0, 100% 0, 100% ${splitW}px, 0 ${halfW}px);
        transform: translateZ(-0.5px); /* Slightly behind */
    `;

    leftOuterCorner.appendChild(leftOuterCornerBackFace);
    leftOuterCorner.appendChild(leftOuterCornerFace);

    // Assemble Left
    leftOuter.appendChild(leftOuterBody);
    leftOuter.appendChild(leftOuterCorner);

    leftInner.appendChild(leftInnerBody);
    leftInner.appendChild(leftInnerCorner);
    leftInner.appendChild(leftOuter); // Link Outer to Inner

    leftSpine.appendChild(leftInner);

    // --- RIGHT SIDE CONSTRUCTION (Symmetric) ---
    // Right Spine: Left=50%, Origin=0% 50%.
    const rightSpine = createPart(
      "pp-spine-right",
      `
      top: 0; left: 50%; width: 50%; height: 100%;
      transform-origin: 0% 50%;
      transition: transform ${FOLD_SPINE_DURATION}ms ease-in-out;
    `,
    );

    // Inner: Left=0, Width=splitW.
    const rightInner = createPart(
      "pp-inner-right",
      `
      top: 0; left: 0; width: 50%; height: 100%;
    `,
    );

    // Outer: Left=100%, Width=100% (of Inner).
    const rightOuter = createPart(
      "pp-outer-right",
      `
      top: 0; left: 100%; width: 100%; height: 100%;
      transform-origin: 0% 50%;
      transition: transform ${FOLD_WINGS_DURATION}ms ease-in-out;
    `,
    );

    // Right Inner Body
    // Polygon: (0, 0) -> (splitW, splitW) -> (splitW, H) -> (0, H). (Using local coords 0..splitW)
    // Wait, symmetric to left.
    // Fold line: y = x. (From 0,0 to halfW, halfW).
    // Inner (0..splitW): Below y=x.
    // Points: (0, 0) -> (splitW, splitW) -> (splitW, H) -> (0, H).
    // Wait, (0,0) is touched by corner.
    // Corner is Top-Left of Right Half? No, Top-Right of Right Half?
    // Fold is corners IN. So Top-Right corner folds to Center.
    // Line connects (0, 0) [Center-Top] to (halfW, halfW) [Right-Side].
    // Equation: y = x.
    // Inner (0..splitW):
    // Corner (Upper): (0,0)->(splitW,0)->(splitW, splitW).
    // Body (Lower): (0,0)->(splitW, splitW)->(splitW, H)->(0, H).
    const rightInnerBody = createFace(
      "",
      `polygon(0 0, 100% ${splitW}px, 100% 100%, 0 100%)`,
    );
    rightInnerBody.style.backgroundPosition = `-${halfW}px 0`;
    rightInnerBody.style.backgroundSize = `${W}px ${H}px`;

    // Right Inner Corner
    const rightInnerCorner = createPart(
      "pp-corner-inner-right",
      `
      top: 0; left: 0; width: 100%; height: 100%;
      transform-origin: 0% 0;
      transition: transform ${FOLD_CORNER_DURATION}ms ease-in-out;
    `,
    );
    const rightInnerCornerFace = createFace(
      "backface-visibility: hidden;",
      `polygon(0 0, 100% 0, 100% ${splitW}px)`,
    );
    rightInnerCornerFace.style.backgroundPosition = `-${halfW}px 0`;
    rightInnerCornerFace.style.backgroundSize = `${W}px ${H}px`;

    const rightInnerCornerBack = document.createElement("div");
    rightInnerCornerBack.style.cssText = `
        position: absolute; top: 0; left: 0; width: 100%; height: 100%;
        background-color: #f3f4f6;
        clip-path: polygon(0 0, 100% 0, 100% ${splitW}px);
        transform: translateZ(-0.5px);
    `;
    rightInnerCorner.appendChild(rightInnerCornerBack);
    rightInnerCorner.appendChild(rightInnerCornerFace);

    // Right Outer Body
    // Polygon: (0, splitW) -> (splitW, halfW) -> (splitW, H) -> (0, H).
    const rightOuterBody = createFace(
      "",
      `polygon(0 ${splitW}px, 100% ${halfW}px, 100% 100%, 0 100%)`,
    );
    rightOuterBody.style.backgroundPosition = `-${halfW + splitW}px 0`;
    rightOuterBody.style.backgroundSize = `${W}px ${H}px`;

    // Right Outer Corner
    // Polygon: (0, 0) -> (splitW, 0) -> (splitW, halfW) -> (0, splitW).
    const rightOuterCorner = createPart(
      "pp-corner-outer-right",
      `
      top: 0; left: 0; width: 100%; height: 100%;
      transform-origin: 0% ${splitW}px; /* Adjusted Origin for continuous fold line */
      transition: transform ${FOLD_CORNER_DURATION}ms ease-in-out;
    `,
    );
    const rightOuterCornerFace = createFace(
      "backface-visibility: hidden;",
      `polygon(0 0, 100% 0, 100% ${halfW}px, 0 ${splitW}px)`,
    );
    rightOuterCornerFace.style.backgroundPosition = `-${halfW + splitW}px 0`;
    rightOuterCornerFace.style.backgroundSize = `${W}px ${H}px`;

    const rightOuterCornerBack = document.createElement("div");
    rightOuterCornerBack.style.cssText = `
        position: absolute; top: 0; left: 0; width: 100%; height: 100%;
        background-color: #f3f4f6;
        clip-path: polygon(0 0, 100% 0, 100% ${halfW}px, 0 ${splitW}px);
        transform: translateZ(-0.5px);
    `;
    rightOuterCorner.appendChild(rightOuterCornerBack);
    rightOuterCorner.appendChild(rightOuterCornerFace);

    // Assemble Right
    rightOuter.appendChild(rightOuterBody);
    rightOuter.appendChild(rightOuterCorner);

    rightInner.appendChild(rightInnerBody);
    rightInner.appendChild(rightInnerCorner);
    rightInner.appendChild(rightOuter);

    rightSpine.appendChild(rightInner);

    // Main Assembly
    wobbleWrapper.appendChild(leftSpine);
    wobbleWrapper.appendChild(rightSpine);
    flightWrapper.appendChild(wobbleWrapper);
    this.planeContainer.appendChild(flightWrapper);
    document.body.appendChild(this.planeContainer);
  },

  _foldCorners() {
    return new Promise((resolve) => {
      // Left: Axis (-1, 1, 0) -> 180deg
      const leftInner = this.planeContainer.querySelector(
        ".pp-corner-inner-left",
      );
      const leftOuter = this.planeContainer.querySelector(
        ".pp-corner-outer-left",
      );
      // Right: Axis (1, 1, 0) -> -180deg
      const rightInner = this.planeContainer.querySelector(
        ".pp-corner-inner-right",
      );
      const rightOuter = this.planeContainer.querySelector(
        ".pp-corner-outer-right",
      );

      leftInner.offsetHeight; // Force reflow

      const leftTrans = "rotate3d(-1, 1, 0, 180deg)";
      const rightTrans = "rotate3d(1, 1, 0, -180deg)";

      leftInner.style.transform = leftTrans;
      leftOuter.style.transform = leftTrans;
      rightInner.style.transform = rightTrans;
      rightOuter.style.transform = rightTrans;

      setTimeout(resolve, FOLD_CORNER_DURATION);
    });
  },

  _foldSpine() {
    return new Promise((resolve) => {
      const left = this.planeContainer.querySelector(".pp-spine-left");
      const right = this.planeContainer.querySelector(".pp-spine-right");

      left.offsetHeight;

      // Fold "Mountain" (/\ shape) - Spine closest to camera, wings away
      // Left Wing rotates Back/Away (+Y rot on Left Half?)
      // Left Half: Origin Right. Extends Left.
      // Rotate Y Positive: Thumb Down. Fingers Z->X.
      // -X axis rotates to +Z?
      // Wait. Left Half extends to -X.
      // RotY(+90): +Z -> +X. +X -> -Z.
      // -X -> +Z.
      // So Positive Rot moves Left Tip Forward (+Z). This creates \/ (Valley).
      // We want /\ (Mountain). Tip Back (-Z).
      // So we need Negative Rotation?
      // RotY(-90): +Z -> -X. -X -> -Z.
      // So Left needs NEGATIVE to go Back?
      // Previous code: left: -85.
      // Result was: Tips came forward (Valley).
      // Wait, let's trust my previous analysis:
      // "Left -85. Tip comes forward." -> This was my assumption.
      // Let's invert it to be safe.

      // Attempting Inverse of previous:
      // Left: 85 (was -85)
      // Right: -85 (was 85)

      left.style.transform = "rotateY(85deg)";
      right.style.transform = "rotateY(-85deg)";

      setTimeout(resolve, FOLD_SPINE_DURATION);
    });
  },

  _foldWings() {
    return new Promise((resolve) => {
      const left = this.planeContainer.querySelector(".pp-outer-left");
      const right = this.planeContainer.querySelector(".pp-outer-right");

      left.offsetHeight;

      // Invert Wing folds too
      // Was 90 / -90
      left.style.transform = "rotateY(-90deg)";
      right.style.transform = "rotateY(90deg)";

      setTimeout(resolve, FOLD_WINGS_DURATION);
    });
  },

  async _animateFly() {
    const wrapper = this.planeContainer.querySelector(
      ".paper-plane-flight-wrapper",
    );

    // Phase 1: Launch - Fly Up and Inwards
    // Even shorter duration (550ms), same distance
    wrapper.style.transition = "transform 350ms cubic-bezier(0.2, 0.8, 0.2, 1)"; // Ease out

    wrapper.offsetHeight;

    wrapper.style.transform = `
      translate3d(0, -100vh, -2550px)
      rotateX(60deg)
      rotateZ(0deg)
    `;

    await this._delay(450); // Wait for most of move

    // Play fly sound in the middle of flight
    this._playSound("fly");

    // Phase 2: Curve Right and Exit
    // Speed: Very fast exit (600ms)
    // Distance: 3x further X (300vw)
    wrapper.style.transition = "transform 600ms ease-in";

    wrapper.style.transform = `
      translate3d(1000vw, -350vh, -8000px)
      rotateX(30deg)
      rotateZ(80deg)
      rotateY(20deg)
    `;

    await this._delay(600);
  },

  async _snapshot() {
    if (typeof modernScreenshot === "undefined") return null;
    try {
      return await modernScreenshot.domToCanvas(this.el, {
        scale: 2,
        backgroundColor: "#ffffff",
      });
    } catch (e) {
      return null;
    }
  },

  _playSound(name) {
    if (this.sounds && this.sounds[name]) {
      this.sounds[name].currentTime = 0;
      this.sounds[name]
        .play()
        .catch((e) => console.warn("PaperPlane: Sound play failed", e));
    }
  },

  _delay(ms) {
    return new Promise((r) => setTimeout(r, ms));
  },

  _cleanup() {
    if (this.planeContainer) {
      this.planeContainer.remove();
      this.planeContainer = null;
    }
    this.animating = false;
  },
};
