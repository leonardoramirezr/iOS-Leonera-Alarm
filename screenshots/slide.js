// Fits each device frame to its capture's aspect ratio and, while a capture is
// missing from captures/, shows which file the slide expects.
for (const img of document.querySelectorAll(".frame .screen")) {
  const frame = img.closest(".frame");
  const file = img.getAttribute("src");

  const fit = () => {
    frame.classList.remove("missing");
    frame.style.setProperty("--screen-ar", `${img.naturalWidth} / ${img.naturalHeight}`);
  };
  const markMissing = () => {
    frame.classList.add("missing");
    if (!frame.querySelector(".placeholder")) {
      const note = document.createElement("div");
      note.className = "placeholder";
      note.textContent = `Missing capture: screenshots/${file}`;
      frame.append(note);
    }
  };

  img.addEventListener("load", fit);
  img.addEventListener("error", markMissing);
  if (img.complete) {
    img.naturalWidth ? fit() : markMissing();
  }
}
