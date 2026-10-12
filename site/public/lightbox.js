// Open landing screenshots in a full-screen overlay; without JavaScript the
// links still open the original WebP in the browser.
(() => {
  let overlay = null;
  const close = () => {
    if (!overlay) return;
    overlay.remove();
    overlay = null;
    document.documentElement.style.removeProperty('overflow');
  };
  const open = (href, alt) => {
    close();
    overlay = document.createElement('div');
    overlay.className = 'etaf-lightbox';
    const image = document.createElement('img');
    image.src = href;
    image.alt = alt;
    overlay.append(image);
    overlay.addEventListener('click', close);
    document.documentElement.style.overflow = 'hidden';
    document.body.append(overlay);
  };
  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') close();
  });
  document.addEventListener('click', (event) => {
    const link = event.target.closest('.etaf-shots a.etaf-shot-link');
    if (!link) return;
    event.preventDefault();
    const image = link.querySelector('img');
    open(link.getAttribute('href'), image ? image.alt : '');
  });
})();
