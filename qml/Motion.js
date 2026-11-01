// Omarchy 4.0 predates animation settings; newer shells supply the preference.
function duration(style, milliseconds) {
  if (style.reduceMotion === true) return 0
  return typeof style.duration === "function" ? style.duration(milliseconds) : milliseconds
}
