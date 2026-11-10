// With Reduce Motion, the video waits for a tap instead of playing on its own.
// A file of its own, so the content security policy in _headers allows no inline script.
if (matchMedia('(prefers-reduced-motion: reduce)').matches) {
  const video = document.getElementById('opening');
  video.removeAttribute('autoplay');
  video.pause();
  video.controls = true;
}
